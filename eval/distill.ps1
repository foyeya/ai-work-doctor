# ai工作医生 · 蒸馏回路（distill）
#
# 目的：把"模型真实的翻车现场"蒸成"下一版卡里的规则"。
# 一个提示词插件改不了模型权重，但它可以**从使用痕迹里持续长规则**——
# 这正是"让任意模型越用越顺手"唯一诚实的实现路径。
#
# 流程：扫会话 → 机械判失败类 → 汇总证据 → 生成提案（带验证要求）→ 人来批 → 进卡 → 探针回归
#
# 用法：
#   powershell -File .\eval\distill.ps1                                  # 扫最近 7 天会话，出提案
#   powershell -File .\eval\distill.ps1 -SinceDays 30 -Max 100
#   powershell -File .\eval\distill.ps1 -Sessions "D:\some\sessions" -Out .\eval\proposals\2026-10-18.md
#   powershell -File .\eval\distill.ps1 -SelfTest                        # 自证：脏会话必须产出建议
#
# 提案里每条建议都带「验证方式」：必须能过某个探针或让检测器归零，否则不进卡（防止拍脑袋加规则）。
param(
    [string]$Sessions = "",
    [int]$SinceDays = 7,
    [int]$Max = 50,
    [string]$Out = "",
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'session-lib.ps1')

function Get-CardGeneration {
    param([string]$Raw)
    if ($Raw -match '扫描/枚举/全盘') { return 'v2.10+' }
    if ($Raw -match '测试红了先判谁错') { return 'v2.9' }
    if ($Raw -match '即使用户明说') { return 'v2.9' }
    if ($Raw -match '先复现再修') { return 'v2.7-2.8' }
    if ($Raw -match '常驻卡') { return 'v2.0-2.6' }
    return '无卡'
}

