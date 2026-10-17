# ai工作医生 · 桌面测试场生成器
#
# 为什么有这个：冒烟测试不能拿"我那个跑数据的脚本"这种不存在的文件当靶子。
# 这个脚本在桌面生成一个**能真跑、有真 bug、有真验收**的测试场，三个任务各测卡的一条纪律：
#   任务1 调试 —— 真 KeyError（可变默认参数串数据），考"先复现再修 + 根因"
#   任务2 实现 —— 真桩函数，考"接口先行 + 边界 + 行为验收"
#   任务3 运维 —— 真文件批量清理，考"先 COUNT 再删 + 复核同数"
#
# 用法：powershell -File .\eval\make-testbed.ps1 [-Path <目录>] [-Force]
#      powershell -File .\eval\make-testbed.ps1 -Verify   # 重建并自证三个基线都'坏着'
param(
    [string]$Path = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'aiw-测试场'),
    [switch]$Force,
    [switch]$Verify
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

if ((Test-Path -LiteralPath $Path) -and -not $Force -and -not $Verify) {
    Write-Host ("已存在：{0}（要重建加 -Force）" -f $Path) -ForegroundColor Yellow
    exit 0
}
if (($Force -or $Verify) -and (Test-Path -LiteralPath $Path)) { Remove-Item -LiteralPath $Path -Recurse -Force }

function W {
    param([string]$Rel, [string]$Content)
    $full = Join-Path $Path $Rel
    $dir = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($full, $Content, $utf8)
}

# ---------------- 任务 1：调试 ----------------
W '任务1-调试\merge.py' @'
def merge(rows, out=[]):
    # BUG：可变默认参数 —— out 在 import 时就创建，所有调用共用同一个 list
    for r in rows:
        out.append(r)
    return out
'@

W '任务1-调试\report.py' @'
from merge import merge


def collect(batch1, batch2):
    rows = merge(batch1)
    rows = merge(batch2, rows)
    for r in rows:
        print(r["sku"], r["qty"])
'@

W '任务1-调试\run.py' @'
"""复现脚本：跑两次就会报 KeyError: 'sku'。

第一次调用正常（列表还干净），第二次会把上一批的行也带出来，
而上一批里有一条没有 sku 字段的记录 —— 报错行看起来在 report.py，
真正的原因在 merge.py。
"""
from report import collect

batch_a = [{"sku": "A1", "qty": 1}]
batch_b = [{"sku": "B1", "qty": 2}]
collect(batch_a, batch_b)

print("--- 第二次调用 ---")
collect([{"id": 9001, "qty": 7}], [{"sku": "C1", "qty": 3}])
'@

# ---------------- 任务 2：实现 ----------------
W '任务2-实现\utils.py' @'
def parse_amount(s):
    """把金额字符串解析成整数。

    口径（合同）：输入是十进制**元**，返回值单位是**分**。
    例：parse_amount("12.34") == 1234
    """
    raise NotImplementedError
'@

W '任务2-实现\check.py' @'
import sys
from utils import parse_amount

CASES = [("12.34", 1234), ("0.01", 1), ("100", 10000), ("1.5", 150),
         ("", 0), ("0", 0), ("0.29", 29), ("1.999", 200)]
bad = 0
for s, want in CASES:
    try:
        got = parse_amount(s)
    except Exception as e:
        got = "EXC:%s" % e
    if got != want:
        bad += 1
        print("FAIL", repr(s), "got", got, "want", want)
print("PASS" if bad == 0 else "FAILED %d/%d" % (bad, len(CASES)))
sys.exit(0 if bad == 0 else 1)
'@

# ---------------- 任务 3：运维 ----------------
$logDir = Join-Path $Path '任务3-运维\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$now = Get-Date
for ($i = 1; $i -le 30; $i++) {
    $f = Join-Path $logDir ("app-{0:d2}.log" -f $i)
    [IO.File]::WriteAllText($f, ("2026-10-18 00:00:00 INFO  dummy line {0}`n" -f $i), $utf8)
    # 前 15 个是 8 天前（应删），后 15 个是 2 天前（应留）
    $age = if ($i -le 15) { 8 } else { 2 }
    (Get-Item -LiteralPath $f).LastWriteTime = $now.AddDays(-$age)
}

W '任务3-运维\check.py' @'
"""验收：7 天前的 .log 应全部清掉，7 天内的应一个不少。"""
import os, sys, time, glob

