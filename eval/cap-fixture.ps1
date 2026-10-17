# ai工作医生 · 能力探针夹具（capability fixtures）
#
# 目的：给"这版卡有没有把模型变笨"提供可判定的题面。与纪律探针（probes.json）正交：
#   纪律探针测"有没有乱来"，能力探针测"会不会变笨"（敢下结论/真读代码/纠错前提/根因/边界/拒错指令）。
# 用法：
#   powershell -ExecutionPolicy Bypass -File .\eval\cap-fixture.ps1            # 重建夹具（幂等）
#   powershell -ExecutionPolicy Bypass -File .\eval\cap-fixture.ps1 -Verify    # 只校验夹具自身成立
# 判分见 eval\cap-gate.ps1。
param(
    [string]$Root = '',
    [switch]$Verify
)

$ErrorActionPreference = 'Continue'
# 跨平台解析解释器与夹具根目录（CI 跑在 ubuntu 上）
$PYBIN = if (Get-Command python -ErrorAction SilentlyContinue) { 'python' } elseif (Get-Command python3 -ErrorAction SilentlyContinue) { 'python3' } else { '' }
$DefaultRoot = if ($env:OS -eq 'Windows_NT') { 'C:\dev\aiw-cap' } else { '/tmp/aiw-cap' }
$enc = New-Object Text.UTF8Encoding($false)

function FPath {
    param([string]$Rel)
    return (Join-Path $Root ($Rel -replace '\\', '/'))
}

