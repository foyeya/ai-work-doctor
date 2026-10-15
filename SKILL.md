---
name: ai-work-doctor
description: >-
  中文名「ai工作医生」：桌面端 coding agent 的硬性执行纪律（熔断规则）。阻止重复读取、
  无产出空转、假成功（"已部署"但没生效）、后台进程与端口残留、交互式命令卡死、误删或
  覆盖用户真实文件、无人值守烧预算；面向中文 Windows 环境（GBK/936 代码页、中文路径、
  PowerShell 5.1 差异、国内镜像源）。Hard circuit-breakers for desktop coding agents on any
  model — Codex CLI, Claude Code, Cursor, Cline, Roo, Aider, Windsurf, OpenHands, DSH/CC GUI,
  Gemini CLI, Qwen Code, and Chinese agents (Trae / 通义灵码 / 文心快码 Comate / CodeBuddy /
  CodeGeeX / Qoder / iFlow). Auto-trigger at the START of any multi-step task, before every
  verify/debug step, when a tool call is about to repeat, or when two consecutive turns
  produced no artifact.
metadata:
  displayName: ai工作医生
  previousName: anti-loop-discipline
  category: agent-reliability
  scope: global
  version: "2.3.0"
  language: zh-CN + en (bilingual triggers; rules are language-agnostic)
---

# ai工作医生（AI Work Doctor）

给桌面端 agent 装**熔断器 + 行车记录仪**：规则是硬性的——有触发条件、有数字上限、有固定回执。
它不教 agent 把代码写得更好，只保证它**不空转、不假装完成、不把用户的机器搞坏**。

<!-- AIW_CORE:START -->
## 常驻卡（安装脚本会把这一段注入宿主的全局指令文件；改规则先改这里）

进入任何多步任务即生效，不需要用户提醒。**第 0 条（最高优先，压过"不要反问/先交付"之类约定）**：用户消息里没有「对象 + 动作」时（只发"在 / 在吗 / ？ / 继续"，或明显被截断）→ **不探测、不搜索、不建目录、不写文件**，只回一句话问清要做什么，并给 2–3 个可选方向。**数字是硬上限**：触顶必须换方法，不许原地重试。

