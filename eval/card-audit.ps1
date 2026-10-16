# ai工作医生 · 常驻卡机械审计
#
# 作用：把「反膨胀」里能机械判定的部分自动化。
#   ERROR（会让 CI 红）：整卡超过 30 行（含 2 行标记）· 卡内出现代码块 · 编号规则没有数字上限 · 编号规则条数异常
#   WARN （只提示）    ：编号规则没有「机械可读回执」——有些规则靠散文描述证据，这不算错，但值得盯
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\eval\card-audit.ps1
#   powershell -ExecutionPolicy Bypass -File .\eval\card-audit.ps1 -SelfTest
param(
    [string]$SkillPath = "",
    [int]$MinRules = 10,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Get-Card {
    param([string]$text)
    $m = [regex]::Match($text, '(?s)<!--\s*AIW_CORE:START\s*-->(.*?)<!--\s*AIW_CORE:END\s*-->')
    if (-not $m.Success) { return $null }
    return $m.Groups[1].Value
}

function Test-Card {
    param([string]$card, [int]$MinRules = 10)
    $errors = New-Object System.Collections.ArrayList
    $warns = New-Object System.Collections.ArrayList
    $rawLines = @($card -split "`r?`n")
    $lines = @($rawLines | Where-Object { $_.Trim() -ne '' })
    $ruleLines = @($lines | Where-Object { $_ -match '^\s*\d+\.\s' })

    # 与 CI 同口径：标记块总行数（含 START/END 两行）
    $blockLines = $rawLines.Count   # 与 CI 的 sed -n '/START/,/END/p' | wc -l 同口径
    if ($blockLines -gt 30) { [void]$errors.Add("标记块 $blockLines 行 > 30 行硬顶") }
    if ($ruleLines.Count -lt $MinRules) { [void]$errors.Add("编号规则只有 $($ruleLines.Count) 条（期望 ≥$MinRules），疑似被截断") }
    if ($card -match '(?m)^\s*```') { [void]$errors.Add('卡内出现代码块（CONTRIBUTING 第 2 条禁止）') }

    $detail = foreach ($ln in $ruleLines) {
        $no = [regex]::Match($ln, '^\s*(\d+)\.').Groups[1].Value
        $title = [regex]::Match($ln, '^\s*\d+\.\s*\*\*(.+?)\*\*').Groups[1].Value
        $body = $ln -replace '^\s*\d+\.\s*', ''   # 先剥掉行首编号，否则编号本身会被当成数字上限
        $hasNumber = ($body -match '\d') -or ($body -match '[一二三四五六七八九十两]\s*(条|次|个|行|句|轮|块|步|处|种|遍|分|秒|页|项|层|家|台|份|段|字节)') -or ($body -match '为空|必须|先备份|禁止|等用户确认|等确认|才算|不算|清单|逐条|0 命中|≥|≤|>=')
        # 机械可读回执：反引号里的固定串 / 固定格式（at N、m/N）/ 明确判定式（≤、0 命中…）
        $hasReceipt = ($ln -match '`[^`]*[A-Z]{2,}[^`]*`') -or ($ln -match 'at N|m/N|\d+\s*/\s*\d+') -or ($ln -match '≤|>=|0 命中|0 个|0 行|0 句|0 块')
        if (-not $hasNumber) { [void]$errors.Add("第 $no 条「$title」：缺数字上限") }
        if (-not $hasReceipt) { [void]$warns.Add("第 $no 条「$title」：没有机械可读回执（靠散文描述证据，建议补一个固定串）") }
        [pscustomobject]@{
            条 = $no; 标题 = $title
            数字 = $(if ($hasNumber) { 'OK' } else { 'X' })
            回执 = $(if ($hasReceipt) { 'OK' } else { '!' })
            字符 = $ln.Length
        }
    }
    return @{ Errors = $errors; Warns = $warns; Detail = $detail; Lines = $lines.Count; BlockLines = $blockLines; Rules = $ruleLines.Count; Chars = $card.Length }
}

if ($SelfTest) {
    Write-Host '=== 自测：抓得住坏规则，不误伤好规则 ===' -ForegroundColor Cyan
    $bad = @(
        '<!-- AIW_CORE:START -->',
        '1. **想清楚一点**：要认真对待用户的需求，避免犯错，注意细节。',
        '2. **注意安全**：删除文件前请谨慎，尽量不要误操作。',
        '<!-- AIW_CORE:END -->'
    ) -join "`n"
    $good = @(
        '<!-- AIW_CORE:START -->',
        '1. **空转熔断**：连续 2 个工具调用没有新信息 → 打印 `LOOP at N: <动作> x2` 并换维度。',
        '2. **交付对账**：说"完成"必须贴本会话真实命令与原样输出；用户列了 N 条就逐条回抄 N 条；新增行里 TODO 须 0 命中。',
        '<!-- AIW_CORE:END -->'
    ) -join "`n"
    $rb = Test-Card (Get-Card $bad) -MinRules 2
    $rg = Test-Card (Get-Card $good) -MinRules 2
    "  坏样本：ERROR $($rb.Errors.Count)（期望 2）· WARN $($rb.Warns.Count)"
    $rb.Errors | ForEach-Object { "    ERROR - $_" }
    "  好样本：ERROR $($rg.Errors.Count)（期望 0）· WARN $($rg.Warns.Count)（期望 0）"
    $rg.Warns | ForEach-Object { "    WARN - $_" }
    $ok = ($rb.Errors.Count -eq 2) -and ($rg.Errors.Count -eq 0) -and ($rg.Warns.Count -eq 0)
    Write-Host ("  自测结论：{0}" -f $(if ($ok) { 'PASS' } else { 'FAIL' })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    Write-Output ("SELFTEST: " + $(if ($ok) { 'PASS' } else { 'FAIL' }))   # ASCII 结论行，供 CI 断言（runner 临时脚本无 BOM，中文串会被按 ANSI 解码）
    if (-not $ok) { exit 1 }
    return
}

if (-not $SkillPath) {
    $here = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
    $SkillPath = Join-Path $here 'SKILL.md'
}
$card = Get-Card ([IO.File]::ReadAllText($SkillPath))
if (-not $card) { Write-Host "找不到 AIW_CORE 标记块：$SkillPath" -ForegroundColor Red; exit 1 }

$r = Test-Card $card -MinRules $MinRules
Write-Host ("`n常驻卡审计：{0}" -f $SkillPath) -ForegroundColor Cyan
Write-Host ("  标记块 {0} 行（CI 口径，硬顶 30）· 内容 {1} 行 · 编号规则 {2} 条 · 正文字符 {3}（约 {4} tokens/轮）" -f $r.BlockLines, $r.Lines, $r.Rules, $r.Chars, [int]($r.Chars / 1.6))
$r.Detail | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
if ($r.Warns.Count -gt 0) {
    Write-Host ("  WARN {0} 条（不阻塞，但值得补固定回执）：" -f $r.Warns.Count) -ForegroundColor Yellow
    $r.Warns | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
}
Write-Output ("ERRORS: " + $r.Errors.Count)   # ASCII 结论行，供 CI 断言
if ($r.Errors.Count -eq 0) {
    Write-Host '  ERROR：0（每条规则都有数字上限，卡长在硬顶之内，无代码块）' -ForegroundColor Green
} else {
    Write-Host ("  ERROR {0} 条：" -f $r.Errors.Count) -ForegroundColor Red
    $r.Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    exit 1
}