function Get-SessionRecords {
    param([string]$Root, [int]$Days, [int]$Limit)
    $cut = (Get-Date).AddDays(-$Days)
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'session.v4.jsonl*' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $cut } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First $Limit)
    $recs = New-Object System.Collections.ArrayList
    foreach ($f in $files) {
        try {
            $raw = Expand-SessionFile $f.FullName
            $meta = Get-SessionMeta $raw
            $ev = ConvertFrom-JsonlText $raw
            if ($ev.Count -eq 0) { continue }
            $r = Test-SessionEvents -Events $ev
            [void]$recs.Add([pscustomobject]@{
                File   = $f.FullName
                Id     = if ($meta.Id) { $meta.Id } else { $f.Directory.Name }
                Cwd    = $meta.Cwd
                Card   = Get-CardGeneration $raw
                When   = $f.LastWriteTime
                Sec    = [math]::Round($r.TotalSec, 0)
                Calls  = $r.Calls
                Errors = $r.Errors
                Waits  = $r.Waits
                Silent = $r.MaxSilent
                Waste  = [math]::Round($r.WasteSec, 0)
                HFs    = @($r.HardFail)
            })
        } catch {
            Write-Host ("  跳过（解析失败）：{0} — {1}" -f $f.Name, $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }
    return @($recs)
}

function New-Proposal {
    param($Records, [int]$Days)

    $isNew = { param($x) $x.Card -eq 'v2.10+' }
    $hf1 = @($Records | Where-Object { $_.HFs -match 'HF1' })
    $hf2 = @($Records | Where-Object { $_.HFs -match 'HF2' })
    $hf3 = @($Records | Where-Object { $_.HFs -match 'HF3' })
    $errHeavy = @($Records | Where-Object { $_.Calls -ge 5 -and ($_.Errors / [math]::Max($_.Calls, 1)) -ge 0.4 })
    $totalSec = ($Records | Measure-Object Sec -Sum).Sum
    $wasteSec = ($Records | Measure-Object Waste -Sum).Sum

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("# ai工作医生 · 蒸馏提案（$(Get-Date -Format 'yyyy-MM-dd HH:mm')）")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine("采样范围：最近 $Days 天，$($Records.Count) 个会话。总时长 $([math]::Round($totalSec,0)) 秒，其中超时浪费 $([math]::Round($wasteSec,0)) 秒。")
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 证据')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| 会话 | 卡版本 | 时长s | 调用 | 报错 | wait | 最长静默 | 浪费s | 命中 |')
    [void]$sb.AppendLine('|---|---|---|---|---|---|---|---|---|')
    foreach ($r in ($Records | Sort-Object Waste -Descending | Select-Object -First 12)) {
        $hit = if ($r.HFs.Count) { ($r.HFs | ForEach-Object { ($_ -split ' ')[0] }) -join ',' } else { '—' }
        [void]$sb.AppendLine(("| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} |" -f $r.Id.Substring(0, [Math]::Min(13, $r.Id.Length)), $r.Card, $r.Sec, $r.Calls, $r.Errors, $r.Waits, $r.Silent, $r.Waste, $hit))
    }
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('## 建议改动')
    [void]$sb.AppendLine('')

    $n = 0
    if ($hf1.Count -gt 0) {
        $n++
        [void]$sb.AppendLine("### $n. HF1 长阻塞仍出现（$($hf1.Count)/$($Records.Count) 个会话）")
        [void]$sb.AppendLine('- 现状：卡第 7 条已写「扫描/枚举/全盘/句柄类硬上限 20 秒」，但仍出现单次 ≥120 秒调用。')
        [void]$sb.AppendLine('- 建议：把"例外"进一步收紧——**任何 ≥60 秒的命令必须先转后台**，并对该 job **最多非阻塞轮询 1 次**；不得用 `wait=true` 阻塞等。')
        [void]$sb.AppendLine('- 验证：`session-audit.ps1` 对同批会话重跑，HF1 归零；`cap-gate.ps1 -SelfTest` 不退化。')
        [void]$sb.AppendLine('')
    }
    if ($hf2.Count -gt 0) {
        $n++
        [void]$sb.AppendLine("### $n. HF2 干等仍出现（$($hf2.Count)/$($Records.Count) 个会话）")
        [void]$sb.AppendLine('- 现状：卡第 7 条已写「`wait=true` 只准等 1 次」，仍出现 ≥2 次。')
        [void]$sb.AppendLine('- 建议：升级为 **禁止 `wait=true`**，改用 `wait=false` 轮询（间隔 ≥2 秒、最多 3 次），拿不到输出就直接给结论。')
        [void]$sb.AppendLine('- 验证：同批会话 HF2 归零；且不得因此让任务被判"未完成"（人工抽 2 个会话确认结论仍给出）。')
        [void]$sb.AppendLine('')
    }
    if ($hf3.Count -gt 0) {
        $n++
        [void]$sb.AppendLine("### $n. HF3 静默空转仍出现（$($hf3.Count)/$($Records.Count) 个会话）——**这是当前最硬的问题**")
        [void]$sb.AppendLine('- 现状：卡第 11 条写了「连续 5 步没有对外文字 → 先输出一句进展」，实测被无视；persona 里的 `[STAGE]` 也没执行。')
        [void]$sb.AppendLine('- 建议：把这条从第 11 条（末尾）**前移到第 2 条**（诊断纪律，位置早、更易被遵守），第 11 条只留交付格式。')
        [void]$sb.AppendLine('- 验证：新会话 HF3 归零；若前移后仍无效，说明提示层约束力不足，应改宿主层（每 N 步强制摘要）。')
        [void]$sb.AppendLine('')
    }
    if ($errHeavy.Count -gt 0) {
        $n++
        [void]$sb.AppendLine("### $n. 报错率偏高（$($errHeavy.Count)/$($Records.Count) 个会话 ≥40%）")
        [void]$sb.AppendLine('- 建议：第 1 条补一句——**同一命令失败 2 次先查环境（路径/编码/权限/工具是否存在），不要改参数硬试**。')
        [void]$sb.AppendLine('- 验证：重跑这批任务，报错率下降且总调用数不增加；`session-audit` HF1/HF3 不退化。')
        [void]$sb.AppendLine('')
    }
    if ($n -eq 0) {
        [void]$sb.AppendLine('本期没有命中任何失败类——**不要为了改而改**。把样本量加大（`-SinceDays 30`）再跑。')
        [void]$sb.AppendLine('')
    }

    [void]$sb.AppendLine('## 入库规则（防止越改越糟）')
    [void]$sb.AppendLine('1. 每条建议**只能改一处措辞**，改完跑 `card-audit.ps1`（结构 + 19 条语义条款）与全部 `-SelfTest`。')
    [void]$sb.AppendLine('2. 必须说明它修复的是**哪一次真实事故**（带会话 ID 与数字），否则不进卡。')
    [void]$sb.AppendLine('3. 改完用同批会话复跑 `distill.ps1`，**命中数下降**才算生效；不降就回滚。')
    [void]$sb.AppendLine('4. 卡长只减不增优先；必须增时，先证明它换回的失败次数 > 新增 token 成本。')

    return $sb.ToString()
}

