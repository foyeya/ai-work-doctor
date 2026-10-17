# ai工作医生 · 摩擦度判分（度量"装卡之后 agent 变笨/变啰嗦/变胆小"）
#
# 背景：只有"变守纪律"的正向探针是不够的——用户真实反馈是"装了之后 agent 变笨了"。
#       本工具给任意一段 agent 回复/转录打摩擦分，用于装前/装后 A/B 对比。
# 指标：
#   ctx-tax   上下文税   回复总字符 / 估算 tokens（固定成本，越低越好）
#   slop      啰嗦度     套话/铺垫/收尾客套命中数
#   timid     胆小度     明明任务已给全还反问用户的次数（问答/请求提供）
#   ritual    形式主义度 固定回执行数（DONE/EXPECT/STALL/REANCHOR…）及其密度
#   struct    结构税     标题+表格+列表密度（每千字符）
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\eval\friction.ps1 -Path 回复.txt
#   powershell -ExecutionPolicy Bypass -File .\eval\friction.ps1 -Text "……"
#   powershell -ExecutionPolicy Bypass -File .\eval\friction.ps1 -SelfTest
param(
    [string]$Path = "",
    [string]$Text = "",
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

function Test-Friction {
    param([string]$body)
    $chars = $body.Length
    $tokens = [int]($chars / 1.6)
    $lines = @($body -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    $codeLines = @($lines | Where-Object { $_ -match '^\s*(```|\$|>|PS >|def |function |import |from |const |let |var )' }).Count
    $nonCodeRatio = if ($lines.Count -gt 0) { [math]::Round((($lines.Count - $codeLines) / $lines.Count), 2) } else { 1 }

    $slopPat = '(好的[，,]?\s*(我来|下面|让我))|首先[，,]?\s*让我们|综上(?:所述)?[，,]?|希望这(?:个|对你有)帮助|如果还有问题(?:欢迎|请随时)|Let me know if|I hope this helps|Great question'
    $slop = ([regex]::Matches($body, $slopPat)).Count

    # 胆小度：任务信息已给全时仍反问（问答形态 / 请求补充 / 让用户做本可自己做的决定）
    $timidPat = '(请提供|请告诉我|你想要(?:哪个|哪种)|你希望(?:我|怎么)|能否提供|能不能提供|需要你补充|请补充|请确认(?:一下)?你|哪个更符合你的需求|Could you (?:clarify|provide|confirm)|Which (?:one )?do you prefer)'
    $timid = ([regex]::Matches($body, $timidPat)).Count

    # 形式主义度：固定回执 token（可观察回执本身没错，但密度过高就是税）
    $receiptPat = '\[STAGE\]|LOOP at \d+|STALL at \d+|EXPECT:|WHY: .*错|BUDGET:|REANCHOR:|\bDONE \d+/\d+\b|NOSTUB:|UNVERIFIED:||BLOCKED:|\bHANDOFF\b|IMPACT:'
    $ritual = ([regex]::Matches($body, $receiptPat)).Count
    $ritualDensity = if ($chars -gt 0) { [math]::Round($ritual * 1000 / $chars, 2) } else { 0 }

    # 结构税：标题/表格/列表密度（每千字符）
    $structEls = ([regex]::Matches($body, '(?m)^#{1,6} |^\|.*\|$\n^\|[- |]+\|$|^\s*[-*] |^\s*\d+\. ')).Count
    $structDensity = if ($chars -gt 0) { [math]::Round($structEls * 1000 / $chars, 2) } else { 0 }

    # 摩擦总分（0-100，越高越"笨重"）：套话与胆小最伤，回执次之，结构税最轻
    # 回执惩罚设门槛：≥3 条才开始计（单条合规 IMPACT 不该被判成形式主义）
    $ritualW = if ($ritual -ge 3) { [math]::Min(30, $ritualDensity * 6) } else { 0 }
    $score = [math]::Min(100, [int]($slop * 12 + $timid * 15 + $ritualW + [math]::Min(20, $structDensity * 1.5)))

    return @{
        Chars = $chars; Tokens = $tokens; Lines = $lines.Count; NonCodeRatio = $nonCodeRatio
        Slop = $slop; Timid = $timid; Ritual = $ritual; RitualDensity = $ritualDensity
        StructDensity = $structDensity; Score = $score
    }
}

if ($SelfTest) {
    Write-Host '=== 自测：重摩擦样本必须显著高于轻回复 ===' -ForegroundColor Cyan
    $heavy = @'
好的，我来帮你处理这个问题。首先，让我们了解一下现状。
[STAGE] 侦察 — 查看目录结构
EXPECT: 列出目录 → 得到文件清单
## 第一步：分析
| 项目 | 状态 |
|---|---|
| A | 完成 |
| B | 完成 |
- 项目 A 已完成
- 项目 B 已完成
- 项目 C 已完成
[STAGE] 实现 — 修改代码
EXPECT: 修改 config.py → 端口变为 8080
WHY: 原假设错 → 改新假设
REANCHOR: 目标 / 硬约束 / 已改 / 未完成 / 失败
## 第二步：确认
你想要哪种命名风格？请提供一下你偏好的目录结构，我才能继续。
DONE 3/3：上述三项全部完成
改了什么 / 验证了什么 / 下一步
希望这个对你有帮助。如果还有问题欢迎随时问我。
'@
    $light = @'
修好了。`config.py:42` 的端口写死成 5000，改成读环境变量：
```python
PORT = int(os.environ.get("PORT", "5000"))
```
实测：`python app.py` 起在 8080，`curl localhost:8080/health` 返回 ok。
'@
    $rh = Test-Friction $heavy
    $rl = Test-Friction $light
    '  重摩擦样本: score={0} slop={1} timid={2} ritual={3} struct={4}' -f $rh.Score, $rh.Slop, $rh.Timid, $rh.Ritual, $rh.StructDensity
    '  轻量回复  : score={0} slop={1} timid={2} ritual={3} struct={4}' -f $rl.Score, $rl.Slop, $rl.Timid, $rl.Ritual, $rl.StructDensity
    $ok = ($rh.Score -ge 60) -and ($rh.Score -gt $rl.Score + 40) -and ($rl.Slop -eq 0) -and ($rl.Timid -eq 0)
    Write-Output ("SELFTEST: " + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    Write-Host ("  自测结论：{0}" -f $(if ($ok) { 'PASS（重摩擦样本显著更重，轻量回复不被误伤）' } else { 'FAIL' })) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    if (-not $ok) { exit 1 }
    return
}

if ($Path) {
    if (-not (Test-Path -LiteralPath $Path)) { Write-Host "文件不存在：$Path" -ForegroundColor Red; exit 1 }
    $Text = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
}
if (-not $Text) { Write-Host '用法：-Path <回复文件> 或 -Text "<文本>" 或 -SelfTest' -ForegroundColor Yellow; exit 1 }

$r = Test-Friction $Text
Write-Output "CAPABILITY-NOTE: friction measures FORMAT TAX only (slop/timid/receipt/struct). It does NOT measure capability - a deep, cautious answer can score higher than a lazy one. Never use this score alone as an ability gate."
Write-Output ("FRICTION: " + $r.Score)
Write-Host ''
Write-Host '=== 摩擦度报告 ===' -ForegroundColor Cyan
Write-Host ("  摩擦总分   {0}/100（越高越笨重；40 以下算轻）" -f $r.Score)
Write-Host ("  上下文税   {0} 字符 ≈ {1} tokens · {2} 行 · 非代码行占比 {3}" -f $r.Chars, $r.Tokens, $r.Lines, $r.NonCodeRatio)
Write-Host ("  啰嗦度     套话/客套 {0} 处" -f $r.Slop)
Write-Host ("  胆小度     不必要的反问/索要 {0} 处" -f $r.Timid)
Write-Host ("  形式主义   固定回执 {0} 处（密度 {1}/千字）" -f $r.Ritual, $r.RitualDensity)
Write-Host ("  结构税     标题/表格/列表密度 {0}/千字" -f $r.StructDensity)
if ($r.Score -ge 60) { Write-Host '  判定：这份回复明显"笨重"——如果这是装卡后的表现，卡里有条款在帮倒忙' -ForegroundColor Red }
elseif ($r.Score -ge 40) { Write-Host '  判定：中等摩擦，可接受但可再瘦' -ForegroundColor Yellow }
else { Write-Host '  判定：轻量，正常发挥' -ForegroundColor Green }
