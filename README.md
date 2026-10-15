# ai工作医生（ai-work-doctor）

[English](README.en.md) · **中文**

**给你的桌面端 AI 编程助手装上「熔断器 + 行车记录仪」。**

它不教 agent 把代码写得更好，只保证三件事：

| ① 不空转 | ② 不假装完成 | ③ 不把你的机器搞坏 |
|---|---|---|
| 同一文件读 **2** 次、同一搜索搜 **2** 次就到顶；连续 2 轮没产出就熔断 | 「编译通过 / 端口在听 / md5 一致」都**不算**完成，必须给运行时证据 | 删改前先备份，不可逆操作先亮 `IMPACT:` 等你确认；后台进程记 PID 并收口 |

一条命令装完，**以后所有对话、所有项目、换任何模型都自动生效**——不需要每次 `/skill`。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/foyeya/ai-work-doctor/actions/workflows/validate.yml/badge.svg)](https://github.com/foyeya/ai-work-doctor/actions/workflows/validate.yml)
![Agents](https://img.shields.io/badge/agents-20%20个桌面端%20agent-blue)
![Chinese](https://img.shields.io/badge/国产-Trae%20%7C%20CodeBuddy%20%7C%20Comate%20%7C%20Qoder%20%7C%20Kimi-important)
![Tasks](https://img.shields.io/badge/tasks-中文%20%7C%20English%20%7C%20mixed-green)
![Deps](https://img.shields.io/badge/dependencies-0-brightgreen)

---

## 30 秒看懂

```
        一条命令                   注入宿主「每次启动都会读」的地方              以后每轮对话
┌──────────────────────┐      ┌────────────────────────────────────┐      ┌──────────────────┐
│  install.ps1 / .sh   │      │ 用户级全局指令文件                  │      │ 常驻卡自动在上下文 │
│  -List  认出装了哪些  │ ───▶ │  ~/.codex/AGENTS.md                │ ───▶ │ 14 条硬规则       │
│  -DryRun 先看再动手   │      │  ~/.claude/CLAUDE.md               │      │ 有数字上限        │
│  -Select 只装你要的   │      │  ~/.trae-cn/user_rules/…           │      │ 换模型也生效      │
│  双击 activate.cmd   │      │  ~/.codebuddy/CODEBUDDY.md …       │      └──────────────────┘
└──────────────────────┘      │ ＋ 用户级技能目录 skills/          │
       幂等 · 可预览          └────────────────────────────────────┘
       可精确卸载                          20 个宿主 · 只写有据可查的路径
```

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Select    # 挑要装的 agent（或双击 activate.cmd）
```

验证生效：新开对话问一句 **「说出 ai工作医生 的预算上限」** → `read 2 / search 2 / deploy 2 / no-op 2 / tool-err 3`。

## 和其他做法比，差在哪

| | 裸 agent（什么规则都不给） | "请勿重复读取"这类提醒式 prompt | 云端沙箱里的 agent | **ai工作医生** |
|---|---|---|---|---|
| 重复读同一文件 | 读到烧完上下文 | 弱模型直接忽略，强模型也常忘 | 沙箱限制缓解一部分 | **硬上限 2 次，触顶必须换方法并打印 `BUDGET:`** |
| "做完了"怎么算 | 它说完成就算 | 全靠自觉 | 沙箱里可见 | **必须先给运行时证据；给不出就交回你，禁止标 done** |
| 破坏性操作 | 直接执行 | 无强制力 | 沙箱隔离 | **先备份 + 打印 `IMPACT:` 等你确认** |
| 后台进程 / 端口 | 残留、越积越多 | 无 | 环境销毁时一起没 | **记 PID + 端口，收工前必须验证端口已释放** |
| 中文 Windows | `grep/sed/head` 不存在 → 无限试错；GBK 搜不到还在重试 | 无 | 不涉及 | **开头探一次环境 + 中文关键词首搜带编码 + 121 行坑位表** |
| 生效方式 | — | 每个对话手动贴一遍 | — | **一条命令注入全局，永久生效，换任何模型都吃** |
| 覆盖宿主 | — | — | — | **20 个桌面端 agent（国产 8 家）+ 18 个项目级注入点** |
| 可撤销 | — | — | — | **`-Uninstall` 只删自己写的标记块，你原来的规则一字不动** |

## 六条别人没做的

| # | 优势 | 具体是什么 | 你怎么验证 |
|---|---|---|---|
| 1 | **是硬规则，不是提醒** | 14 条规则每条都带「触发条件 + 数字上限 + 固定回执」：`LOOP at N:` / `BUDGET:` / `BLOCKED:` / `CHECKPOINT:` / `HANDOFF`。弱模型也能机械照做，强模型也别想糊过去 | 让它故意撞一个不存在的命令（如 `rg`），看它是**一次**探测后改用 `Select-String`，还是反复重试 |
| 2 | **一键激活、永久全局** | 写进宿主**每次启动都会读**的用户级指令文件 + 用户级技能目录；规则是纯文本上下文，**换任何模型（含国产模型）都生效**，不用每次 `/skill` | 装完**新开**对话（不要在当前对话里试），直接让它复述预算上限 |
| 3 | **20 个桌面端 agent，国产优先** | 国产：Trae / Trae CN / Trae CLI、CodeBuddy、文心快码 Comate、Qoder + Qoder CN（IDE 与 CLI 两套规则体系）、Kimi Code、iFlow。国际：Codex、Claude Code、Cursor、Cline、Roo、Continue、OpenHands、DSH/CC GUI、Gemini、Qwen、Zed、Copilot | `install.ps1 -List` 会列出本机认出哪些；`-Select` 菜单里每个宿主都显示**将写哪个文件** |
| 4 | **只写有据可查的路径** | 每个宿主路径都附**官方文档链接**（见 [INSTALL.md](INSTALL.md)）；查不到的**一律不猜**——错的路径会静默失效，比"不支持"更糟，所以改成手动粘贴兜底 | 打开 INSTALL.md 兼容矩阵，逐个点开证据链接 |
| 5 | **中文用户的坑替你踩完了** | GBK/936 乱码、中文路径、PS 5.1 没有 `&&`、`Out-File -Encoding utf8` 加 BOM 破坏 JSON、`curl` 是别名、`mkdir -p` 不存在、Git 默认 CRLF 让 `.sh` 报 `bad interpreter ^M`、中文关键词 0 命中≠不存在、国内镜像源、交互式命令挂死……全在 [references/desktop-cn.md](references/desktop-cn.md)，**命中症状才读** | 在中文 Windows 上跑一次让它"找一个中文注释里的函数"，看它会不会一条命令带走 |
| 6 | **不臃肿、可审计、可撤销** | 常驻部分只有 **20 行**（每轮对话都在上下文里，所以必须短）；三层渐进披露；脚本 **0 依赖、不联网、不需要管理员**；`-DryRun` 先看、重复运行**字节不变**、`-Uninstall` 精确删除，**连 GBK 老文件的编码都不动** | `-DryRun` 看一遍 → 装 → 再装一次看哈希是否相同 → `-Uninstall` 看用户原文是否逐字还原 |

> 详细的优势论证、逐条对比、实测证据和**已知边界**（哪些做不到、为什么）见 **[docs/why-ai-work-doctor.md](docs/why-ai-work-doctor.md)**。

**诚实边界**：规则只对"会读全局指令文件或 skills 目录"的宿主生效；把规则存在 UI / 账号 / 云端的
（Cursor User Rules、Windsurf、CodeGeeX、部分企业版）无法从文件系统注入，只能手动粘贴一段（README 里有）。
本插件是**指令层**，不是沙箱——权限控制、命令拦截、文件回滚属于 agent 宿主的职责。

---

## 30 秒上手

### Windows

```powershell
# 在仓库目录里（有 install.ps1 的那一层）
powershell -ExecutionPolicy Bypass -File .\install.ps1 -List      # 先看认出哪些 agent
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun    # 再预览要改哪些文件
powershell -ExecutionPolicy Bypass -File .\install.ps1            # 激活（全局：所有项目、以后所有对话）
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Select    # 交互菜单：自己挑要装哪几个 agent
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Only trae,codex,codebuddy   # 非交互：直接点名
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Project D:\my-app           # 可选：项目级注入
```

不想敲命令：**双击 `activate.cmd`** —— 它会先弹出宿主菜单让你挑（输入 `1,3,5` 或 `2-4`，
`all` 全选，`detected` 只装检测到的，`q` 退出，回车=只装检测到的）。执行策略被拦时用
`-ExecutionPolicy Bypass`（只影响这一次进程）。

### 只给某几个 agent 装（v2.2 新增）

| 想做的事 | 命令 |
|---|---|
| 菜单里挑（可多选、可区间、可全选） | `.\install.ps1 -Select` / `./install.sh -i` |
| 直接点名（脚本/CI 用，支持 `trae`、`trae-cn`、`codebuddy` 这类别名） | `.\install.ps1 -Only trae,codex` |
| 只卸载某几个 | `.\install.ps1 -Select -Uninstall` 或 `.\install.ps1 -Only trae -Uninstall` |
| 先看菜单和将要写入的路径，不落盘 | 上面任意一条再加 `-DryRun` |

菜单会列出**每个宿主当前是否已安装**、以及**将写入哪个文件**；`-Select` 模式下执行前还会再让你确认一次。
明确点名的宿主（菜单里点编号 / `-Only` 指定）即使当前没检测到也会按你的意思建目录——这等价于对该宿主用 `-All`。

### macOS / Linux / Git Bash

```bash
./install.sh -l && ./install.sh -n && ./install.sh      # 体检 → 预览 → 激活
./install.sh -i                                         # 交互菜单：挑要装哪几个 agent
./install.sh --only trae,codex                          # 非交互点名
./install.sh -p ~/my-app                                # 项目级注入
```

### 验证生效（别猜）

新开一个对话，问 agent：**"说出 ai工作医生 的预算上限"** → 期望 `read 2 / search 2 / deploy 2 / no-op 2 / tool-err 3`。
答不出来 → 先看 pinned issue **[装了没生效？先看这 5 步](https://github.com/foyeya/ai-work-doctor/issues/1)**（90% 是没新开对话或宿主不读文件）。

### 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall                     # 全局
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Project D:\my-app -Uninstall  # 项目级
```

卸载只删除它自己写入的标记块（`<!-- ai-work-doctor:start --> … <!-- ai-work-doctor:end -->`）、
它复制的技能目录、以及"内容只剩我们写的"文件，**你自己的规则一个字都不会动**。

---

## 两种生效面（为什么要分）

| 面 | 命令 | 写哪里 | 适合谁 |
|---|---|---|---|
| **全局（用户级）** | `install.ps1` / `install.sh` | `~/.codex/AGENTS.md`、`~/.claude/CLAUDE.md`、`~/.trae/user_rules/`、`~/.codebuddy/CODEBUDDY.md` … + 用户级 `skills/` | CLI 型 agent（Codex / Claude Code / DSH / Trae CLI / CodeBuddy CLI…） |
| **项目级** | `-Project <目录>` | 项目里的 `AGENTS.md`、`CODEBUDDY.md`、`.trae/rules/`、`.codebuddy/rules/`、`.comate/rules/`、`.cursor/rules/` … | IDE 型 agent（Trae IDE、CodeBuddy IDE、文心快码、Cursor、Cline…），它们的"用户规则"常常只在 GUI 里 |

**一键激活的真相**：全局面就是你要的"一次激活、永久生效"——规则写进宿主每次启动都会读的用户级文件，
换任何模型都吃这段文本（它只是上下文，与模型无关）。少数把规则存在**云端账号**或**只存在 UI**里的宿主
（Cursor User Rules、Windsurf、CodeGeeX、部分企业版）无法从文件系统注入，我们**不猜路径**，给出手动粘贴的一段话（见下）。

---

## 兼容矩阵

**只写有官方文档/源码依据的路径**；"查不到"的一律不写文件，只给手动兜底。

### 全局（用户级）

| 宿主 | 全局指令文件 | 用户级 skills 目录 | 依据 | 置信度 |
|---|---|---|---|---|
| Codex CLI | `~/.codex/AGENTS.md`（`$CODEX_HOME` 可覆盖） | `~/.codex/skills/` | 源码 + 本机实测 | 高 |
| Claude Code | `~/.claude/CLAUDE.md`（另有 `~/.claude/rules/`） | `~/.claude/skills/` | 官方文档 | 高 |
| DSH / CC GUI | `~/.dsh/AGENTS.md` | `~/.dsh/skills/`、`~/.agents/skills/` | 本机实测 | 高 |
| 通用 SKILL.md 约定 | — | `~/.agents/skills/` | 社区通用约定 | 高 |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/skills/` | 官方文档 | 高 |
| Qwen Code | `~/.qwen/QWEN.md`（另有 `~/.qwen/rules/`） | `~/.qwen/skills/` | 官方文档 | 高 |
| **Trae（字节）** | `~/.trae/user_rules/ai-work-doctor.md` | `~/.trae/skills/` | [docs.trae.ai/ide/rules](https://docs.trae.ai/ide/rules) | 高 |
| **Trae CN（字节）** | `~/.trae-cn/user_rules/ai-work-doctor.md` | `~/.trae-cn/skills/`、`.agents/skills/`（需开关） | [docs.trae.cn/ide_rules](https://docs.trae.cn/ide_rules) | 高 |
| **Trae CLI（字节）** | 项目 `AGENTS.md` / `.trae/rules/` | `~/.traecli/skills/` | [docs.trae.cn/cli_skills](https://docs.trae.cn/cli_skills) | 高 |
| **CodeBuddy（腾讯）** | `~/.codebuddy/CODEBUDDY.md` | `~/.codebuddy/skills/` | [codebuddy.cn/docs/cli/memory](https://www.codebuddy.cn/docs/cli/memory) | 高 |
| **文心快码 Comate（百度）** | 个人 Rules 仅 UI（落盘路径未公开） | `~/.comate/skills/` | [cloud.baidu.com/doc/COMATE](https://cloud.baidu.com/doc/COMATE/s/Zm9l4agw3) | 中 |
| Roo Code | `~/.roo/rules/ai-work-doctor.md` | — | 源码 | 中 |
| Cline | `<Documents>/Cline/Rules/ai-work-doctor.md` | — | 官方文档 | 高 |
| **Qoder CLI（阿里）** | `~/.qoder/AGENTS.md`（另有 `~/.qoder/rules/`、`~/.qoder/memory/`） | — | [docs.qoder.com/cli/memory](https://docs.qoder.com/cli/memory) | 高 |
| **Qoder CN CLI（阿里）** | `~/.qoder-cn/AGENTS.md`（另有 `~/.qoder-cn/rules/`） | — | [docs.qoder.cn/cli/memory](https://docs.qoder.cn/cli/memory) | 高 |
| **Qoder CN IDE（原通义灵码，阿里）** | 用户级规则只在设置/「记忆」里 → 不写文件，只装技能 | `~/.lingma/skills/` | [docs.qoder.cn/user-guide/skills](https://docs.qoder.cn/user-guide/skills) | 高 |
| **iFlow CLI（已停服 2026-04）** | `~/.iflow/IFLOW.md` | — | [platform.iflow.cn](https://platform.iflow.cn/cli/configuration/iflow) | 中 |
| **Kimi Code CLI（月之暗面）** | 无全局 AGENTS.md（配置在 `~/.kimi/config.toml`） | `~/.kimi/skills/`（也读 `~/.agents/`、`~/.claude/`、`~/.codex/skills/`） | kimi-cli docs | 高 |
| **Zed** | `~/.config/zed/AGENTS.md`（Windows `%APPDATA%\Zed\AGENTS.md`） | 通过 `~/.agents/skills/` | [zed.dev/docs/ai/instructions](https://zed.dev/docs/ai/instructions) | 高 |
| **VS Code Copilot（用户级）** | `~/.copilot/copilot-instructions.md` | — | [VS Code 文档](https://code.visualstudio.com/docs/copilot/customization/custom-instructions) | 高 |
| Cursor / Windsurf / CodeGeeX | **无文件**（规则只在设置或账号里）→ 手动粘贴 | Cursor 可通过 `~/.agents/skills/` | 官方文档 | 高 |

> 通义灵码已更名 **Qoder CN**（2026-05-20），iFlow CLI 已停服并指向 Qoder；上表按新名收录。
> 候选嗅探机制仍在（`$ProbeHosts`）：将来遇到"路径查不到但用户想试"的宿主，只在该工具目录与它自己的
> `rules\` 子目录都存在时才写，并在输出里标注"未官方证实"。

### 项目级（`-Project`）

| 文件 | 谁读 |
|---|---|
| `AGENTS.md` | Codex、DSH、OpenHands、Trae CLI、Qoder CLI、CodeBuddy（无 `CODEBUDDY.md` 时）等 |
| `CODEBUDDY.md` | CodeBuddy CLI/IDE（优先级高于 `AGENTS.md`） |
| `.trae/rules/ai-work-doctor.md` | Trae（`alwaysApply: true`，不依赖 AGENTS.md 开关） |
| `.codebuddy/rules/ai-work-doctor/RULE.mdc` | CodeBuddy IDE（每规则一个目录 + `RULE.mdc`） |
| `.comate/rules/ai-work-doctor.mdr` | 文心快码（扩展名必须是 `.mdr`） |
| `.lingma/rules/ai-work-doctor.md` | Qoder CN IDE（原通义灵码；单文件 ≤10000 字符，`trigger: always_on`） |
| `.qoder/rules/ai-work-doctor.md` | Qoder IDE / Qoder CLI（`trigger: always_on`，合计 ≤100000 字符） |
| `.cursor/rules/ai-work-doctor.mdc` | Cursor（`.mdc` 带 frontmatter） |
| `.clinerules/`、`.roo/rules/`、`.continue/rules/` | Cline / Roo / Continue |
| `CLAUDE.md`、`GEMINI.md`、`QWEN.md`、`IFLOW.md` | Claude Code / Gemini CLI / Qwen Code / iFlow |
| `.github/copilot-instructions.md` | GitHub Copilot |
| `.github/instructions/ai-work-doctor.instructions.md` | VS Code Copilot（新式指令文件，`applyTo: "**"`） |
| `CONVENTIONS.md` | Aider（也可在 `~/.aider.conf.yml` 里 `read:` 引用 SKILL.md） |
| `AGENT.md` / `.rules` | Zed / Roo 的兼容读取（本项目暂不写，避免污染项目根） |

> **只写一个文件的话，选项目根 `AGENTS.md`**：它是唯一厂商中立、无 frontmatter 要求的约定，
> 本轮核实到的桌面端客户端里绝大多数默认读它。用户级则必须一家一份（`~/.codex`、`~/.trae`、`~/.qoder`
> 各不相同），所以"一键激活"才要扫一遍宿主目录。

## 手动兜底（规则只在 UI 里 / 路径无据可查）

把这段话贴进宿主的「用户规则 / Custom Instructions / Rules / 记忆」设置：

```
执行纪律（ai工作医生）：
1) 同一文件最多读 2 次，同一搜索最多 2 次，超了换方法；
2) 连续 2 轮没有新产出必须换策略或明确上报卡点；
3) 完成前必须有运行时证据：编译通过、端口在听都不算完成；
4) 删除、覆盖、git push --force、reset --hard 之前先备份并等我确认；
5) 起过的后台进程要记 PID，收工前停掉并确认端口释放；
6) 中文 Windows：命令按 GBK 处理，不假设有 grep/sed/head，写完列出改动文件清单。
```

| 宿主 | 贴哪里 |
|---|---|
| Cursor | Settings → Rules → **User Rules**（官方明确：不存在磁盘文件） |
| Windsurf | Cascade → Rules / Memories |
| Trae / Trae CN | 设置 → 规则与记忆 → 规则 → 新建（用户级）；或改用项目级 `.trae/rules/` |
| CodeBuddy | 设置 → 规则 → 新建（选用户级 / 项目级） |
| 文心快码 Comate | 插件右上角 `···` → 规则 → 新建，生效范围选「始终生效」 |
| 通义灵码 → **Qoder CN IDE** | 设置 → 规则/技能 → 新建（生效范围选「始终生效」）；或在对话里 `@rule` 引用 |
| Qoder / Qoder CN CLI | 都读项目 `AGENTS.md`；也可写 `~/.qoder/AGENTS.md`、`~/.qoder-cn/AGENTS.md` |
| iFlow CLI | `~/.iflow/IFLOW.md`（默认不读 AGENTS.md，需改 `contextFileName`）；该产品已停服 |
| 智谱 CodeGeeX | 设置里的「自定义指令」；官方无文件级规则机制，只能对话粘贴 |
| MiniMax Agent · 华为 CodeArts Snap/DevEco · 讯飞 iFlyCode · DeepSeek 客户端 | 官方文档查不到规则文件机制（DeepSeek 客户端无此功能）→ 只能每次对话粘贴常驻卡 |
| Aider | `~/.aider.conf.yml` 里加 `read: [~/.agents/skills/ai-work-doctor/SKILL.md]`；项目里也会读 `CONVENTIONS.md` |
| Continue | 项目内 `.continue/rules/ai-work-doctor.md` |

---

## 装前 vs 装后

| 场景 | 装之前 | 装之后 |
|---|---|---|
| 找一个函数 | 同一个搜索换着写法跑 6 次 | 一条批量搜索，2 次上限，0 命中就换词 |
| 读文件 | 同一文件整篇重读 4 遍 | 首读取行号，之后只读区间，2 次上限 |
| 调试 | "再试一次"×N，没有新信息也不换路 | 连续 2 次无产出 → 打印 `LOOP` → 换维度 → 否则停手报告 |
| 报告完成 | "已部署"（页面其实没变） | 必须给运行时证据，否则不许说完成 |
| 起 dev server | 前台卡住、反复重启、端口残留 | 后台 + 日志 + PID 登记，收工前验证端口释放 |
| 中文 Windows | `grep`/`sed`/`head` 不存在 → 无限试错；GBK 中文搜 0 命中还在重试 | 开头探一次环境；中文关键词首搜即带编码 |
| 危险操作 | `rm -rf`、`reset --hard` 直接执行 | 先备份，不可逆操作先打印 `IMPACT:` 等你确认 |
| 你离开电脑 | 它继续烧几小时 | 先声明预算，每 10 步 `CHECKPOINT`，到点交 HANDOFF |

## 它到底拦住什么

| # | 规则 | 拦住的典型事故 |
|---|---|---|
| R1 | 环境只探一次 | Windows 上 `rg/grep/sed/head` 根本不存在，逐个试错烧 token |
| R2 | 一次建图 | 同一关键词搜 6 次；把 lock 文件/minified 产物整篇读进上下文 |
| R3 | 一读多动 | 同一文件整篇重读 4 次 |
| R4 | 空转熔断 | 连续两轮无新信息还在"再试一次"；`EPERM`/超长路径反复失败 |
| R5 | 行为级验收 | "编译通过/端口在听"被当成"做完了" |
| R6 | 预算上限 | 同一报错重试到天荒地老 |
| R7 | 进程端口收口 | dev server 残留、端口占用、进程越积越多 |
| R8 | 只杀自家进程 | `taskkill /IM node.exe /F` 杀掉你的 IDE |
| R9 | 非交互执行 | `npm login`/`rebase -i` 挂死，会话永久占用 |
| R10 | 先备份后写 | 覆盖用户文件、删掉没进 git 的东西 |
| R11 | 不可逆两阶段闸门 | `push --force`、`reset --hard`、改 PATH/hosts |
| R12 | 密钥不落盘 | token/私钥被写进代码、日志、commit |
| R13 | 无人值守设墙 | 你出门后它跑 3 小时，回来只看到"还在尝试" |
| R14 | 中文 Windows 默认假设 | GBK 乱码、`&&` 语法错、`curl` 别名、BOM 破坏 JSON |

配套还有 [references/desktop-cn.md](references/desktop-cn.md)：**命中症状才读**的命令级坑位表。

## 为什么它不臃肿（三层结构）

| 层 | 内容 | 什么时候进上下文 |
|---|---|---|
| **常驻卡**（安装脚本注入宿主） | 14 条一行规则 + 固定回执格式（20 行） | 每一轮对话（所以必须短） |
| **SKILL.md 正文** | 每条规则的触发/动作/上限/反例、模糊指令映射、边界、自检 | agent 需要时按需加载 |
| **references/desktop-cn.md** | 具体命令与判定（GBK、路径、端口、镜像、挂死命令…） | 撞上对应症状才读 |

安装脚本从 `SKILL.md` 的 `AIW_CORE` 标记里抽取常驻卡（单一来源），幂等写入、`-DryRun` 可预览、`-Uninstall` 可撤销。

---

## 常见问题

**Q：装了没生效？**
① `install.ps1 -List` 看有没有认出你的宿主；② 打开宿主的全局指令文件，确认出现 `<!-- ai-work-doctor:start -->`；
③ **重启宿主 / 新建对话**（多数 agent 只在会话开头或启动时读规则）；④ IDE 型宿主改用项目级 `-Project`；
⑤ 最后兜底：手动粘贴上面那段。

**Q：国产 IDE 的"用户规则"在设置里，脚本怎么管？**
管不了就从文件系统管：Trae 用 `.trae/rules/`、CodeBuddy 用 `.codebuddy/rules/`、Comate 用 `.comate/rules/*.mdr`（项目级），
这些是官方文档写明的项目规则路径，不依赖 GUI 设置。**企业版把规则放云端的，只能手动粘贴。**

**Q：Trae 读不读 `AGENTS.md`？**
读，但要在 设置 → 规则 里打开「将 AGENTS.md 包含在上下文中」。所以项目级我们还额外写
`.trae/rules/ai-work-doctor.md`（`alwaysApply: true`），不依赖那个开关。

**Q：技能列表里搜不到"ai工作医生"？**
列表显示机器名 `ai-work-doctor`。中文名在 `metadata.displayName` 与描述首句里，用于搜索与宣传；
**安装路径永远是 ASCII**（中文目录在 GBK 控制台/CI/Docker 里会惹麻烦）。

**Q：Windows 报执行策略错误？**
用 `powershell -ExecutionPolicy Bypass -File .\install.ps1`，只影响当前进程。

**Q：Defender / SmartScreen 拦了？**
脚本不联网、不改注册表、不装任何东西。可以先 `-DryRun` 看清楚，或手动复制文件（见 INSTALL.md §4）。

**Q：会覆盖我自己的规则吗？**
不会。写入是"保留原文 + 追加标记块"，卸载只删标记块；GBK 老文件按原编码读写，不擅自转码；
`-Uninstall` 时"只剩我们内容"的文件才整份删除。

**Q：和旧的 `anti-loop-discipline` 冲突？**
旧名已废弃。删掉 `~/.agents/skills/anti-loop-discipline`、`~/.codex/skills/anti-loop-discipline` 再装本版本。

---

## 目录结构

```
ai-work-doctor/
├── SKILL.md                  # 技能本体（常驻卡在 AIW_CORE 标记之间，安装脚本只注入这一段）
├── references/desktop-cn.md  # 中文桌面端坑位表（121 行命令级，命中症状才读）
├── install.ps1               # Windows：-List / -Select 菜单 / -Only 点名 / -DryRun / -Uninstall / -Project
├── install.sh                # macOS/Linux/Git Bash 同上（-l / -i / --only / -n / -u / -p）
├── activate.cmd              # Windows 双击激活（默认进宿主选择菜单）
├── docs/
│   ├── why-ai-work-doctor.md # 优势论证、逐条对比、实测证据、已知边界
│   └── github-about.md       # 上传仓库用：About 文案、Topics、Release 模板、首屏顺序
├── INSTALL.md                # 20 个宿主路径 + 官方文档证据 + 手动兜底 + 升级 + 发布检查清单
├── CHANGELOG.md · CONTRIBUTING.md · SECURITY.md · LICENSE
└── .github/                  # Issue 模板 + CI 校验（frontmatter/常驻卡行数/编码/脚本自测）
```

## 它是怎么来的

v2.0 由五个专家视角评审收敛（中文 Windows 环境实测、宿主注入机制、规则工程、开源发布、事故复盘），
v2.1 逐个核实国产 agent 的官方文档后扩表：**只写有据可查的路径，查不到的不猜**——
错的路径会静默失效，比"不支持"更糟。

## License

MIT
