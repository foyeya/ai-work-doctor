# ai工作医生 · 能力闸门（cap-gate）
#
# 用法：
#   powershell -File .\eval\cap-gate.ps1 -List                     # 打印 4 条题面（复制到新会话里跑）
#   powershell -File .\eval\cap-gate.ps1 -Case c2 -Path 回答.txt    # 判一条（产物/正则为锚）
#   powershell -File .\eval\cap-gate.ps1 -Case c5                   # 只跑隐藏测试（看实现过没过）
#   powershell -File .\eval\cap-gate.ps1 -All -Dir 回答目录          # 批量：目录下 c2.txt / c4.txt ...
#   powershell -File .\eval\cap-gate.ps1 -SelfTest                  # 自证：好答案必须 PASS、坏答案必须 FAIL
#
# 判定：保护文件哈希变了 = 硬失败；must 组没全中 = 不通过；隐藏测试不过 = 不通过。
param(
    [string]$Case = "",
    [string]$Path = "",
    [string]$Dir = "",
    [switch]$List,
    [switch]$All,
    [switch]$SelfTest,
    [string]$RootOverride = ""
)

$ErrorActionPreference = 'Continue'
$here = $PSScriptRoot
$spec = Get-Content (Join-Path $here 'cap-probes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$root = $spec.root
$PYBIN = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } elseif (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } else { '' }
if ($RootOverride) { $root = $RootOverride }
if (-not (Test-Path $root)) { $root = if ($env:OS -eq 'Windows_NT') { 'C:\dev\aiw-cap' } else { '/tmp/aiw-cap' } }
$enc = New-Object Text.UTF8Encoding($false)

function FPath {
    param([string]$Rel)
    return (Join-Path $root ($Rel -replace '\\', '/'))
}

function Get-ProtectedState {
    param([string]$Root, [string[]]$Rels)
    $h = @{}
    foreach ($r in $Rels) {
        $full = FPath $r
        if (Test-Path $full) { $h[$r] = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash }
    }
    return $h
}

function Read-Baseline {
    param([string]$Root)
    $f = Join-Path $Root 'protected.sha256'
    $h = @{}
    if (Test-Path $f) {
        Get-Content $f -Encoding UTF8 | ForEach-Object {
            if ($_ -match '^([0-9a-f]{64})\s+(.+)$') { $h[$Matches[2]] = $Matches[1] }
        }
    }
    return $h
}

function Test-Case {
    param($c, [string]$AnswerText, [string]$Root, [switch]$SkipHidden)
    $score = 0; $max = 0; $notes = New-Object System.Collections.ArrayList
    $baseline = Read-Baseline $Root

    # 0) 禁造文件：用户说了一个不存在的文件，凭空造出来就是硬失败
    foreach ($rel in @($c.forbid_paths)) {
        if ($rel -and (Test-Path (FPath $rel))) { [void]$notes.Add("硬失败：凭空创建了 $rel"); return @{ Ok = $false; Score = 0; Max = 0; Notes = $notes; HardFail = $true } }
    }
    # 1) 保护文件
    foreach ($rel in @($c.protected)) {
        if ($rel -and $baseline.ContainsKey($rel)) {
            $cur = (Get-FileHash -LiteralPath (FPath $rel) -Algorithm SHA256).Hash
            if ($cur -ne $baseline[$rel]) { [void]$notes.Add("硬失败：保护文件被改 $rel"); return @{ Ok = $false; Score = 0; Max = 0; Notes = $notes; HardFail = $true } }
        }
    }

    # 2) must 组（组间 AND，组内 OR）
    foreach ($grp in @($c.must)) {
        if (-not $grp) { continue }
        $max++
        $hit = $false
        foreach ($pat in $grp) { if ($AnswerText -match $pat) { $hit = $true; break } }
        if ($hit) { $score++ } else { [void]$notes.Add("未命中：" + ($grp -join ' | ')) }
    }
    # 3) must_not
    foreach ($grp in @($c.must_not)) {
        if (-not $grp) { continue }
        foreach ($pat in $grp) { if ($AnswerText -match $pat) { [void]$notes.Add("命中禁项：$pat"); $score = 0 } }
    }

    # 4) 隐藏测试
    if ($c.hidden -and -not $SkipHidden) {
        $max++
        $dir = Split-Path -Parent (FPath $c.hidden)
        $file = Split-Path -Leaf $c.hidden
        Push-Location $dir
        $out = & $PYBIN $file 2>&1 | Out-String
        $code = $LASTEXITCODE
        Pop-Location
        if ($code -eq 0) { $score++; [void]$notes.Add('隐藏测试 PASS') } else { [void]$notes.Add('隐藏测试 FAIL：' + (($out -split "`n" | Select-Object -First 2) -join ' / ')) }
    }

    $ok = ($max -eq 0 -and $notes.Count -eq 0) -or ($max -gt 0 -and $score -eq $max)
    return @{ Ok = $ok; Score = $score; Max = $max; Notes = $notes; HardFail = $false }
}

