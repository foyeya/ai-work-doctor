# Changelog

## 2.3.0 (2026-10-15)

**按真实事故补的两条闸门**：用户只发了「在」，agent 烧了 3 轮思考 + 4 次工具调用，其中一条
`Get-ChildItem C:\ D:\ Desktop Downloads -Recurse -Depth 3` **跑了 1 分 53 秒**、吐回一堆无关文件，
最后什么也没交付。原因是卡片缺两件事：**输入不足时该不该先问**，以及**单条命令的成本上限**。

### 新增 R0 输入闸门（INPUT GATE，写在卡片第 0 行 = 最高优先）
- 触发：用户消息里没有「对象 + 动作」（只发"在 / 在吗 / ？ / 继续"，或明显被截断）。
- 动作：**零工具调用**——不探测、不搜索、不建目录、不写文件，只回一句问清目标并给 2–3 个方向。
- 明确写上"**压过**'不要反问/先交付'之类约定"，因为这类约定正是上次事故的推力来源。
- 例外：工作区里已有明确线索（用户上一条给过文件名/目标）→ 按线索推进，不要问。

### R2 增补"成本上限" + R6 增补时间维度
- **禁止从盘符根递归**（`Get-ChildItem C:\ -Recurse`、`dir /s D:\`、`find / -name`）；搜索必须限定目录 + 深度 ≤3 + 超时。
- **单条命令 20 秒**上限，超时即中止换法（写进 R6 预算表）。
- 新增"某个软件/文件在哪"的 **5 秒级定位法**：`where.exe` → 注册表 `App Paths` → `MUICache`/`Compatibility
  Assistant\Store` → `Prefetch` → 开始菜单 `.lnk` 解析 → 服务与启动项；都找不到再问用户，最后才限定目录递归。
  实测：全盘递归 1 分 53 秒没找到的东西，注册表两行命令 1 秒拿到。

### 文档同步
- `references/desktop-cn.md`：新增成本上限行 + §1.1「5 秒级定位法」全套可复制命令。
- README / README.en.md：规则表加 R0（英文版标题改 The 15 rules）、手动兜底粘贴段落加第 0 条。
- 版本号 2.3.0；常驻卡 20 → 22 行（仍然短，因为它每轮都在上下文里）。

## 2.2.1 (2026-10-15)

**只改文档，无行为变更**：把"凭什么用这个插件"讲清楚，方便开源仓库首屏一眼看懂。

- README 首屏重写：一句人话 + 三条承诺（不空转 / 不假装完成 / 不搞坏机器）+ 「30 秒看懂」流程图 +
  「和其他做法比，差在哪」对照表 + 「六条别人没做的」优势表（**每条都写"你怎么验证"**）+ 诚实边界声明。
- 新增 `docs/why-ai-work-doctor.md`：完整论证——四种固定失效模式、为什么提醒式 prompt 无效、
  14 条规则的设计原则与分工、逐条对比、20 个宿主与证据链、中文桌面端专项清单、工程质量与验证方式、
  **已知边界（做不到的 5 条）**、谁该用/谁不必用。
- 新增 `docs/github-about.md`：上传仓库用——仓库名/About 中英文案/Topics 建议/Release 标题与正文模板/
  附件清单/首屏顺序/首个 pinned issue 文案（"装了没生效？先看这 5 步"）。
- README 目录结构补上 `docs/`，并更新 `install.ps1` / `install.sh` 的参数摘要。

## 2.2.0 (2026-10-15)

**按 agent 单独安装 / 卸载**：用户不必再"全装一遍"，可以只给自己真在用的那几个宿主装。

### 新增
- **交互式菜单**：`install.ps1 -Select` / `install.sh -i|--select`。列出每个宿主的「是否已安装 + 将写入哪个文件」，
  支持按编号多选（`1,3,5`）、区间（`2-4`）、`all`（全选，含未检测到的）、`detected`（只装检测到的）、`q`（退出）；
  回车默认 = 只装检测到的。执行前再确认一次；`-DryRun` 时跳过确认。
- **双击版直接进菜单**：`activate.cmd` 默认带 `-Select`，Windows 用户不用记任何参数。
- **点名式非交互**：`-Only trae,codex`，支持别名与模糊匹配（`trae`、`trae-cn`、`trae_cn`、`code-buddy` 都认）。
  **明确点名 = 明确意图**：该宿主即使当前没检测到也按你的意思建目录（等价于只对这一个宿主用 `-All`），其它宿主一律不动。
- **按 agent 卸载**：`-Select -Uninstall`（菜单里挑）或 `-Only trae -Uninstall`（点名）。
- `-Select` 与 `-Project` 同时给 → 只警告并忽略菜单，项目级照常执行。

### 为什么
"一键全装"对只用一个客户端的人是多写的文件；而 IDE 型 agent 的用户往往只想装自己那一个。
现在三条路都通：全装（默认）/ 菜单挑（`-Select`）/ 点名（`-Only`），三条路都幂等、都可预览、都可撤销。

## 2.1.0 (2026-10-15)

**国产桌面端 agent 支持**：把只支持"英文系 CLI"的注入表扩成"国产 IDE 型 agent 也能生效"，并新增项目级模式。

### 新增：两种生效面
- **全局（用户级）**：`install.ps1` / `install.sh` 注入用户级全局指令文件 + 复制技能到用户级 skills 目录。
- **项目级（新）**：`-Project <目录>` / `--project <目录>`，往项目里写各 IDE 型 agent 认的项目规则文件
  （`AGENTS.md`、`CLAUDE.md`、`GEMINI.md`、`QWEN.md`、`CODEBUDDY.md`、`.trae/rules/*.md`、
  `.codebuddy/rules/<name>/RULE.mdc`、`.comate/rules/*.mdr`、`.cursor/rules/*.mdc`、`.clinerules/`、
  `.roo/rules/`、`.continue/rules/`、`.github/copilot-instructions.md`），同样幂等、可预览、可卸载。

### 新增：国产 agent 注入（每条都有官方文档依据）
- **Trae / Trae CN / Trae CLI（字节）**：全局 `~/.trae/user_rules/`、`~/.trae-cn/user_rules/`；
  项目 `.trae/rules/*.md`（frontmatter `alwaysApply: true`）；技能目录 `~/.trae/skills`、`~/.trae-cn/skills`、`~/.traecli/skills`。
- **CodeBuddy（腾讯）**：全局 `~/.codebuddy/CODEBUDDY.md`；项目 `CODEBUDDY.md` +
  `.codebuddy/rules/<name>/RULE.mdc`（IDE 形态，frontmatter `alwaysApply`/`enabled`）；技能 `~/.codebuddy/skills/`。
  注意 IDE 读 AGENTS.md 的前提是"该目录没有 CODEBUDDY.md"。
- **文心快码 Comate（百度）**：项目 `.comate/rules/*.mdr`（扩展名必须是 `.mdr`，内容是 Markdown）；技能 `~/.comate/skills/`。
- **Qoder 家族（阿里）**：Qoder CLI `~/.qoder/AGENTS.md`、Qoder CN CLI `~/.qoder-cn/AGENTS.md`；
  项目 `.qoder/rules/*.md`（Qoder IDE/CLI）与 `.lingma/rules/*.md`（Qoder CN IDE，原通义灵码），
  frontmatter 一律写 `trigger: always_on`（CN IDE 缺省行为无文档保证）；技能 `~/.lingma/skills/`。
  命名变更说明：通义灵码 2026-05-20 更名 Qoder CN；iFlow CLI 2026-04-17 停服。
- **Kimi Code CLI（月之暗面）**：技能 `~/.kimi/skills/`（它也读 `~/.agents/skills/`、`~/.claude/skills/`、`~/.codex/skills/`）。
- **iFlow CLI（停服）**：`~/.iflow/IFLOW.md`（项目/用户级）。
- **Zed**：`~/.config/zed/AGENTS.md`、Windows `%APPDATA%\Zed\AGENTS.md`。
- **VS Code Copilot**：用户级 `~/.copilot/copilot-instructions.md`；项目级 `.github/copilot-instructions.md`、
  `.github/instructions/*.instructions.md`（`applyTo: "**"`）。
- **Aider**：项目 `CONVENTIONS.md`（另有 `~/.aider.conf.yml` 的 `read:` 手动方式）。
- **候选嗅探机制保留**：将来遇到"路径查不到但用户想试"的宿主，只在该工具目录与它自己的 `rules\` 子目录都存在时才写，
  并在输出里标注"未官方证实"。v2.1 的候选表为空 —— 已支持宿主全部有文档依据。

### 查不到、因此**不写任何文件**（只给手动兜底）
MarsCode（已并入 Trae）、豆包/火山引擎、智谱 CodeGeeX（官方无文件级规则机制）、
MiniMax Agent、华为 CodeArts Snap / DevEco CodeGenie、讯飞 iFlyCode、DeepSeek 官方客户端（无此功能）、
Windsurf 全局规则、Cursor 的 User Rules（官方明确"不存在磁盘文件"）、`llms.txt`（只是文档索引，非注入点）。

### 修正
- 项目级 Trae 规则不再写死 `.trae/rules/project_rules.md`（那是 Trae UI 自己的文件名，可能覆盖用户内容），
  改为独立的 `.trae/rules/ai-work-doctor.md`。
- 卸载时若目标文件"只剩我们写的内容"（含 `.mdc`/`.mdr` frontmatter 与自动加的标题行）→ 整文件删除，不留空壳。
- 全局注入表新增 DSH/CC GUI 说明（CC GUI 走 `~/.dsh/` 与 `~/.agents/skills/`）。

### 说明
本版所有路径都经过官方文档/源码核对；凡"查不到"的一律不写文件、只给手动兜底 —— 错的路径会静默失效，
比"不支持"更糟。文档核对的证据链接见 `INSTALL.md` 兼容矩阵。

## 2.0.0 (2026-10-15)

面向桌面端 agent 的大改版：规则重写、加一键激活、补齐中文 Windows 与"真实机器不可逆损失"的防护。

### 新增
- **一键激活**：`install.ps1`（Windows）/ `install.sh`（macOS/Linux/Git Bash）/ `activate.cmd`（双击）。
  幂等、可预览（`-DryRun`/`-n`）、可卸载（`-Uninstall`/`--uninstall`）、只写检测到的宿主、
  保留原文件编码（UTF-8 / UTF-8 BOM / GBK 都不擅自转码）、无网络、不需要管理员。
- **常驻卡单一来源**：`SKILL.md` 内 `<!-- AIW_CORE:START -->…<!-- AIW_CORE:END -->` 之间的内容就是注入宿主
  全局指令文件的那一段，安装脚本直接抽取，避免两份内容漂移。常驻卡 14 行、约 4 KB。
- **`references/desktop-cn.md`**：中文桌面端命令级坑位表（编码 / 路径权限 / Shell 差异 / 进程端口 /
  国内镜像源 / 假成功 / 交互式挂死 / 并发写 / 无人值守 / 危险操作）。
- **反馈回执格式**：`[STAGE]`、`LOOP at N:`、`BUDGET:`、`CHECKPOINT:`、`BLOCKED:`、`HANDOFF`。
- **仓库配套**：`.gitattributes`、`CONTRIBUTING.md`、`SECURITY.md`、Issue 模板、`validate.yml` 校验工作流。

### 规则集重写（R1–R14）
- 新增 R1 环境只探一次（Windows 上 `rg`/`grep`/`sed`/`head` 常常根本不存在，逐个试错是最高频烧 token 行为）。
- 新增 R7 进程端口收口、R8 只杀自家进程、R9 非交互执行 —— 桌面端（真实进程/端口）特有故障。
- 新增 R10 备份后写（含并发写保护与哈希校验）、R11 不可逆操作两阶段闸门（`IMPACT:` + 等确认）、
  R12 密钥不落盘 —— 直接操作用户真实文件带来的不可逆损失。
- 新增 R13 无人值守设墙（预算 + `CHECKPOINT` + `HANDOFF`）。
- 新增 R4 里的"同路径连续 2 次 `EPERM`/`ENAMETOOLONG`/写后消失 → 停手诊断"熔断。
- 保留并收紧 R2/R3/R5/R6/R14；把原 R6（事件链审计）从常驻卡移出（触发条件无法机械判定）。

### 修正（基于本机与官方文档实测，不是推测）
- 删除"`grep` 兜底"的错误假设：GNU grep **不做转码**，用 UTF-8 中文 pattern 搜 GBK 文件是**静默 0 命中**，
  不是报编码错。改为"中文关键词首搜即带编码"（`Select-String -Encoding Default` / `rg --encoding gbk`）。
- 删除 Windsurf / Continue 全局层 / Cursor / OpenHands 的未证实写入路径：
  Cursor 的 User Rules **不在文件系统**，`~/.openhands/skills/` 是公共缓存 —— 一律改走手动粘贴兜底。
- Cline 的 `Documents` 目录改为读注册表解析（OneDrive 重定向场景）。
- 补充 Windows 写入陷阱：PS 5.1 的 `Out-File -Encoding utf8` 会写 BOM（破坏 JSON/frontmatter）、
  5.1 没有 `utf8NoBOM`、`curl` 是 `Invoke-WebRequest` 别名、`mkdir` 没有 `-p`、
  Git for Windows 默认 `core.autocrlf=true` 导致 `.sh` 检出 CRLF（`bad interpreter ^M`）。
- 删除原 C3 里"抓紧/快点 → 预算减半、直接上正解"这类无法机械判定的条款（保留其余模糊指令映射）。

### 评审
v2.0 由 5 个独立专家视角评审后收敛：中文 Windows 环境（本机实测）、宿主注入机制（逐个核实官方文档）、
规则工程（常驻卡 ≤30 行、无数字上限的口号一律不进）、开源发布（可审阅/幂等/可卸载/无占位符）、
事故复盘（不可逆损失清单）。凡"查不到证据"的宿主路径一律不猜。

## 1.3.0 (2026-10-15)

- Renamed to **ai工作医生** (AI Work Doctor). Machine id: `ai-work-doctor`
  (was `anti-loop-discipline`); display name and `metadata.displayName` are Chinese.
- `name` stays ASCII on purpose: skill loaders (DSH / Codex / Claude Code) validate it
  against `^[a-z0-9]+(?:-[a-z0-9]+)*$` and silently drop a skill whose name is Chinese.
- README / INSTALL updated to the new name and install paths (`~/.agents/skills/ai-work-doctor`,
  `~/.codex/skills/ai-work-doctor`, `~/.claude/skills/ai-work-doctor`).

## 1.2.0 (2026-10-15)

- Added Chinese-task clauses C1-C4 (search encoding fallback chain, Windows GBK
  console defaults, vague-instruction→acceptance mapping, Chinese file/log loop
  traps).
- description now advertises Chinese-task support.

## 1.1.0 (2026-10-15)

- Cross-framework/cross-model/cross-task-type metadata and description.
- New Rule 9 (environment adaptation: verify tool once, note fallback, batch
  remote commands) and Rule 10 (reproduce-before-patch for bugs).
- Budget table gains "same API/tool error x3".
- Behavioral verification table by change type (UI/API/logic/config/docs).
- Search examples: rg + grep fallback + remote output cap.
- Standardized HANDOFF template (Goal/Done/Blocked/Next/Do-not-redo).
- Quick Reference card added.

## 1.0.0 (2026-10-15)

- Initial release: 8 rules extracted from a real production incident.
