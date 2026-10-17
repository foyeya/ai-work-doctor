# ai工作医生 · 会话体检（session-audit）
#
# 为什么有这个：2026-10-18 一个真实会话（session-8954c625）跑了 494 秒，
# 其中 240 秒卡在一次无上限的句柄枚举、120 秒卡在 job_output wait=true 干等，
# 16 步里一个字都没输出给用户 —— 用户的感受就是"墨迹"。
# 卡的规则没有可观测回执，等于没生效。这个脚本把这类浪费做成机械判分：
#   HF1 单次工具调用 ≥120 秒（长阻塞）
#   HF2 job_output wait=true ≥2 次（干等同一件事）
#   HF3 连续 ≥5 个工具调用期间 0 对外文字（静默空转，与卡第 11 条同口径）
#
# 用法：
#   powershell -File .\eval\session-audit.ps1 -Path <会话.v4.jsonl.zstd 或 .jsonl>
#   powershell -File .\eval\session-audit.ps1 -SelfTest
#
# 退出码：0 = 无硬失败；1 = 有硬失败（CI 可据此红）
param(
    [string]$Path = "",
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$HF1_SEC = 120      # 单次调用硬上限（秒）
$HF2_COUNT = 2      # wait=true 允许次数（超过即硬失败）
$HF3_SILENT = 5     # 连续无对外文字的工具调用数上限

function Expand-SessionFile {
    param([string]$File)
    if ($File -notlike '*.zstd') { return ([IO.File]::ReadAllText($File, [Text.Encoding]::UTF8)) }
    $py = Join-Path $env:TEMP 'aiw_unzstd.py'
    $code = "import sys`ntry:`n    from compression import zstd`n    d = zstd.decompress(open(sys.argv[1],'rb').read())`nexcept Exception:`n    import zstandard as z`n    d = z.decompress(open(sys.argv[1],'rb').read())`nopen(sys.argv[2],'wb').write(d)`n"
    [IO.File]::WriteAllText($py, $code, (New-Object Text.UTF8Encoding($false)))
    $out = Join-Path $env:TEMP ('aiw_sess_' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.jsonl')
    & python $py $File $out | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        throw '解压失败：需要 python 3.14+ 的 compression.zstd，或 pip install zstandard'
    }
    $t = [IO.File]::ReadAllText($out, [Text.Encoding]::UTF8)
    Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue
    return $t
}

function ConvertFrom-JsonlText {
    param([string]$Raw)
    $ev = New-Object System.Collections.ArrayList
    foreach ($line in ($Raw -split "`r?`n")) {
        if (-not $line.Trim()) { continue }
        try { [void]$ev.Add(($line | ConvertFrom-Json)) } catch { }
    }
    return @($ev | Where-Object { $_.time -and $_.time -gt 1e12 } | Sort-Object seq)
}

function Get-CallArgs {
    param($ev)
    $d = $ev.data
    if (-not $d) { return '' }
    $a = $d.arguments
    if ($null -eq $a) { return '' }
    try { return ($a | ConvertTo-Json -Depth 6 -Compress) } catch { return [string]$a }
}

function Test-SessionEvents {
    param($Events)

    $calls = @()
    $results = @()
    $texts = @()   # 每个 assistant 事件的对外文字长度（按 seq/time 顺序）
    $order = @()   # 时间序：'call' 或 'text'
    $prev = $null
    foreach ($e in $Events) {
        if ($e.type -eq 'tool/call') {
            $dur = 0
            if ($prev) { $dur = ($e.time - $prev.time) / 1000.0 }
            $calls += [pscustomobject]@{
                Name = [string]$e.data.name
                Args = (Get-CallArgs $e)
                Time = $e.time
                Dur  = $dur
            }
            $order += 'call'
        } elseif ($e.type -eq 'tool/result') {
            $results += [pscustomobject]@{ Text = (($e.data | ConvertTo-Json -Depth 6 -Compress)); IsError = [bool]$e.data.message.isError; Time = $e.time }
        } elseif ($e.type -eq 'assistant/message') {
            $txt = 0
            $msg = $e.data.message
            if ($msg -and $msg.content) {
                foreach ($p in @($msg.content)) { if ($p.type -eq 'text') { $txt += ([string]$p.text).Length } }
            }
            $texts += [pscustomobject]@{ Len = $txt; Seq = $e.seq }
            if ($txt -gt 0) { $order += 'text' }
        }
        $prev = $e
    }

    # 修正耗时：用"下一条事件 - 本条"，而不是上一条
    $sorted = @($Events | Sort-Object time)
    for ($i = 0; $i -lt $calls.Count; $i++) {
        # 按时间找 calls[i] 之后的第一条事件
        $t = $calls[$i].Time
        $nxt = $sorted | Where-Object { $_.time -gt $t } | Select-Object -First 1
        $calls[$i].Dur = if ($nxt) { ($nxt.time - $t) / 1000.0 } else { 0 }
    }

    # HF1 单次调用超时
    $hf1 = @($calls | Where-Object { $_.Dur -ge $HF1_SEC })

    # HF2 wait=true 次数
    $waits = @($calls | Where-Object { $_.Args -match 'wait[^:,]{0,8}[:=]\s*true' })

    # HF3 最长静默段（连续工具调用，其间无对外文字）
    $maxSilent = 0; $run = 0
    foreach ($o in $order) {
        if ($o -eq 'text') { $run = 0 } else { $run++; if ($run -gt $maxSilent) { $maxSilent = $run } }
    }

    # 报错数（粗判）
    $errs = @($results | Where-Object { $_.IsError -or $_.Text -match '(?i)(exception|not recognized|cannot find|denied|没有找到|拒绝访问|失败)' })

    $hard = New-Object System.Collections.ArrayList
    if ($hf1.Count -gt 0) { [void]$hard.Add(("HF1 长阻塞：{0} 次调用 ≥{1} 秒（最慢 {2:N0}s：{3}）" -f $hf1.Count, $HF1_SEC, ($hf1 | Measure-Object Dur -Maximum).Maximum, $hf1[0].Name)) }
    if ($waits.Count -ge $HF2_COUNT) { [void]$hard.Add(("HF2 干等：job wait=true {0} 次（上限 {1} 次）" -f $waits.Count, ($HF2_COUNT - 1))) }
    if ($maxSilent -ge $HF3_SILENT) { [void]$hard.Add(("HF3 静默空转：连续 {0} 个工具调用没有对外文字（上限 {1}）" -f $maxSilent, ($HF3_SILENT - 1))) }

    return [pscustomobject]@{
        Calls      = $calls.Count
        Errors     = $errs.Count
        Waits      = $waits.Count
        MaxSilent  = $maxSilent
        Slowest    = ($calls | Sort-Object Dur -Descending | Select-Object -First 3)
        TotalSec   = if ($sorted.Count -gt 1) { ($sorted[-1].time - $sorted[0].time) / 1000.0 } else { 0 }
        HardFail   = $hard
    }
}

function New-FakeEvent {
    param([string]$Type, [long]$Time, [int]$Seq, $Data)
    return [pscustomobject]@{ type = $Type; time = $Time; seq = $Seq; data = $Data }
}

if ($SelfTest) {
    Write-Host '=== 自测：真实形态的会话必须命中 3 类浪费，健康会话必须 0 命中 ===' -ForegroundColor Cyan
    $t0 = 1792260709000
    # 脏会话：1 次 240s 调用 + 2 次 wait=true + 12 个工具调用无文本
    $dirty = New-Object System.Collections.ArrayList
    [void]$dirty.Add((New-FakeEvent 'user/message' $t0 1 @{ content = 'x' }))
    $seq = 2; $t = $t0
    for ($i = 1; $i -le 6; $i++) {
        [void]$dirty.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'pwsh'; arguments = @{ command = 'a' } })); $seq++; $t += 1500
        [void]$dirty.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'ok' })); $seq++; $t += 500
    }
    # 240 秒的句柄扫描
    [void]$dirty.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'pwsh'; arguments = @{ command = 'find-handles' } })); $seq++; $t += 240000
    [void]$dirty.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'moved to background job' })); $seq++; $t += 500
    # 两次 wait=true
    [void]$dirty.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'job_output'; arguments = @{ job_id = 'pwsh-14'; wait = $true; timeout_ms = 120000 } })); $seq++; $t += 120000
    [void]$dirty.Add((New-FakeEvent 'tool/result' $t $seq @{ text = '(no new output)' })); $seq++; $t += 500
    [void]$dirty.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'job_output'; arguments = @{ job_id = 'pwsh-14'; wait = $true; timeout_ms = 180000 } })); $seq++; $t += 1000
    [void]$dirty.Add((New-FakeEvent 'tool/result' $t $seq @{ text = '(no new output)' })); $seq++
    $rd = Test-SessionEvents -Events @($dirty)

    # 健康会话：短调用 + 每 2 步一句对外文字 + 0 次 wait
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
    Write-Host '--- 判定 ---' -ForegroundColor DarkGray
    Write-Host ("  脏会话应 FAIL（实得 {0} 条硬失败），健康会话应 PASS（实得 {1} 条）" -f $rd.HardFail.Count, $rc.HardFail.Count)
    Write-Output ("SELFTEST: " + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    exit $(if ($ok) { 0 } else { 1 })
}

if (-not $Path) {
    Write-Host '用法：-Path <会话 .v4.jsonl.zstd|.jsonl> 或 -SelfTest' -ForegroundColor Yellow
    exit 2
}
if (-not (Test-Path -LiteralPath $Path)) { Write-Host ("找不到会话文件：" + $Path) -ForegroundColor Red; exit 2 }

$events = ConvertFrom-JsonlText (Expand-SessionFile $Path)
if ($events.Count -eq 0) { Write-Host '没有解析到事件（文件格式不对？）' -ForegroundColor Red; exit 2 }

$r = Test-SessionEvents -Events $events

Write-Host ''
Write-Host ('=== 会话体检：{0} ===' -f (Split-Path $Path -Leaf)) -ForegroundColor Cyan
Write-Host ('  总时长 {0:N0} 秒 / 工具调用 {1} 次 / 报错 {2} 次 / wait=true {3} 次 / 最长静默 {4} 步' -f $r.TotalSec, $r.Calls, $r.Errors, $r.Waits, $r.MaxSilent)
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
