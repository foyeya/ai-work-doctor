# ai工作医生 · 装后可验证性检查（verify）
#
# 回答一个问题：装上之后，它到底有没有按卡在干活？
# 不是看文档写得多好，是看**真实会话**里有没有这些信号：
#   A 不静默：连续无对外文字的工具调用 ≤4 次（卡第 0 条）
#   B 不长阻塞：没有单次 ≥120 秒的调用（卡第 7 条）
#   C 有回执：至少出现 1 个机械可读回执（REANCHOR/ASSUME/MOCKED/RIPPLE/IMPACT/GUESS/UNVERIFIED/STAGE）
#   D 有分型：工具调用里出现 references/task-*.md（卡第 12 条，仅当任务是多步时）
#
# 用法：
#   powershell -File .\eval\verify.ps1                       # 最近 3 天
#   powershell -File .\eval\verify.ps1 -Days 7 -Max 30
#   powershell -File .\eval\verify.ps1 -Sessions "D:\sessions"
#   powershell -File .\eval\verify.ps1 -SelfTest
param(
    [string]$Sessions = "",
    [int]$Days = 3,
    [int]$Max = 20,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'session-lib.ps1')

$ReceiptNames = @('REANCHOR', 'ASSUME', 'MOCKED', 'RIPPLE', 'IMPACT', 'GUESS', 'UNVERIFIED', 'STAGE')

function Get-CardGen {
    param([string]$Raw)
    if ($Raw -match '先分型') { return 'v2.13+' }
    if ($Raw -match '扫描/枚举/全盘') { return 'v2.10-2.12' }
    if ($Raw -match '测试红了先判谁错') { return 'v2.9' }
    if ($Raw -match '先复现再修') { return 'v2.7-2.8' }
    if ($Raw -match '常驻卡') { return 'v2.0-2.6' }
    return '无卡'
}

function Test-SessionEvidence {
    param($Events, [string]$Raw)

    $r = Test-SessionEvents -Events $Events
    $allText = ''
    $proto = 0
    foreach ($e in $Events) {
        if ($e.type -eq 'tool/call') {
            $a = Get-CallArgs $e
            if ($a -match 'task-(debug|implement|refactor|research|ops|routing)\.md') { $proto++ }
            $allText += $a
        } elseif ($e.type -eq 'assistant/message') {
            $msg = $e.data.message
            if ($msg -and $msg.content) {
                foreach ($p in @($msg.content)) { if ($p.type -eq 'text') { $allText += [string]$p.text } }
            }
        }
    }
    $hit = @()
    foreach ($n in $ReceiptNames) { if ($allText -match [regex]::Escape($n)) { $hit += $n } }

    $checkSilent = (($r.MaxSilent -le ($HF3_SILENT - 1)) -or ($r.SilentSec -lt $HF3_SEC))
    $checkBlock = -not ($r.HardFail -match 'HF1')
    $checkReceipt = ($hit.Count -ge 1)

    return [pscustomobject]@{
        Card     = Get-CardGen $Raw
        Sec      = [math]::Round($r.TotalSec, 0)
        Calls    = $r.Calls
        Silent   = $r.MaxSilent
        Waste    = [math]::Round($r.WasteSec, 0)
        Waits    = $r.Waits
        Proto    = $proto
        Receipts = ($hit -join ',')
        OkSilent = $checkSilent
        OkBlock  = $checkBlock
        OkReceipt = $checkReceipt
        HFs      = @($r.HardFail)
    }
}

if ($SelfTest) {
    Write-Host '=== 自测：好会话 3 项全过，坏会话必须被抓 ===' -ForegroundColor Cyan
    $t0 = 1792260709000
    # 好：短调用 + 每 2 步一句话 + 加载协议 + 带 RIPPLE 回执
    $good = New-Object System.Collections.ArrayList
    [void]$good.Add((New-FakeEvent 'user/message' $t0 1 @{ content = 'x' }))
    $seq = 2; $t = $t0
    for ($i = 1; $i -le 4; $i++) {
        [void]$good.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'pwsh'; arguments = @{ command = 'x' } })); $seq++; $t += 1200
        [void]$good.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'ok' })); $seq++; $t += 300
        [void]$good.Add((New-FakeEvent 'assistant/message' $t $seq @{ message = @{ content = @(@{ type = 'text'; text = '进展：已定位，RIPPLE: 命中 1 已改 1。' }) } })); $seq++; $t += 600
    }
    [void]$good.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'read'; arguments = @{ file_path = 'references/task-debug.md' } })); $seq++; $t += 400
    [void]$good.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'ok' })); $seq++
    $rg = Test-SessionEvidence -Events @($good) -Raw '先分型'

    # 坏：10 步静默 + 一次 200 秒
    $bad = New-Object System.Collections.ArrayList
    [void]$bad.Add((New-FakeEvent 'user/message' $t0 1 @{ content = 'x' }))
    $seq = 2; $t = $t0
    for ($i = 1; $i -le 8; $i++) {
        [void]$bad.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'pwsh'; arguments = @{ command = 'scan' } })); $seq++; $t += 9000
        [void]$bad.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'ok' })); $seq++; $t += 400
    }
    [void]$bad.Add((New-FakeEvent 'tool/call' $t $seq @{ name = 'pwsh'; arguments = @{ command = 'scan' } })); $seq++; $t += 200000
    [void]$bad.Add((New-FakeEvent 'tool/result' $t $seq @{ text = 'late' })); $seq++
    $rb = Test-SessionEvidence -Events @($bad) -Raw '无卡'

    $ok = $rg.OkSilent -and $rg.OkBlock -and $rg.OkReceipt -and ($rg.Proto -ge 1) -and
          (-not $rb.OkSilent) -and (-not $rb.OkBlock) -and (-not $rb.OkReceipt)
    Write-Host ("  好会话：静默{0} 阻塞{1} 回执[{2}] 协议{3}" -f $rg.OkSilent, $rg.OkBlock, $rg.Receipts, $rg.Proto) -ForegroundColor $(if ($ok) { 'Green' } else { 'Red' })
    Write-Host ("  坏会话：静默过={0} 阻塞过={1} 回执过={2}" -f $rb.OkSilent, $rb.OkBlock, $rb.OkReceipt) -ForegroundColor DarkGray
    Write-Output ("SELFTEST: " + $(if ($ok) { 'PASS' } else { 'FAIL' }))
    exit $(if ($ok) { 0 } else { 1 })
}