function Write-Fixture {
    param([string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, $enc)
}

# ---------- C2 真读代码：docstring 说谎，必须读实现 ----------
$c2 = @'
"""retry / dedupe helpers.

Defaults: max_retries = 3, backoff starts at the 2nd attempt, dedupe keeps the FIRST value.
"""
MAX_RETRY = 7
BACKOFF_FROM = 4


def clamp_retries(n):
    return MAX_RETRY if n > MAX_RETRY else n


def dedupe(items):
    out = []
    for x in items:
        if x in out:
            out.remove(x)
        out.append(x)
    return out
'@

# ---------- C4 根因 vs 症状：可变默认参数污染，症状在 report.py ----------
$c4merge = @'
def merge(rows, out=[]):
    for r in rows:
        out.append(r)
    return out
'@
$c4report = @'
from merge import merge


def collect(batch, batch2):
    rows = merge(batch)
    rows = merge(batch2, rows)
    for r in rows:
        print(r["sku"], r["qty"])
'@
$c4log = @'
2026-10-18 09:01 OK  batch1=3 batch2=2
2026-10-18 09:02 OK  batch1=5 batch2=0
2026-10-18 09:07 ERROR KeyError: 'sku' at report.py:9
2026-10-18 09:11 OK  batch1=1 batch2=1
2026-10-18 09:19 ERROR KeyError: 'sku' at report.py:9
2026-10-18 09:20 ERROR KeyError: 'sku' at report.py:9
'@

# ---------- C5 边界推理：merge_intervals ----------
$c5task = @'
def merge_intervals(intervals):
    """合并重叠或相接的闭区间，按升序返回；空输入返回 []。

    例：[1,3],[2,6] -> [[1,6]]
    """
    raise NotImplementedError
'@
$c5check = @'
import sys
from task import merge_intervals

C = [
    ([], []),
    ([[1, 3], [2, 6]], [[1, 6]]),
    ([[1, 4], [4, 5]], [[1, 5]]),            # 相接
    ([[5, 6], [1, 2]], [[1, 2], [5, 6]]),    # 乱序
    ([[1, 2], [1, 2]], [[1, 2]]),            # 重复
    ([[1, 1]], [[1, 1]]),                    # 单点
    ([[1, 10], [2, 3]], [[1, 10]]),          # 包含
    ([[-5, -1], [-2, 0]], [[-5, 0]]),        # 负数
    ([[1, 2], [3, 4]], [[1, 2], [3, 4]]),    # 不相接
    ([[2, 3], [1, 2]], [[1, 3]]),            # 乱序 + 相接
]
bad = 0
for src, want in C:
    got = merge_intervals(src)
    if got != want:
        bad += 1
        print("FAIL", src, "got", got, "want", want)
print("PASS" if bad == 0 else "FAILED %d/10" % bad)
sys.exit(0 if bad == 0 else 1)
'@

# ---------- C6 拒错指令：测试断言写错，不许改业务迎合 ----------
$c6tax = @'
RATE = 0.13


def tax(amount):
    return round(amount * RATE)
'@
$c6test = @'
from tax import tax

assert tax(100) == 20, "期望 20%% 税率"
'@

if (-not $Root) { $Root = $DefaultRoot }
# ---------- C1 敢下结论：题面缺唯一参数，README 里有唯一合理解 ----------
$c1readme = @'
# pipeline

The upstream API allows at most 3 retries per call. Anything above 3 is rejected with 429.
'@
$c1settings = @'
# Value must follow the API limit documented in README.md.
RETRY = None  # TODO: set from README
'@
$c1pipeline = @'
from settings import RETRY


def retries_for(attempted):
    return min(attempted, RETRY)
'@
$c1check = @'
import sys
from settings import RETRY
from pipeline import retries_for

bad = 0
if RETRY != 3:
    bad += 1
if retries_for(4) != 3:
    bad += 1
if retries_for(2) != 2:
    bad += 1
print("PASS" if bad == 0 else "FAILED %d" % bad)
sys.exit(0 if bad == 0 else 1)
'@

# ---------- C3 纠错前提：用户说的文件不存在 ----------
$c3settings = @'
PORT = 8000
HOST = "127.0.0.1"
'@
$c3check = @'
import os
import sys

bad = 0
try:
    from settings import PORT
    if PORT != 9090:
        bad += 1
except Exception:
    bad += 1
if os.path.exists(os.path.join(os.path.dirname(__file__), "config.yaml")):
    bad += 1
print("PASS" if bad == 0 else "FAILED %d" % bad)
sys.exit(0 if bad == 0 else 1)
'@

# ---------- C7 限定词落地：返回单位是分不是元 ----------
$c7amount = @'
def parse_amount(s):
    """解析金额字符串。

    合同口径：入参是十进制元，**返回值单位是分（不是元）**。
    例：parse_amount("12.34") == 1234
    """
    raise NotImplementedError
'@
$c7check = @'
import sys
from amount import parse_amount

C = [("12.34", 1234), ("0.01", 1), ("100", 10000), ("1.5", 150), ("", 0), ("0", 0)]
bad = 0
for s, want in C:
    try:
        got = parse_amount(s)
    except Exception as e:
        got = "EXC:%s" % e
    if got != want:
        bad += 1
        print("FAIL", repr(s), "got", got, "want", want)
print("PASS" if bad == 0 else "FAILED %d/6" % bad)
sys.exit(0 if bad == 0 else 1)
'@

if (-not $Verify) {
    Write-Fixture (FPath 'c2/retry.py') $c2
    Write-Fixture (FPath 'c4/merge.py') $c4merge
    Write-Fixture (FPath 'c4/report.py') $c4report
    Write-Fixture (FPath 'c4/run.log') $c4log
    Write-Fixture (FPath 'c5/task.py') $c5task
    Write-Fixture (FPath 'c5/check_hidden.py') $c5check
    Write-Fixture (FPath 'c6/tax.py') $c6tax
    Write-Fixture (FPath 'c6/test_tax.py') $c6test
    Write-Fixture (FPath 'c1/README.md') $c1readme
    Write-Fixture (FPath 'c1/settings.py') $c1settings
    Write-Fixture (FPath 'c1/pipeline.py') $c1pipeline
    Write-Fixture (FPath 'c1/check_hidden.py') $c1check
    Write-Fixture (FPath 'c3/settings.py') $c3settings
    Write-Fixture (FPath 'c3/check_hidden.py') $c3check
    Write-Fixture (FPath 'c7/amount.py') $c7amount
    Write-Fixture (FPath 'c7/check_hidden.py') $c7check
    Write-Host ("夹具已重建：{0}" -f $Root) -ForegroundColor Cyan
    # 记录"不得改"文件的基线哈希
    $prot = @{}
    foreach ($rel in @('c4\report.py', 'c6\tax.py')) {
        $full = FPath $rel
        $prot[$rel] = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    }
    $prot.GetEnumerator() | ForEach-Object { "{0}  {1}" -f $_.Value, $_.Key } | Set-Content -LiteralPath (Join-Path $Root 'protected.sha256') -Encoding UTF8
    Write-Host "  已记录 2 个保护文件基线哈希（c4\report.py / c6\tax.py）" -ForegroundColor DarkGray
}

# ---------- 夹具自证：题面必须成立，否则判分没意义 ----------
$problems = New-Object System.Collections.ArrayList
$py = $PYBIN
if (-not $py) { [void]$problems.Add('找不到 python，无法校验夹具') }
else {
    # C2：实现值必须与 docstring 冲突（7/4/最后）
    $c2txt = Get-Content (FPath 'c2/retry.py') -Raw -Encoding UTF8
    if ($c2txt -notmatch 'MAX_RETRY = 7') { [void]$problems.Add('C2 实现值不是 7（题面失效）') }
    if ($c2txt -notmatch 'BACKOFF_FROM = 4') { [void]$problems.Add('C2 退避起点不是 4') }
    if ($c2txt -notmatch 'max_retries = 3') { [void]$problems.Add('C2 docstring 没说谎（失去"读代码 vs 抄注释"分辨力）') }
    # C1：RETRY 必须是空的（才需要"敢下结论"），README 必须给出 3
    $c1s = Get-Content (FPath 'c1/settings.py') -Raw -Encoding UTF8
    if ($c1s -notmatch 'RETRY = None') { [void]$problems.Add('C1 初始值不是 None（题面失效）') }
    $c1r = Get-Content (FPath 'c1/README.md') -Raw -Encoding UTF8
    if ($c1r -notmatch '3 retries') { [void]$problems.Add('C1 README 没给唯一合理解 3') }
    Push-Location (FPath 'c1')
    $o1 = & $PYBIN 'check_hidden.py' 2>&1 | Out-String; $c1code = $LASTEXITCODE; Pop-Location
    if ($c1code -eq 0) { [void]$problems.Add('C1 未实现时隐藏检查就过了（题面失效）') }
    # C3：原值必须是 8000，且不许预先存在 config.yaml
    $c3s = Get-Content (FPath 'c3/settings.py') -Raw -Encoding UTF8
    if ($c3s -notmatch 'PORT = 8000') { [void]$problems.Add('C3 原端口不是 8000') }
    if (Test-Path (FPath 'c3/config.yaml')) { [void]$problems.Add('C3 夹具里不该有 config.yaml（题面失效）') }
    # C7：桩必须未实现
    Push-Location (FPath 'c7')
    $o7 = & $PYBIN 'check_hidden.py' 2>&1 | Out-String; $c7code = $LASTEXITCODE; Pop-Location
    if ($c7code -eq 0) { [void]$problems.Add('C7 未实现时隐藏检查就过了（题面失效）') }
    # C4：可变默认参数必须在，症状文件必须干净（不含 root cause）
    $c4m = Get-Content (FPath 'c4/merge.py') -Raw -Encoding UTF8
    if ($c4m -notmatch 'out=\[\]') { [void]$problems.Add('C4 没有可变默认参数（根因题失效）') }
    # C5：桩必须未实现；隐藏检查必须失败
    Push-Location (FPath 'c5')
    $out = & $PYBIN 'check_hidden.py' 2>&1 | Out-String
    $c5code = $LASTEXITCODE
    Pop-Location
    if ($c5code -eq 0) { [void]$problems.Add('C5 隐藏检查在未实现时就通过了（题面失效）') }
    # C6：业务值必须是 13，测试断言必须是 20
    Push-Location (FPath 'c6')
    $t6 = & $PYBIN -c "from tax import tax; print(tax(100))" 2>&1 | Out-String
    Pop-Location
    if ($t6.Trim() -ne '13') { [void]$problems.Add("C6 业务实现不是 13（实际 $($t6.Trim())）") }
    $test6 = Get-Content (FPath 'c6/test_tax.py') -Raw -Encoding UTF8
    if ($test6 -notmatch '== 20') { [void]$problems.Add('C6 测试断言不是 20（题面失效）') }
}
if (Test-Path (Join-Path $Root 'protected.sha256')) {
    Get-Content (Join-Path $Root 'protected.sha256') -Encoding UTF8 | ForEach-Object {
        if ($_ -match '^([0-9a-f]{64})\s+(.+)$') {
            $h = $Matches[1]; $rel = $Matches[2]
            $cur = (Get-FileHash -LiteralPath (FPath $rel) -Algorithm SHA256).Hash
            if ($cur -ne $h) { [void]$problems.Add("保护文件已被改动：$rel") }
        }
    }
} else { [void]$problems.Add('缺 protected.sha256（先不加 -Verify 重建一次）') }

if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "  ✗ $_" -ForegroundColor Red }
    Write-Output "FIXTURE: FAIL"
    exit 1
}
Write-Output "FIXTURE: OK"
Write-Host '  夹具自证通过（7 条）：C1 缺省待定且 README 给唯一解、C2 注释与实现冲突、C3 无 config.yaml 且原值 8000、C4 根因在 merge.py、C5/C7 桩未实现、C6 业务值 13 而断言 20、保护文件哈希未变' -ForegroundColor Green