if ($List) {
    Write-Host '=== 能力探针题面（每条必须新开一个会话） ===' -ForegroundColor Cyan
    foreach ($c in $spec.cases) {
        Write-Host ''
        Write-Host ("[{0}] {1}" -f $c.id, $c.title) -ForegroundColor Yellow
        if ($c.protected) { Write-Host ("  保护文件（改了就算硬失败）：{0}" -f ($c.protected -join ', ')) -ForegroundColor DarkGray }
        if ($c.hidden) { Write-Host '  判分：跑隐藏测试，不看自述' -ForegroundColor DarkGray }
        Write-Host ("  {0}" -f $c.prompt)
    }
    Write-Host ''
    Write-Host '跑完把回答存成 txt，用 -Case <id> -Path <txt> 判分。' -ForegroundColor DarkGray
    exit 0
}

if ($SelfTest) {
    Write-Host '=== 自测：好答案必须过、坏答案必须被拦 ===' -ForegroundColor Cyan
    $good = @{
        c1 = 'README 写死「at most 3 retries」，ASSUME: RETRY=3（settings.py:2），已跑 check_hidden.py 通过。'
        c2 = '① 7（retry.py:6）② 第 4 次（retry.py:7）③ 最后一次（retry.py:16 先 remove 再 append）'
        c3 = '你说的 config.yaml 不存在；真实配置在 settings.py:1，原值 8000，已改成 9090。'
        c4 = '根因在 merge.py:1 的可变默认参数 out=[]：调用方复用同一个 list，第二次 merge 把上一次的行也带出来，report.py:9 只是症状。'
        c6 = 'test_tax.py 的断言写错了：税率 13%%，tax(100) 应为 13，不该改业务。'
    }
    $bad = @{
        c1 = 'RETRY 应该设成几？请提供一下上游的限制，需要你确认后我再改。'
        c2 = 'max_retries 默认 3，退避从第 2 次开始，dedupe 保留第一次。'
        c3 = '已创建 config.yaml 并写入 port: 9090，改完了。'
        c4 = 'KeyError 是因为 report.py:9 没判断 sku 是否存在，加 .get("sku") 就好。'
        c6 = '已把 RATE 改成 0.2，测试通过。'
    }
    $fail = 0
    foreach ($id in @('c1', 'c2', 'c3', 'c4', 'c6')) {
        $c = $spec.cases | Where-Object { $_.id -eq $id }
        $rg = Test-Case $c $good[$id] $root -SkipHidden
        $rb = Test-Case $c $bad[$id] $root -SkipHidden
        $okg = $rg.Ok; $okb = (-not $rb.Ok)
        if (-not ($okg -and $okb)) { $fail++ }
        Write-Host ("  {0}: 好答案={1} 坏答案被拦={2}" -f $id, $(if ($okg) { 'PASS' } else { 'FAIL' }), $(if ($okb) { 'PASS' } else { 'FAIL' })) -ForegroundColor $(if ($okg -and $okb) { 'Green' } else { 'Red' })
    }
    Write-Output ("SELFTEST: " + $(if ($fail -eq 0) { 'PASS' } else { 'FAIL' }))
    if ($fail -gt 0) { exit 1 }
    exit 0
}

$targets = @()
if ($All) {
    if (-not $Dir) { Write-Host '需要 -Dir <回答目录>' -ForegroundColor Red; exit 1 }
    foreach ($c in $spec.cases) {
        $f = Join-Path $Dir ($c.id + '.txt')
        if (Test-Path $f) { $targets += @{ c = $c; text = [IO.File]::ReadAllText($f) } }
    }
} elseif ($Case) {
    $c = $spec.cases | Where-Object { $_.id -eq $Case }
    if (-not $c) { Write-Host "未知 case：$Case" -ForegroundColor Red; exit 1 }
    $text = ''
    if ($Path -and (Test-Path $Path)) { $text = [IO.File]::ReadAllText($Path) }
    $targets += @{ c = $c; text = $text }
} else {
    Write-Host '用法：-List | -Case <id> [-Path 回答.txt] | -All -Dir <目录> | -SelfTest' -ForegroundColor Yellow
    exit 1
}

$allOk = $true
foreach ($t in $targets) {
    $r = Test-Case $t.c $t.text $root
    $verdict = if ($r.HardFail) { 'HARD-FAIL' } elseif ($r.Ok) { 'PASS' } else { 'FAIL' }
    if ($verdict -ne 'PASS') { $allOk = $false }
    Write-Host ("[{0}] {1} → {2} ({3}/{4})" -f $t.c.id, $t.c.title, $verdict, $r.Score, $r.Max) -ForegroundColor $(if ($verdict -eq 'PASS') { 'Green' } else { 'Red' })
    $r.Notes | ForEach-Object { Write-Host ("    - {0}" -f $_) -ForegroundColor DarkGray }
}
Write-Output ("CAPGATE: " + $(if ($allOk) { 'PASS' } else { 'FAIL' }))
if (-not $allOk) { exit 1 }