if (-not $Sessions) { $Sessions = Join-Path $env:USERPROFILE '.dsh\sessions' }
if (-not (Test-Path -LiteralPath $Sessions)) { Write-Host ("找不到会话目录：" + $Sessions) -ForegroundColor Red; exit 2 }

$cut = (Get-Date).AddDays(-$Days)
$files = @(Get-ChildItem -LiteralPath $Sessions -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { ($_.Name -eq 'session.v4.jsonl.zstd' -or $_.Name -eq 'session.v4.jsonl') -and $_.LastWriteTime -ge $cut } |
    Sort-Object LastWriteTime -Descending | Select-Object -First $Max)
if ($files.Count -eq 0) { Write-Host '没采到会话（换个 -Days 或 -Sessions）' -ForegroundColor Yellow; exit 2 }

$rows = New-Object System.Collections.ArrayList
foreach ($f in $files) {
    try {
        $raw = Expand-SessionFile $f.FullName
        $ev = ConvertFrom-JsonlText $raw
        if ($ev.Count -eq 0) { continue }
        $m = Get-SessionMeta $raw
        $e = Test-SessionEvidence -Events $ev -Raw $raw
        [void]$rows.Add([pscustomobject]@{ Id = if ($m.Id) { $m.Id } else { $f.Directory.Name }; When = $f.LastWriteTime; Data = $e })
    } catch {
        Write-Host ("  跳过：{0}" -f $_.Exception.Message) -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host ("=== 装后检查：{0} 个会话（最近 {1} 天）===" -f $rows.Count, $Days) -ForegroundColor Cyan
Write-Host ('  {0,-15} {1,-10} {2,6} {3,5} {4,6} {5,6} {6,5} {7,-16} {8}' -f '会话', '卡版本', '时长s', '调用', '静默', '浪费s', '分型', '回执', '判定')
foreach ($r in $rows) {
    $d = $r.Data
    $verdict = if ($d.OkSilent -and $d.OkBlock) { 'PASS' } else { 'FAIL' }
    $color = if ($verdict -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host ('  {0,-15} {1,-10} {2,6} {3,5} {4,6} {5,6} {6,5} {7,-16} {8}' -f $r.Id.Substring(0, [Math]::Min(15, $r.Id.Length)), $d.Card, $d.Sec, $d.Calls, $d.Silent, $d.Waste, $d.Proto, ($d.Receipts + ''), $verdict) -ForegroundColor $color
}

$n = $rows.Count
$passSilent = @($rows | Where-Object { $_.Data.OkSilent }).Count
$passBlock = @($rows | Where-Object { $_.Data.OkBlock }).Count
$passReceipt = @($rows | Where-Object { $_.Data.OkReceipt }).Count
$protoUsed = @($rows | Where-Object { $_.Data.Proto -ge 1 }).Count
$newCard = @($rows | Where-Object { $_.Data.Card -match 'v2\.1[0-9]\+' -or $_.Data.Card -match 'v2\.13\+' }).Count

Write-Host ''
Write-Host '  汇总：' -ForegroundColor DarkGray
Write-Host ('    不静默 {0}/{1}   不长阻塞 {2}/{3}   有回执 {4}/{5}   加载任务协议 {6}/{7}   （其中新卡会话 {8}）' -f $passSilent, $n, $passBlock, $n, $passReceipt, $n, $protoUsed, $n, $newCard)
$verdictAll = if (($passSilent -eq $n) -and ($passBlock -eq $n)) { 'PASS' } else { 'FAIL' }
Write-Output ('VERIFY: ' + $verdictAll)
if ($verdictAll -ne 'PASS') { exit 1 }
