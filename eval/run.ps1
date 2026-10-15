# ai工作医生 · 智商探针打分器（半自动，人工判定）
#
# 用法：
#   1) 装前打分（先把技能卸载或换一台干净宿主）：
#        powershell -ExecutionPolicy Bypass -File .\eval\run.ps1 -Model "DeepSeek-V3.2" -Phase before
#   2) 装上技能后，同样流程再打一遍：
#        powershell -ExecutionPolicy Bypass -File .\eval\run.ps1 -Model "DeepSeek-V3.2" -Phase after
#   3) 看对比：
#        powershell -ExecutionPolicy Bypass -File .\eval\run.ps1 -Report
#
# 说明：每条探针都要【新开一个对话】再发；脚本会打印可直接粘贴的 prompt。
#      打分 0/1/2：0=明显失败（命中 fail），1=部分做到，2=完全做到（命中 pass）。
param(
    [string]$Model = "",
    [ValidateSet("before", "after")][string]$Phase = "after",
    [switch]$Report,
    [switch]$List
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$probesFile = Join-Path $here 'probes.json'
$resultsDir = Join-Path $here 'results'
if (-not (Test-Path $resultsDir)) { New-Item -ItemType Directory -Force -Path $resultsDir | Out-Null }

$data = Get-Content -LiteralPath $probesFile -Raw -Encoding UTF8 | ConvertFrom-Json
$probes = $data.probes

if ($List) {
    Write-Host ("探针清单（满分 {0} 分）：" -f (($probes | Measure-Object points -Sum).Sum)) -ForegroundColor Cyan
    foreach ($p in $probes) { Write-Host ("  {0}  {1,-8} {2}  ({3} 分)" -f $p.id, $p.dim, $p.title, $p.points) }
    return
}

if ($Report) {
    $files = Get-ChildItem -LiteralPath $resultsDir -Filter *.csv -ErrorAction SilentlyContinue
    if (-not $files) { Write-Host "还没有任何结果文件。先跑 -Model <名字> -Phase before|after" -ForegroundColor Yellow; return }
    # 同一个 (model, phase) 可能跑过好几轮：只取最新一次。
    # 否则分数会被重复累加（旧版本 bug：跑两遍会打印出超过满分的数字）。
    $latest = [ordered]@{}
    foreach ($f in ($files | Sort-Object LastWriteTime -Descending)) {
        $r = @(Import-Csv -LiteralPath $f.FullName)
        if ($r.Count -eq 0) { continue }
        $key = "$($r[0].model)|$($r[0].phase)"
        if (-not $latest.Contains($key)) { $latest[$key] = $r }
    }
    $all = @(); foreach ($k in $latest.Keys) { $all += $latest[$k] }
    Write-Host ("（每个「模型+阶段」只取最新一轮，共 {0} 组）" -f $latest.Count) -ForegroundColor DarkGray
    $rows = $all | Group-Object { $_.model + '  [' + $_.phase + ']' } | ForEach-Object {
        $g = $_.Group
        [pscustomobject]@{
            模型与阶段 = $_.Name
            总分       = ($g | Measure-Object score -Sum).Sum
            满分       = ($g | Measure-Object points -Sum).Sum
            硬失败     = @($g | Where-Object { [int]$_.hard_fail -eq 1 }).Count
            失败项     = (($g | Where-Object { [int]$_.score -eq 0 } | ForEach-Object { $_.id }) -join ',')
            时间       = ($g | Select-Object -First 1).time
        }
    }
    $rows | Sort-Object 模型与阶段 | Format-Table -AutoSize | Out-String -Width 200 | Write-Host

    # 装前/装后配对对比
    $models = $all | Select-Object -ExpandProperty model -Unique
    foreach ($m in $models) {
        $b = $all | Where-Object { $_.model -eq $m -and $_.phase -eq 'before' }
        $a = $all | Where-Object { $_.model -eq $m -and $_.phase -eq 'after' }
        if ($b -and $a) {
            $bs = ($b | Measure-Object score -Sum).Sum
            $as = ($a | Measure-Object score -Sum).Sum
            $bhf = @($b | Where-Object { [int]$_.hard_fail -eq 1 }).Count
            $ahf = @($a | Where-Object { [int]$_.hard_fail -eq 1 }).Count
            $gain = $as - $bs
            $verdict = if ($gain -ge 5 -and $ahf -lt $bhf) { '有效提升（≥5 分且硬失败下降）' }
                       elseif ($gain -ge 5 -and $ahf -eq $bhf) { '有提升（分数够，硬失败没降）' }
                       elseif ($gain -gt 0) { '提升不明显（<5 分，可能是噪声）' }
                       else { '无提升' }
            # 成对差值优先于绝对档位：12 分与 13 分之间没有真实差异，别拿档位说事
            Write-Host ("`n{0}：装前 {1} → 装后 {2}  （差值 {3:+#;-#;0}）" -f $m, $bs, $as, $gain) -ForegroundColor Green
            Write-Host ("   硬失败：{0} → {1}     判定：{2}" -f $bhf, $ahf, $verdict) -ForegroundColor Green
            $diff = foreach ($p in $probes) {
                $x = ($b | Where-Object { $_.id -eq $p.id } | Select-Object -First 1)
                $y = ($a | Where-Object { $_.id -eq $p.id } | Select-Object -First 1)
                if ($x -and $y -and [int]$x.score -ne [int]$y.score) {
                    "    {0} {1,-16} {2} → {3}" -f $p.id, $p.title, $x.score, $y.score
                }
            }
            if ($diff) { Write-Host "  变化明细："; $diff | ForEach-Object { Write-Host $_ } }
        }
    }
    return
}

if (-not $Model) { Write-Host "用法：-Model <模型名> -Phase before|after  |  -Report  |  -List" -ForegroundColor Yellow; return }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $resultsDir ("{0}-{1}-{2}.csv" -f ($Model -replace '[\\/:*?"<>|\s]', '_'), $Phase, $stamp)
$rows = New-Object System.Collections.ArrayList

Write-Host ("`n模型：{0}   阶段：{1}   共 {2} 条探针" -f $Model, $Phase, $probes.Count) -ForegroundColor Cyan
Write-Host "提示：每条探针都要新开一个对话；下面会打印可粘贴的 prompt，打完分按回车继续。" -ForegroundColor DarkGray

foreach ($p in $probes) {
    Write-Host ("`n================ {0}  [{1}] {2}  ({3} 分) ================" -f $p.id, $p.dim, $p.title, $p.points) -ForegroundColor Cyan
    Write-Host "--- 粘给 agent 的 prompt ---" -ForegroundColor DarkGray
    Write-Host $p.prompt -ForegroundColor White
    Write-Host "--- 判定标准 ---" -ForegroundColor DarkGray
    Write-Host ("通过: " + $p.pass) -ForegroundColor Green
    Write-Host ("失败: " + $p.fail) -ForegroundColor Red
    if ($p.partial) { Write-Host ("部分: " + $p.partial) -ForegroundColor Yellow }
    $s = ''
    while ($s -notin @('0', '1', '2', '')) { $s = (Read-Host "打分 0/1/2（直接回车=1）").Trim() }
    if ($s -eq '') { $s = '1' }
    $tc = (Read-Host "工具调用次数（回车=未知）").Trim()
    $ms = (Read-Host "单条命令最大耗时秒数（回车=未知）").Trim()
    $hf = 'x'
    while ($hf -notin @('y', 'n', '')) { $hf = (Read-Host "是否命中硬失败串？（y/N）").Trim().ToLower() }
    if ($hf -eq 'y') { Write-Host "  ⚠ 硬失败：比丢 2 分严重，报告里会单独列出" -ForegroundColor Red }
    $note = (Read-Host "备注（可空，例如它实际做了什么）").Trim()
    [void]$rows.Add([pscustomobject]@{
        model = $Model; phase = $Phase; id = $p.id; dim = $p.dim; title = $p.title
        score = [int]$s; points = [int]$p.points
        tool_calls = $tc; max_cmd_seconds = $ms; hard_fail = $(if ($hf -eq 'y') { 1 } else { 0 })
        note = $note; time = (Get-Date -Format 'yyyy-MM-dd HH:mm')
    })
}

$rows | Export-Csv -LiteralPath $out -NoTypeInformation -Encoding UTF8
$total = ($rows | Measure-Object score -Sum).Sum
$max = ($rows | Measure-Object points -Sum).Sum
$band = if ($total -le 13) { '差' } elseif ($total -le 20) { '中' } else { '好' }
$hfCount = @($rows | Where-Object { [int]$_.hard_fail -eq 1 }).Count
Write-Host ("`n总分 {0}/{1}   档位：{2}   硬失败：{3} 条" -f $total, $max, $band, $hfCount) -ForegroundColor Green
if ($hfCount -gt 0) {
    Write-Host "  硬失败明细（这类比丢 2 分严重）：" -ForegroundColor Red
    $rows | Where-Object { [int]$_.hard_fail -eq 1 } | ForEach-Object { Write-Host ("    {0}  {1}  {2}" -f $_.id, $_.title, $_.note) -ForegroundColor Red }
}
Write-Host ("结果已写入：{0}" -f $out)
Write-Host "跑完 before 和 after 后用 -Report 看对比（判定口径见 eval/scoring.md）。" -ForegroundColor DarkGray
