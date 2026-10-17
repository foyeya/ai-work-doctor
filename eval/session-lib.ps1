# ai工作医生 · 会话解析与判分公共库（被 session-audit / distill 复用）
# 约定：这里只放"纯函数"（输入事件 → 输出结构），不做任何 CLI 输出。

$HF1_SEC = 120      # 单次调用硬上限（秒）
$HF2_COUNT = 2      # wait=true 允许次数（超过即硬失败）
$HF3_SILENT = 5     # 连续无对外文字的工具调用数上限（与卡第 11 条同口径）

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

function Get-SessionMeta {
    param([string]$Raw)
    $meta = [pscustomobject]@{ Id = ''; Cwd = '' }
    foreach ($line in ($Raw -split "`r?`n")) {
        if (-not $line.Trim()) { continue }
        try {
            $o = $line | ConvertFrom-Json
            if ($o.type -eq 'session') { $meta.Id = [string]$o.id; $meta.Cwd = [string]$o.cwd; break }
        } catch { }
    }
    return $meta
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
    $order = @()
    foreach ($e in $Events) {
        if ($e.type -eq 'tool/call') {
            $calls += [pscustomobject]@{ Name = [string]$e.data.name; Args = (Get-CallArgs $e); Time = $e.time; Dur = 0 }
            $order += 'call'
        } elseif ($e.type -eq 'tool/result') {
            $results += [pscustomobject]@{ Text = (($e.data | ConvertTo-Json -Depth 6 -Compress)); IsError = [bool]$e.data.message.isError; Time = $e.time }
        } elseif ($e.type -eq 'assistant/message') {
            $txt = 0
            $msg = $e.data.message
            if ($msg -and $msg.content) {
                foreach ($p in @($msg.content)) { if ($p.type -eq 'text') { $txt += ([string]$p.text).Length } }
            }
            if ($txt -gt 0) { $order += 'text' }
        }
    }

    $sorted = @($Events | Sort-Object time)
    for ($i = 0; $i -lt $calls.Count; $i++) {
        $t = $calls[$i].Time
        $nxt = $sorted | Where-Object { $_.time -gt $t } | Select-Object -First 1
        $calls[$i].Dur = if ($nxt) { ($nxt.time - $t) / 1000.0 } else { 0 }
    }

    $hf1 = @($calls | Where-Object { $_.Dur -ge $HF1_SEC })
    $waits = @($calls | Where-Object { $_.Args -match 'wait[^:,]{0,8}[:=]\s*true' })

    $maxSilent = 0; $run = 0
    foreach ($o in $order) {
        if ($o -eq 'text') { $run = 0 } else { $run++; if ($run -gt $maxSilent) { $maxSilent = $run } }
    }

    $errs = @($results | Where-Object { $_.IsError -or $_.Text -match '(?i)(exception|not recognized|cannot find|denied|没有找到|拒绝访问|失败)' })
    $waste = 0
    foreach ($c in $hf1) { $waste += ($c.Dur - $HF1_SEC) }

    $hard = New-Object System.Collections.ArrayList
    if ($hf1.Count -gt 0) { [void]$hard.Add(("HF1 长阻塞：{0} 次调用 ≥{1} 秒（最慢 {2:N0}s：{3}）" -f $hf1.Count, $HF1_SEC, ($hf1 | Measure-Object Dur -Maximum).Maximum, $hf1[0].Name)) }
    if ($waits.Count -ge $HF2_COUNT) { [void]$hard.Add(("HF2 干等：job wait=true {0} 次（上限 {1} 次）" -f $waits.Count, ($HF2_COUNT - 1))) }
    if ($maxSilent -ge $HF3_SILENT) { [void]$hard.Add(("HF3 静默空转：连续 {0} 个工具调用没有对外文字（上限 {1}）" -f $maxSilent, ($HF3_SILENT - 1))) }

    return [pscustomobject]@{
        Calls     = $calls.Count
        Errors    = $errs.Count
        Waits     = $waits.Count
        MaxSilent = $maxSilent
        Slowest   = ($calls | Sort-Object Dur -Descending | Select-Object -First 3)
        TotalSec  = if ($sorted.Count -gt 1) { ($sorted[-1].time - $sorted[0].time) / 1000.0 } else { 0 }
        WasteSec  = $waste
        HardFail  = $hard
    }
}

function New-FakeEvent {
    param([string]$Type, [long]$Time, [int]$Seq, $Data)
    return [pscustomobject]@{ type = $Type; time = $Time; seq = $Seq; data = $Data }
}