if ($SelfTest) {
    Write-Host '=== 自测：脏会话必须产出建议，干净会话必须"不要为了改而改" ===' -ForegroundColor Cyan
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('aiw_distill_' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $t0 = 1792260709000

    function Write-FakeSession {
        param([string]$Dir, [string]$Id, [bool]$Dirty)
        New-Item -ItemType Directory -Force -Path $Dir | Out-Null
        $lines = New-Object System.Collections.ArrayList
        [void]$lines.Add((@{ type = 'session'; id = $Id; cwd = 'C:\fake'; agentPreset = 'standard' } | ConvertTo-Json -Compress))
        $seq = 1; $t = $t0
        if ($Dirty) {
            for ($i = 1; $i -le 6; $i++) {
                [void]$lines.Add((@{ type = 'tool/call'; seq = $seq; time = $t; data = @{ name = 'pwsh'; arguments = @{ command = 'x' } } } | ConvertTo-Json -Depth 6 -Compress)); $seq++; $t += 1500
                [void]$lines.Add((@{ type = 'tool/result'; seq = $seq; time = $t; data = @{ message = @{ content = @(@{ type = 'text'; text = 'ok' }); isError = $false } } } | ConvertTo-Json -Depth 6 -Compress)); $seq++; $t += 500
            }
            [void]$lines.Add((@{ type = 'tool/call'; seq = $seq; time = $t; data = @{ name = 'pwsh'; arguments = @{ command = 'scan' } } } | ConvertTo-Json -Depth 6 -Compress)); $seq++; $t += 200000
            [void]$lines.Add((@{ type = 'tool/result'; seq = $seq; time = $t; data = @{ message = @{ content = @(@{ type = 'text'; text = 'late' }); isError = $false } } } | ConvertTo-Json -Depth 6 -Compress)); $seq++; $t += 500
        } else {
            for ($i = 1; $i -le 6; $i++) {
                [void]$lines.Add((@{ type = 'tool/call'; seq = $seq; time = $t; data = @{ name = 'pwsh'; arguments = @{ command = 'x' } } } | ConvertTo-Json -Depth 6 -Compress)); $seq++; $t += 1200
                [void]$lines.Add((@{ type = 'tool/result'; seq = $seq; time = $t; data = @{ message = @{ content = @(@{ type = 'text'; text = 'ok' }); isError = $false } } } | ConvertTo-Json -Depth 6 -Compress)); $seq++; $t += 300
                [void]$lines.Add((@{ type = 'assistant/message'; seq = $seq; time = $t; data = @{ step = $i; message = @{ content = @(@{ type = 'text'; text = '进展：已列目录。' }) } } } | ConvertTo-Json -Depth 6 -Compress)); $seq++; $t += 700
            }
        }
        [IO.File]::WriteAllText((Join-Path $Dir 'session.v4.jsonl'), ($lines -join "`n"), (New-Object Text.UTF8Encoding($false)))
    }

    $d1 = Join-Path $tmp 'dirty\session-A'
    $c1 = Join-Path $tmp 'clean\session-B'
    Write-FakeSession $d1 'session-A' $true
    Write-FakeSession $c1 'session-B' $false

    $recD = @(Get-SessionRecords -Root (Join-Path $tmp 'dirty') -Days 3650 -Limit 10)
    $recC = @(Get-SessionRecords -Root (Join-Path $tmp 'clean') -Days 3650 -Limit 10)
    $pD = New-Proposal -Records $recD -Days 7
    $pC = New-Proposal -Records $recC -Days 7

    $okD = ($recD.Count -eq 1) -and ($pD -match 'HF1') -and ($pD -match '建议改动')
    $okC = ($recC.Count -eq 1) -and ($pC -match '不要为了改而改')
    Write-Host ("  脏会话：记录 {0} 条 / 提案含建议 {1}" -f $recD.Count, ($pD -match '建议改动')) -ForegroundColor $(if ($okD) { 'Green' } else { 'Red' })
    Write-Host ("  干净会话：记录 {0} 条 / 提案不硬凑 {1}" -f $recC.Count, ($pC -match '不要为了改而改')) -ForegroundColor $(if ($okC) { 'Green' } else { 'Red' })
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    $ok = $okD -and $okC
    Write-Output ("SELFTEST: " + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    exit $(if ($ok) { 0 } else { 1 })
}

if (-not $Sessions) {
    $Sessions = Join-Path $env:USERPROFILE '.dsh\sessions'
}
if (-not (Test-Path -LiteralPath $Sessions)) {
    Write-Host ("找不到会话目录：{0}（用 -Sessions 指定）" -f $Sessions) -ForegroundColor Red
    exit 2
}

Write-Host ("扫描 {0}（最近 {1} 天，最多 {2} 个）……" -f $Sessions, $SinceDays, $Max) -ForegroundColor Cyan
$recs = @(Get-SessionRecords -Root $Sessions -Days $SinceDays -Limit $Max)
if ($recs.Count -eq 0) { Write-Host '没采到会话。' -ForegroundColor Yellow; exit 2 }

$md = New-Proposal -Records $recs -Days $SinceDays
if (-not $Out) {
    $dir = Join-Path $PSScriptRoot 'proposals'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $Out = Join-Path $dir ((Get-Date -Format 'yyyy-MM-dd_HHmm') + '.md')
} else {
    $d = Split-Path $Out -Parent
    if ($d -and -not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}
[IO.File]::WriteAllText($Out, $md, (New-Object Text.UTF8Encoding($false)))

$hitTotal = ($recs | Where-Object { $_.HFs.Count -gt 0 }).Count
Write-Host ''
Write-Host ('  采样 {0} 个会话 / 有硬失败 {1} 个 / 总时长 {2:N0}s 浪费 {3:N0}s' -f $recs.Count, $hitTotal, (($recs | Measure-Object Sec -Sum).Sum), (($recs | Measure-Object Waste -Sum).Sum))
Write-Host ('  提案已写入：{0}' -f $Out) -ForegroundColor Green
Write-Output ('DISTILL: ' + $(if ($hitTotal -gt 0) { "$hitTotal 个会话有待处理失败" } else { '干净，无需改卡' }))