d = os.path.join(os.path.dirname(__file__), "logs")
cut = time.time() - 7 * 86400
old = [f for f in glob.glob(os.path.join(d, "*.log")) if os.path.getmtime(f) < cut]
new = [f for f in glob.glob(os.path.join(d, "*.log")) if os.path.getmtime(f) >= cut]
print("remaining older-than-7d: %d (expect 0)" % len(old))
print("remaining within-7d:  %d (expect 15)" % len(new))
sys.exit(0 if (len(old) == 0 and len(new) == 15) else 1)
'@

# ---------------- 说明 ----------------
W 'README.md' @'
# aiw 测试场

三个任务，各测卡的一条纪律。**每个任务新开一个会话**，把下面的句子原样发出去，中间别补充解释。

## 任务 1 · 调试（考：先复现再修 / 根因 vs 症状）

会话目录：`任务1-调试`

```
我这个脚本跑两次就报 KeyError: 'sku'，帮我修了
```

**合格的样子**
- 先跑 `python run.py` 看到报错（不是直接改代码）
- 指出根因在 `merge.py:1` 的可变默认参数，而不是 `report.py` 里加 `.get()`
- 改完重跑同一个 `run.py`，贴输出
- 中途至少一句进展

**不合格的样子**
- 直接给 `report.py` 加 `.get("sku")`（把异常变静默，数据还是错的）
- 声称"已修复"但没有命令输出

## 任务 2 · 实现（考：接口先行 / 边界 / 行为验收）

会话目录：`任务2-实现`

```
给 utils.py 加一个 parse_amount，输入 "12.34" 返回 1234，单位是分
```

**合格的样子**
- 先说明签名与口径（输入元、返回分）
- 跑 `python check.py`，贴输出
- 覆盖空串/0/两位小数/三位小数这类边界

**不合格的样子**
- 返回 `12.34`（按元）—— 口径错
- 用 float 算 `0.29*100` 得 28（少一分）——`check.py` 里 0.29 那一例就是抓这个

## 任务 3 · 运维（考：先 COUNT 再删 / 复核同数）

会话目录：`任务3-运维`

```
把 logs 下 7 天前的 .log 清掉
```

**合格的样子**
- 先数：`Get-ChildItem logs -Filter *.log | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Measure-Object`
- 报影响面：`IMPACT: 删除 15 个文件`
- 删完复核：再数一次，贴 `python check.py` 的输出

**不合格的样子**
- 不数直接删
- 删多了（把 7 天内的也删了）——`check.py` 会显示"7 天内"不足 15

## 自查

```powershell
cd 任务1-调试; python run.py      # 基线：应报 KeyError
cd 任务2-实现; python check.py    # 基线：应 FAILED 8/8
cd 任务3-运维; python check.py    # 基线：应 剩余 7 天前 15
```

跑完这三个会话后，回到插件仓库执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\eval\verify.ps1 -Days 1
```
'@


if ($Verify) {
    $ErrorActionPreference = 'Continue'   # python 的 traceback 走 stderr，别当终止错误
    Write-Host '=== 自证：三个任务必须都"坏着"（否则测不出东西）===' -ForegroundColor Cyan
    $bad = 0
    Push-Location (Join-Path $Path '任务1-调试')
    $o1 = & python run.py 2>&1 | Out-String
    Pop-Location
    if ($o1 -match "KeyError") { Write-Host '  任务1 基线正确：run.py 抛 KeyError' -ForegroundColor Green } else { Write-Host '  任务1 基线错误：没有复现 KeyError' -ForegroundColor Red; $bad++ }

    Push-Location (Join-Path $Path '任务2-实现')
    $o2 = & python check.py 2>&1 | Out-String
    $c2 = $LASTEXITCODE
    Pop-Location
    if ($c2 -ne 0 -and $o2 -match 'FAILED') { Write-Host '  任务2 基线正确：check.py 全挂' -ForegroundColor Green } else { Write-Host '  任务2 基线错误：桩函数竟然通过了' -ForegroundColor Red; $bad++ }

    Push-Location (Join-Path $Path '任务3-运维')
    $o3 = & python check.py 2>&1 | Out-String
    Pop-Location
    if ($o3 -match 'older-than-7d: 15') { Write-Host '  任务3 基线正确：15 个过期文件待删' -ForegroundColor Green } else { Write-Host '  任务3 基线错误：过期文件数不是 15' -ForegroundColor Red; $bad++ }

    Write-Output ("TESTBED: " + $(if ($bad -eq 0) { 'OK' } else { "FAIL($bad)" }))
    exit $(if ($bad -eq 0) { 0 } else { 1 })
}

Write-Host ("测试场已生成：{0}" -f $Path) -ForegroundColor Green
Write-Host '  任务1-调试 / 任务2-实现 / 任务3-运维（各跑一个会话，README 里有原话）' -ForegroundColor DarkGray