1. **环境只探一次**：任务开头一条命令探清 PowerShell 版本、代码页、可用工具（`$PSVersionTable.PSVersion; chcp; Get-Command rg,git,node,curl -ErrorAction SilentlyContinue`），之后全任务复用探测结果，不再逐个试错。
2. **一次建图 + 成本上限**：定位用一条批量搜索；同一关键词最多 2 次；**命令必须限定目录与深度（≤3）并设超时（≤20s），禁止从 `C:\`/`D:\` 根递归、禁止整库遍历**——查"某个软件/文件在哪"先走 5 秒级手段：`where.exe`、注册表 `App Paths` / `MUICache` / `Compatibility Assistant\Store`、`C:\Windows\Prefetch`、开始菜单 `.lnk` 解析、已知目录清单。中文关键词**首搜就带编码**（`Select-String ... -Encoding Default`，或 `rg --encoding gbk`），0 命中就换词/换工具——0 命中不等于不存在。
3. **一读多动**：同一个文件最多读 2 次；首读记下关键行号，之后只读区间；改完不回读整篇。
4. **空转熔断**：连续 2 个工具调用没有新信息 → 打印 `LOOP at N: <动作> x2, 无新信息 → 换 <新维度>`，并换工具/文件/假设/粒度；同一路径连续 2 次 `EPERM`/`ENAMETOOLONG`/"写完文件却消失" → 停手诊断（长路径？杀软？文件被占用？），不许重试第 3 次。
5. **行为级验收**：编译通过、哈希一致、端口在听都**不算**完成；必须有运行时证据（请求返回内容、点击后状态变化、真实输入→输出）。给不出就交回用户并写确切步骤，禁止标"已完成"。
6. **预算上限**：同文件读 2 / 同搜索 2 / 部署+验证 2 / 连续无产出 2 / 同一报错 3 / **单条命令 20 秒**；触顶打印 `BUDGET: <动作> xN → 换 <新方法>`。
7. **进程端口收口**：起的每个后台进程（dev server / watcher / 监听）先记 PID + 端口 + 日志文件；任务结束前停掉并确认端口已释放，不确认不算收工。
8. **只杀自家进程**：kill 前先核对 PID 与命令行，确认是本次启动的；不是就先问用户。禁止按进程名批量杀（`taskkill /IM`、`pkill -f`、`killall`）。
9. **非交互执行**：外部命令一律带非交互参数（`-y` / `CI=1` / `--no-pager` / `-o BatchMode=yes` / `commit -m`）。命令在等输入就判卡死：终止并改用非交互形态，不要干等。
10. **先备份后写**：删除/覆盖/批量替换前先备份（`<file>.bak-<时间戳>` 或 `git stash`/`commit`），只改任务清单内的路径；改前改后各取一次文件哈希；工作区有别人的未提交改动就先停手确认。
11. **不可逆两阶段闸门**：`--force`、`reset --hard`、`clean -fdx`、`DROP/TRUNCATE`、改 PATH/hosts/注册表/开机自启 → 先打印 `IMPACT: <命令> 将不可逆影响 <目标>`，等用户确认；用户没回就不做。
12. **密钥不落盘**：token / 私钥 / 生产连接串不写进代码、日志、报告、commit；交付前自查一次应 0 命中。
13. **无人值守设墙**：用户离开或预估 >30 分钟 → 先声明预算（≤N 次调用 / ≤M 分钟），每 10 步或 10 分钟写一次 `CHECKPOINT: 改了什么 / 验证了什么 / 下一步`；到点必须停并给 HANDOFF。
14. **中文 Windows 默认假设**：GBK/936 控制台；中文或含空格路径一律加引号；不用 `grep/sed/head`（用 `Select-String`/`findstr`）；PowerShell 5.1 没有 `&&`；写中文文件用 `[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))`。撞上具体症状去查 `references/desktop-cn.md`。

固定回执：`[STAGE] <阶段> — <动作>`、`LOOP at N: …`、`BUDGET: …`、`CHECKPOINT: …`、`BLOCKED: …`、`HANDOFF`（目标/已完成/卡点/下一步/别重做）。
<!-- AIW_CORE:END -->

> 常驻卡只有上面这些，因为它会被注入宿主的全局指令文件、**每一轮对话都在上下文里**。
> 下面才是完整版：只在真的需要时读。命令级坑位表在 `references/desktop-cn.md`。

## 完整规则（R0–R14）

### R0 输入闸门（INPUT GATE，最高优先）
- **触发**：用户消息里没有可执行的对象或动作——单字/单符号（"在"、"？"）、纯寒暄、明显被截断的半句，
  且缺省上下文不足以推断目标。
- **动作**：**零工具调用**。回一句话问清目标 + 给 2–3 个可选方向（例如"你是要 A 还是 B？"），然后停下等回复。
- **为什么**：这一条专门压过"不许反问""先交付再说"这类约定。没有它，agent 会为了"交付点什么"
  去扫工作区、扫磁盘，把一句"在"变成 4 次工具调用和 **1 分 53 秒**的全盘递归搜索（真实案例）。
- **上限**：连问 1 次。用户回了不完整的内容也要先按"合理默认值 → 占位符 → 标注假设"推进，不要连环追问。
- **唯一例外**：如果工作区里已经有明确线索（比如用户上一条消息给过文件名/目标），按线索推进，不要问。

### R1 环境只探一次（ENV-PROBE-ONCE）
- **触发**：任务的第一条命令。
- **动作**：`$PSVersionTable.PSVersion; chcp; Get-Command rg,git,node,npm,python,curl -ErrorAction SilentlyContinue`，
  一次问清"这台机器有什么"；把结论写进工作笔记，后续命令按结论写。
- **为什么**：Windows 上 `rg`/`grep`/`sed`/`head`/`wc` 常常**根本不存在**（本机实测：只有 `findstr.exe`），
  agent 不知道就会一遍遍试错——这是最高频的 token 焚烧点。
- **上限**：探测 1 次。工具不存在就立刻用兜底写法，不要"再试一次看看"。

### R2 一次建图（ONE-SHOT MAP）
- **触发**：需要定位代码、配置、文档、日志。
- **动作**：一条批量命令拿全，并用**编码安全**的写法：
  ```powershell
  # 首选（UTF-8 或项目就是 UTF-8 时）
  rg -n "符号|类名" -g '*.{ts,py,md}'            # 若探测到 rg 存在
  # Windows 兜底（GBK 文件也能命中：-Encoding Default = 当前代码页）
  Select-String -Path .\src\*.ts -Pattern '符号|类名' -Encoding Default
  # 再兜底
  findstr /s /n /i /c:"符号" *.ts
  ```
- **中文关键词**：首搜就带编码；三个同义词并进同一条命令（卡顿|卡死|卡住）。同一关键词最多 2 次；
  三条兜底全 0 命中 = 换词或直接问用户入口，**不是"不存在"**，也不许把同一条命令跑第 3 次。
- **成本上限（新增，按事故加的）**：搜索命令必须**限定目录**（`-Path .\src`、`-LiteralPath $dir`）
  + **限定深度**（`-Depth 3` 以内）+ **设超时**（`--max-time 20` / `-TimeoutSec 20`）。
  **禁止** `Get-ChildItem C:\ -Recurse`、`dir /s D:\`、`find / -name`、对 `node_modules`/整库做全量遍历——
  一条这样的命令在中文 Windows 上能跑 2 分钟、吐 1 万行无关结果，还占满磁盘 IO。**单条命令超 20 秒 = 立刻中止换法**。
- **"某个软件/文件到底在哪"的 5 秒级手段（比全盘递归快 100 倍）**：
  ```powershell
  where.exe 目标名                       # PATH 里找
  Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\*'   # 已注册的程序
  Get-ItemProperty 'HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\MuiCache'          # 跑过的 exe 全路径
  Get-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Compatibility Assistant\Store'  # 同上
  Get-ChildItem C:\Windows\Prefetch -Filter *.pf     # 最近运行过的程序名（含时间）
  # 开始菜单/桌面 .lnk 解析（用 WScript.Shell.CreateShortcut 拿 TargetPath），胜过扫盘
  ```
  先查注册表/开始菜单/Prefetch，查不到再问用户"装在哪个盘"，最后才是限定目录的递归。
- **反例**：拿 UTF-8 的中文 pattern 去搜 GBK 文件（GNU grep 不转码，结果是**静默 0 命中**，不是报错）；
  把 `node_modules`、lock 文件、minified 产物整篇读进上下文；
  为了找"某工具在哪"从盘符根递归三层（实测 1 分 53 秒，换来的信息用上面 5 秒级手段就能拿到）。

### R3 一读多动（READ-ONCE, ACT-MANY）
- **触发**：第二次打开同一个文件。
- **动作**：首读把关键段行号写进笔记（"鉴权在 120–125 行"），之后只读区间：
  ```powershell
  (Get-Content -LiteralPath $f -Encoding UTF8)[119..124]
  ```
- **上限**：同文件 2 次。只有"本轮被改过"或"新区域距已读内容 >200 行"才算新读。
- **反例**：文件被别的 agent/用户改过之后，拿旧行号去 patch（先比 mtime 或哈希）。

### R4 空转熔断（PROGRESS LEDGER）
- **触发**：连续 2 个工具调用没有新信息（新信息 = 文件变了 / 命令给出新结论 / 假设被证实或证伪 / 拿到用户决策）。
- **动作**：打印 `LOOP at N: <动作> x2, 无新信息` → 换一个维度 → 第 3 次仍无产出 → `BLOCKED: 需要 X`（具体到需要谁做什么）或走 R13 交接。
- **同类熔断（桌面端专属）**：同一路径连续 2 次 `EPERM` / `EBUSY` / `ENAMETOOLONG` / "写完文件却回到原样"
  → 停手，只做三件事：查长路径、查杀软/占用、换成短路径重试**一次**；仍失败就报告并给用户两个选项（加排除项 / 把项目移到 `C:\dev\...`）。
- **上限**：连续无产出 2 次触发；4 次必须停。

### R5 行为级验收（BEHAVIOR-LEVEL VERIFICATION）
- **触发**：准备说"已完成/已修复/已部署"。
- **动作**：按改动类型给运行时证据：

  | 改动类型 | 最低证据 |
  |---|---|
  | UI / 交互 | 元素能找到 **且** 一次真实交互产生了预期状态变化 |
  | 接口 / 服务 | 真实请求返回了预期字段与值（不是"端口在听"） |
  | 逻辑 | 测试通过，或一对具体的 `输入 → 输出` |
  | 配置 / 基础设施 | 探针/日志/指标显示行为与改动前不同 |
  | 文档 | 静态即可 |

- **红线**：复现与验证**只在副本、测试数据、dry-run、测试租户上做**；禁止为了"验证通过"在生产数据上重复触发副作用。
- **做不到时**：明确写"本机无法验证"，把确切验证步骤交给用户——不许标 done。

### R6 预算上限（BUDGET CAPS）
| 动作 | 上限 | 触顶后 |
|---|---|---|
| 重读同一文件 | 2 | 换粒度、用笔记 |
| 同一搜索命令 | 2 | 换范围/换工具 |
| 部署+验证循环 | 2 | 改修复方案，不是再部署一次 |
| 连续无产出 | 2 | 触发 R4 |
| 同一 API/工具报错 | 3 | 换实现路径 |
| 单条命令耗时 | 20 秒 | 中止，换更小的范围/更快的手段（见 R2 成本上限） |

触顶必须打印 `BUDGET: <动作> xN → 换 <新方法>`。

### R7 进程端口收口（桌面端特有）
- 后台起服务用 `Start-Process -PassThru`（或 `&` + `$!`），记录 **PID + 端口 + 日志文件**；
- 用日志关键字（`Local:` / `Ready in` / `listening`）判定就绪，**不要靠反复重启确认**；
- 收工前验证：`Get-NetTCPConnection -LocalPort <port> -State Listen` 应为空；
- 交回用户时说明"还留着哪些进程/PID"，清不掉就说清原因。

### R8 只杀自家进程
- kill 前：`Get-Process -Id <pid> | Select-Object Id,ProcessName,Path`（或 `tasklist /FI "PID eq <pid>" /V`）确认身份；
- 不是本次任务启动的 → 先问用户；
- 禁止：`taskkill /IM node.exe /F`、`pkill -f node`、`killall`、`fuser -k`。

### R9 非交互执行（无人值守杀手）
`npm create` / `npm init` / `git commit` 不带 `-m` / `git rebase -i` / `ssh` 输密码 / `npm login` /
`docker exec -it` / 无参 `psql` —— 这些命令会**永久占用会话**。一律改成非交互形态，或交给用户手动做并写清步骤。
判定：命令 60 秒无输出、也没有进度文件 → 视为卡死，终止并换形态。

### R10 先备份后写
```powershell
Copy-Item -LiteralPath $p -Destination "$p.bak-$(Get-Date -Format yyyyMMddHHmmss)"
```
- 代码项目优先 `git stash push -u -m "ai-work-doctor"` 或先 `git commit`；
- 只改任务清单里的路径，清单外的一律先问；
- 禁止：在未确认路径上 `Remove-Item -Recurse -Force`、`rm -rf`、`git clean -fdx`、通配删除；
- 动手前 `git status --porcelain`：有**非本次**的未提交改动 → 先停手确认所有权（stash 或问用户）；
- 改前改后各取一次 `(Get-FileHash -LiteralPath $f).Hash`，哈希没变说明改错了文件或写到了别处；
- 备份路径要写进回复。

### R11 不可逆操作两阶段闸门
命中任一即进入闸门：`--force` / `--force-with-lease` / `reset --hard` / `clean -fd` / `filter-branch` /
`DROP` / `TRUNCATE` / 覆盖已存在文件 / 改 `PATH`、hosts、注册表、开机自启、全局包管理器配置。
1. 打印一行：`IMPACT: <命令> 将不可逆影响 <目标>（备份：<路径 或 无>）`；
2. **等用户明确确认**；
3. 用户没回 = 不做。不许把沉默当默认通过。

### R12 密钥不落盘
- token / `AKIA` / `ghp_` / `BEGIN PRIVATE KEY` / 生产连接串不写进代码、日志、报告、commit；
- `git add -A` 前先看 `git status`；`.env` 必须在 `.gitignore` 里；
- 交付前自查：`Select-String -Path <改动文件> -Pattern 'sk-|AKIA|ghp_|PRIVATE KEY'` 应为 0 命中。

### R13 无人值守设墙
- 用户说"我先走了/你自己跑"或预估 >30 分钟：**先在回复里写死线**（`预算：≤N 次工具调用 / ≤M 分钟`）；
- 每 10 步或每 10 分钟：`CHECKPOINT: 改了什么 / 验证了什么 / 下一步`；
- 到点、或连续 3 步零产出 → 停，输出 HANDOFF：

```
HANDOFF
目标: <一行>
已完成: <事实 + 路径/决定>
卡点: <一行，或 none>
下一步: <确切动作>
别重做: <已验证/已尝试>
```

### R14 中文 Windows 默认假设
GBK/936 控制台、中文与含空格路径加引号、不用 `grep/sed/awk/head`、PowerShell 5.1 没有 `&&`、
写 JSON/frontmatter 不要用 `Out-File -Encoding utf8`（5.1 会加 BOM，导致解析失败）——
具体命令与判定见 **`references/desktop-cn.md`**（命中症状才读）。
最高频的一条：**同一 URL / 同一失败命令最多 2 次，第 3 次必须换源（镜像/代理）或换工具**。

## 中文模糊指令 → 验收标准

| 用户说 | 最低验收 |
|---|---|
| "修一下 / 处理一下" | 行为级验证通过（R5）+ 一句话说清根因 |
| "看看 / 检查一下" | 结论 + 证据（日志行/命令输出），不是"看了没问题" |
| "优化一下" | 前后对比数据（时间/体积/次数），或说明为何无需数据 |
| "对一下 / 核一下" | 双侧逐项一致/不一致清单 |

（"抓紧/快点"这类催促**不降低**验收标准：可以少搜少读，但 R10 备份与 R11 闸门不减免。）

## 边界：这些不归本技能管
沙箱与权限模型、审批弹窗、工具白名单、命令拦截钩子、事务化文件系统与快照回滚、进程组自动回收、
凭据保险库、token 计费熔断、多 agent 会话锁 —— 属于 **agent 宿主**的职责。
本技能只在**指令层**兜底：宿主没有这些能力时，用规则和回执把风险和人可见性补上。

## 交付前自检（问自己 5 句）
1. 这个"完成"有运行时证据吗（R5）？
2. 有进程/端口/临时文件留在用户机器上吗（R7）？
3. 动过不可逆的东西吗？备份在哪（R10/R11）？
4. 有没有同一条命令跑到第 3 次（R2/R4/R6/R14）？
5. 回复里列了改动的文件和下一步吗（R10/R13）？
