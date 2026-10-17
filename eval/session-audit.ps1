# ai工作医生 · 会话体检（session-audit）
#
# 为什么有这个：2026-10-18 一个真实会话跑了 946 秒，其中 240 秒卡在无上限的句柄枚举、
# 540 秒卡在 job_output wait=true 干等，26 个工具调用期间一个字都没输出给用户 ——
# 用户的感受就是"墨迹"。卡的规则没有可观测回执，等于没生效。这个脚本把这类浪费做成机械判分：
#   HF1 单次工具调用 ≥120 秒（长阻塞）
#   HF2 job_output wait=true ≥2 次（干等同一件事）
#   HF3 连续 ≥5 个工具调用期间 0 对外文字（静默空转，与卡第 11 条同口径）
#
# 用法：
#   powershell -File .\eval\session-audit.ps1 -Path <会话.v4.jsonl.zstd 或 .jsonl>
#   powershell -File .\eval\session-audit.ps1 -SelfTest
#
# 退出码：0 = 无硬失败；1 = 有硬失败；2 = 参数/解析问题
param(
    [string]$Path = "",
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'session-lib.ps1')

if ($SelfTest) {
    Write-Host '=== 自测：真实形态的会话必须命中 3 类浪费，健康会话必须 0 命中 ===' -ForegroundColor Cyan
    $t0 = 1792260709000
    $dirty = New-Object System.Collections.ArrayList
    [void]$dirty.Add((New-FakeEvent 'user/message' $t0 1 @{ content = 'x' }))
    $seq = 2; $t = $t0
    for ($i = 1; $i -le 6; $i++) {
        [void]$dirty.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'pwsh'; arguments = @{ command = 'a' } })); $seq++; $t += 1500
        [void]$dirty.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'ok' })); $seq++; $t += 500
    }
    [void]$dirty.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'pwsh'; arguments = @{ command = 'find-handles' } })); $seq++; $t += 240000
    [void]$dirty.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'moved to background job' })); $seq++; $t += 500
    [void]$dirty.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'job_output'; arguments = @{ job_id = 'pwsh-14'; wait = $true; timeout_ms = 120000 } })); $seq++; $t += 120000
    [void]$dirty.Add((New-FakeEvent 'tool/result' $t $seq @{ text = '(no new output)' })); $seq++; $t += 500
    [void]$dirty.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'job_output'; arguments = @{ job_id = 'pwsh-14'; wait = $true; timeout_ms = 180000 } })); $seq++; $t += 1000
    [void]$dirty.Add((New-FakeEvent 'tool/result' $t $seq @{ text = '(no new output)' })); $seq++
    $rd = Test-SessionEvents -Events @($dirty)

    $clean = New-Object System.Collections.ArrayList
    $t = $t0; $seq = 2
    [void]$clean.Add((New-FakeEvent 'user/message' $t0 1 @{ content = 'x' }))
    for ($i = 1; $i -le 6; $i++) {
        [void]$clean.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'pwsh'; arguments = @{ command = 'Get-ChildItem' } })); $seq++; $t += 1200
        [void]$clean.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'ok' })); $seq++; $t += 300
        if ($i % 2 -eq 0) {
            [void]$clean.Add((New-FakeEvent 'assistant/message' $t $seq @{ message = @{ content = @(@{ type = 'text'; text = '进展：已列出目录，接下来看占用。' }) } })); $seq++; $t += 800
        }
    }
    $rc = Test-SessionEvents -Events @($clean)

    $ok = ($rd.HardFail.Count -ge 3) -and ($rc.HardFail.Count -eq 0)
    Write-Host ("  脏会话：硬失败 {0} 条（最慢 {1:N0}s，wait {2} 次，静默 {3} 步）" -f $rd.HardFail.Count, ($rd.Slowest[0].Dur), $rd.Waits, $rd.MaxSilent) -ForegroundColor $(if ($rd.HardFail.Count -ge 3) { 'Green' } else { 'Red' })
    Write-Host ("  健康会话：硬失败 {0} 条" -f $rc.HardFail.Count) -ForegroundColor $(if ($rc.HardFail.Count -eq 0) { 'Green' } else { 'Red' })
    Write-Output ("SELFTEST: " + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    exit $(if ($ok) { 0 } else { 1 })
}

if (-not $Path) {
    Write-Host '用法：-Path <会话 .v4.jsonl.zstd|.jsonl> 或 -SelfTest' -ForegroundColor Yellow
    exit 2
}
if (-not (Test-Path -LiteralPath $Path)) { Write-Host ("找不到会话文件：" + $Path) -ForegroundColor Red; exit 2 }

$raw = Expand-SessionFile $Path
$events = ConvertFrom-JsonlText $raw
if ($events.Count -eq 0) { Write-Host '没有解析到事件（文件格式不对？）' -ForegroundColor Red; exit 2 }

$meta = Get-SessionMeta $raw
$r = Test-SessionEvents -Events $events

Write-Host ''
Write-Host ('=== 会话体检：{0} ===' -f (Split-Path $Path -Leaf)) -ForegroundColor Cyan
Write-Host ('  会话 ID {0} / 项目 {1}' -f $meta.Id, $meta.Cwd)
Write-Host ('  总时长 {0:N0} 秒 / 工具调用 {1} 次 / 报错 {2} 次 / wait=true {3} 次 / 最长静默 {4} 步 / 超时浪费 {5:N0} 秒' -f $r.TotalSec, $r.Calls, $r.Errors, $r.Waits, $r.MaxSilent, $r.WasteSec)
Write-Host '  最慢的 3 次调用：' -ForegroundColor DarkGray
foreach ($c in $r.Slowest) {
    if ($null -eq $c) { continue }
    Write-Host ('    {0,7:N1}s  {1}  {2}' -f $c.Dur, $c.Name, ($c.Args.Substring(0, [Math]::Min(70, $c.Args.Length))))
}
if ($r.HardFail.Count -eq 0) {
    Write-Host '  无硬失败（没有长阻塞 / 干等 / 静默空转）' -ForegroundColor Green
} else {
    Write-Host '  硬失败：' -ForegroundColor Red
    foreach ($h in $r.HardFail) { Write-Host ('    - ' + $h) -ForegroundColor Red }
}
Write-Output ('SESSION: ' + $(if ($r.HardFail.Count -eq 0) { 'PASS' } else { 'FAIL' }))
if ($r.HardFail.Count -gt 0) { exit 1 }
