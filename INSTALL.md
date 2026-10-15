# 安装 · 集成 · 升级 · 卸载

> 机器名（安装/目录/URL 一律用它）：`ai-work-doctor` · 中文显示名：`ai工作医生`
> 任何情况下都不用中文目录名装技能：GBK 控制台、CI、Docker 里都会出问题。

## 1. 两种生效面

| 面 | 命令 | 写入位置 | 目标宿主 |
|---|---|---|---|
| 全局（用户级） | `.\install.ps1` / `./install.sh` | 用户目录下的全局指令文件 + 用户级 skills 目录 | CLI 型：Codex CLI、Claude Code、DSH/CC GUI、Trae CLI、CodeBuddy、Qwen Code、Gemini CLI… |
| 项目级 | `.\install.ps1 -Project D:\app` / `./install.sh -p ~/app` | 项目内的规则文件（见 §3） | IDE 型：Trae、CodeBuddy IDE、文心快码、Cursor、Cline、Roo… |

两者可以都做；项目级用同样的标记块机制，卸载互不影响。

### Windows（推荐先预览）

```powershell
cd <仓库目录>
powershell -ExecutionPolicy Bypass -File .\install.ps1 -List                        # 体检：认出哪些宿主
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun                      # 预览：将改哪些文件
powershell -ExecutionPolicy Bypass -File .\install.ps1                              # 激活全局
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Project D:\my-app           # 项目级
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall                   # 卸载全局
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Project D:\my-app -Uninstall
```

不敲命令：双击 **`activate.cmd`**。

| 参数 | 作用 |
|---|---|
| `-List` | 只体检，不写任何文件 |
| `-Select` / `-i` | **交互式菜单**：列出所有宿主 + 是否已安装 + 将写入的路径，让你按编号挑（`1,3,5`、`2-4`、`all`、`detected`、`q`、回车=detected）；执行前再确认一次 |
| `-DryRun` | 打印将写入的路径与字符数，不落盘 |
| `-Project <目录>` | 项目级注入（可多次）；给了它就只做项目级 |
| `-Uninstall` | 只删除本技能写入的标记块 / 技能目录 / "只剩我们内容"的文件 |
| `-All` | 含"未证实路径"的候选宿主（谨慎） |
| `-Only trae,codex` | 只处理指定宿主（支持 `trae`、`trae-cn`、`code-buddy` 这类别名；明确点名 = 没检测到也建） |
| `-Root <目录>` | 指定用户目录（默认 `$HOME`，测试用） |

只给某几个 agent 装的三种写法：

```powershell
.\install.ps1 -Select                      # 进菜单，输 1,3,5 / 2-4 / all / detected / q
.\install.ps1 -Only trae,codex,codebuddy   # 直接点名（脚本友好）
.\install.ps1 -Select -Uninstall           # 菜单里挑要卸载的
.\install.ps1 -Only trae -Uninstall        # 只卸载 Trae
```

### macOS / Linux / Git Bash

```bash
./install.sh -l          # 体检
./install.sh -n          # 预览
./install.sh             # 激活全局
./install.sh -i          # 交互菜单：挑要装哪几个
./install.sh --only trae,codex
./install.sh -p ~/app    # 项目级
./install.sh -u          # 卸载全局
```

## 2. 脚本到底改了什么（可审阅）

1. **注入常驻卡**：把 `SKILL.md` 里 `<!-- AIW_CORE:START --> … <!-- AIW_CORE:END -->` 之间的内容，
   用 `<!-- ai-work-doctor:start -->` / `<!-- ai-work-doctor:end -->` 包起来，**追加**到目标文件末尾。
   - 幂等：内容一致时报"已是最新"，不重复写入；重复运行字节不变；
   - 保留原文件编码（UTF-8 无 BOM / UTF-8 BOM / GBK 原样保留，不擅自转码）；
   - 卸载 = 精确删除两个标记之间的内容；若删除后只剩"我们写的东西"（含 `/---` frontmatter 与自动加的标题行）→ 整文件删除。
2. **复制技能本体**：`SKILL.md` + `references/` → `<宿主技能目录>/ai-work-doctor/`。
3. **只写检测到的宿主**：宿主目录不存在就跳过（`-All` 才强制）。
4. **候选嗅探（国产 IDE 型）**：通义灵码 / Qoder / iFlow 等路径未获官方证实 ——
   只有"该工具目录存在 **且** 它自己的 `rules\` 子目录也存在"时才往里写一个 `.md`，输出里标注"未官方证实"；
   否则明确打印"请手动粘贴"。**绝不凭空创建陌生目录。**
5. 不联网、不写注册表、不装依赖、不需要管理员。常驻卡约 4 KB（Codex `AGENTS.md` 上限 32 KiB、CodeBuddy 建议 500 行以内）。

## 3. 各宿主路径（v2.1 逐条核对官方文档）

### 3.1 全局（用户级）

| 宿主 | 全局指令文件 | 用户级 skills | 证据 | 置信度 |
|---|---|---|---|---|
| Codex CLI | `~/.codex/AGENTS.md` | `~/.codex/skills/` | 源码 `agents_md.rs` + 本机实测 | 高 |
| Claude Code | `~/.claude/CLAUDE.md`（另有 `~/.claude/rules/*.md`） | `~/.claude/skills/` | 官方文档 | 高 |
| DSH / CC GUI | `~/.dsh/AGENTS.md` | `~/.dsh/skills/`、`~/.agents/skills/` | 本机实测 | 高 |
| 通用 SKILL.md 约定 | — | `~/.agents/skills/` | 通用约定 | 高 |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/skills/` | 官方文档 | 高 |
| Qwen Code | `~/.qwen/QWEN.md`（另有 `~/.qwen/rules/`） | `~/.qwen/skills/` | 官方文档 | 高 |
| **Trae（国际）** | `~/.trae/user_rules/ai-work-doctor.md` | `~/.trae/skills/` | docs.trae.ai/ide/rules、/ide/skills | 高 |
| **Trae CN** | `~/.trae-cn/user_rules/ai-work-doctor.md` | `~/.trae-cn/skills/`、`.agents/skills/`（需开关） | docs.trae.cn/ide_rules、/ide_skills | 高 |
| **Trae CLI** | 用项目 `AGENTS.md` / `.trae/rules/` | `~/.traecli/skills/` | docs.trae.cn/cli_skills | 高 |
| **CodeBuddy（腾讯）** | `~/.codebuddy/CODEBUDDY.md` | `~/.codebuddy/skills/` | codebuddy.cn/docs/cli/memory | 高 |
| **文心快码 Comate（百度）** | 个人 Rules 仅 UI 创建，落盘路径未公开 → 不写 | `~/.comate/skills/` | cloud.baidu.com/doc/COMATE | 中 |
| Roo Code | `~/.roo/rules/ai-work-doctor.md` | — | 源码 | 中 |
| Cline | `<Documents>/Cline/Rules/ai-work-doctor.md`（Windows 自动解析 OneDrive 重定向） | — | 官方文档 | 高 |
| **Qoder CLI（阿里）** | `~/.qoder/AGENTS.md`（另有 `~/.qoder/rules/**/*.md`、`~/.qoder/memory/`） | 用户级 skills 路径未明写 → 不写 | docs.qoder.com/cli/memory | 高 |
| **Qoder CN CLI（阿里）** | `~/.qoder-cn/AGENTS.md`（另有 `~/.qoder-cn/rules/**/*.md`） | 同上 | docs.qoder.cn/cli/memory | 高 |
| **Qoder CN IDE（原通义灵码，阿里）** | 用户级规则只在设置/「记忆」里（无文件）→ 不写 | `~/.lingma/skills/`（另有 `~/.lingma/commands/`） | docs.qoder.cn/user-guide/skills | 高 |
| **iFlow CLI（已停服 2026-04）** | `~/.iflow/IFLOW.md`（默认不读 AGENTS.md，须改 `contextFileName`） | — | platform.iflow.cn/cli/configuration/iflow | 中 |
| **Kimi Code CLI（月之暗面）** | 无全局 AGENTS.md（配置在 `~/.kimi/config.toml`） | `~/.kimi/skills/`（也读 `~/.agents/`、`~/.claude/`、`~/.codex/skills/`） | kimi-cli `docs/en/customization/skills.md` | 高 |
| **Zed** | `~/.config/zed/AGENTS.md`；Windows `%APPDATA%\Zed\AGENTS.md` | 通过 `~/.agents/skills/`、`.agents/skills/` | zed.dev/docs/ai/instructions | 高 |
| **VS Code Copilot（用户级）** | `~/.copilot/copilot-instructions.md` | — | code.visualstudio.com/docs/copilot/customization/custom-instructions | 高 |
| Cursor | **无文件**（User Rules 只在设置里） | 通过 `~/.agents/skills/` 生效 | 官方文档 | 高 |
| Windsurf / CodeGeeX | **无可靠路径** → 手动粘贴 | — | 官方文档/官网产物 | 中 |

**命名变更**：通义灵码已更名 **Qoder CN**（2026-05-20 官方公告），iFlow CLI 2026-04-17 停服并指向 Qoder，上表按新名收录。
Qoder 家族的**全局规则文件**只有 CLI 有（`AGENTS.md`）；IDE 的规则只在项目级与设置里，所以 IDE 只注入项目文件。

**故意不做的**：Codex `config.toml` 没有"指令文件"这类键（不要写）；`~/.openhands/skills/` 是公共缓存（不要写）；
MarsCode / 豆包 / 火山引擎的规则文件查不到（不猜）；CodeGeeX 官方无文件级规则机制（不写）；
Qoder IDE 的 `~/.qoder/skills`（仅本机实测存在，官方未写）不写。

### 3.2 项目级（`-Project` / `-p`）

| 文件 | 谁读 | frontmatter |
|---|---|---|
| `AGENTS.md` | Codex、DSH、OpenHands、Trae CLI、CodeBuddy（无 `CODEBUDDY.md` 时） | — |
| `CODEBUDDY.md` | CodeBuddy CLI/IDE（**优先级高于 AGENTS.md**，存在它就不读 AGENTS.md） | — |
| `.trae/rules/ai-work-doctor.md` | Trae / Trae CN（不依赖"包含 AGENTS.md"开关） | `alwaysApply: true` |
| `.codebuddy/rules/ai-work-doctor/RULE.mdc` | CodeBuddy IDE（**每规则一个目录 + `RULE.mdc`**；CLI 是 `rules/*.md` 平铺，结构写错会静默不生效） | `alwaysApply` / `enabled` |
| `.comate/rules/ai-work-doctor.mdr` | 文心快码（**扩展名必须是 `.mdr`**，内容是 Markdown；生效范围建议在 UI 里选「始终生效」） | — |
| `.lingma/rules/ai-work-doctor.md` | Qoder CN IDE（原通义灵码；**单文件 ≤10000 字符**） | `trigger: always_on` + `alwaysApply: true` |
| `.qoder/rules/ai-work-doctor.md` | Qoder IDE / Qoder CLI（**合计 ≤100000 字符**） | `trigger: always_on` + `alwaysApply: true` |
| `.cursor/rules/ai-work-doctor.mdc` | Cursor（只认 `.mdc`，同目录 `.md` 会被忽略） | `alwaysApply: true` |
| `.clinerules/ai-work-doctor.md` | Cline | — |
| `.roo/rules/ai-work-doctor.md` | Roo Code | — |
| `.continue/rules/ai-work-doctor.md` | Continue | — |
| `CLAUDE.md` / `GEMINI.md` / `QWEN.md` / `IFLOW.md` | Claude Code / Gemini CLI / Qwen Code / iFlow CLI | — |
| `CONVENTIONS.md` | Aider（也可在 `~/.aider.conf.yml` 用 `read:` 直接引 SKILL.md） | — |
| `.github/copilot-instructions.md` | GitHub Copilot | — |
| `.github/instructions/ai-work-doctor.instructions.md` | VS Code Copilot 新式指令文件 | `applyTo: "**"` |

未纳入：`AGENT.md`、`.rules`（Zed/Roo 兼容读，但会污染项目根，收益低）；`llms.txt`（只是文档索引，不是规则注入点）；
`.trae/skills`、`.cline/skills`（项目级技能目录，本项目只注入规则文件）。

## 4. 手动兜底（规则只在 UI / 云端里）

把这段话贴进宿主的「用户规则 / Custom Instructions / Rules / 记忆」：

```
执行纪律（ai工作医生 / ai-work-doctor）：
1) 同一文件最多读 2 次，同一搜索最多 2 次，超了换方法；
2) 连续 2 轮没有新产出必须换策略或明确上报卡点；
3) 完成前必须有运行时证据：编译通过、端口在听都不算完成；
4) 删除、覆盖、git push --force、reset --hard 之前先备份并等我确认；
5) 起过的后台进程要记 PID，收工前停掉并确认端口释放；
6) 中文 Windows：命令按 GBK 处理，不假设有 grep/sed/head，写完列出改动文件清单。
```

| 宿主 | 位置 |
|---|---|
| Cursor | Settings → Rules → User Rules |
| Windsurf | Cascade → Rules / Memories |
| Trae / Trae CN | 设置 → 规则与记忆 → 规则 → 新建（用户级） |
| CodeBuddy | 设置 → 规则 → 新建（用户级/项目级） |
| 文心快码 Comate | 插件 `···` → 规则 → 新建，范围选「始终生效」 |
| Qoder CN IDE（原通义灵码） | 设置 → 规则/技能 → 新建，「生效范围」选**始终生效**（或用 `@rule` 引用） |
| Qoder / Qoder CN CLI · iFlow CLI | 都读项目 `AGENTS.md`；iFlow 还需把 `contextFileName` 设为 `AGENTS.md` |
| 智谱 CodeGeeX | 设置里的「自定义指令」；官方无文件机制，只能对话粘贴 |
| MiniMax · 华为 CodeArts Snap / DevEco CodeGenie · 讯飞 iFlyCode · DeepSeek 客户端 | 官方文档查不到规则文件机制（DeepSeek 客户端无此功能）→ 只能每次对话粘贴常驻卡 |
| Aider | `~/.aider.conf.yml` 加 `read: [~/.agents/skills/ai-work-doctor/SKILL.md]` |
| Continue | 项目内 `.continue/rules/ai-work-doctor.md` |

## 5. 远程安装（发布后）

> ⚠️ 维护者注意：下面 URL 里的 `foyeya` 必须在首次发布前替换成真实 GitHub 用户名/组织名，否则用户拿到 404。
> 仓库名保持 ASCII：`ai-work-doctor`。

```powershell
# Windows：先下载再执行（可审阅，别用 irm | iex）
$d = "$env:TEMP\ai-work-doctor"; New-Item -ItemType Directory -Force -Path $d | Out-Null
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/foyeya/ai-work-doctor/main/install.ps1' -OutFile "$d\install.ps1"
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/foyeya/ai-work-doctor/main/SKILL.md'    -OutFile "$d\SKILL.md"
Get-Content "$d\install.ps1" -TotalCount 20
powershell -ExecutionPolicy Bypass -File "$d\install.ps1" -DryRun
```

```bash
# macOS / Linux
curl -fsSL -o /tmp/aiw-install.sh https://raw.githubusercontent.com/foyeya/ai-work-doctor/main/install.sh
less /tmp/aiw-install.sh && bash /tmp/aiw-install.sh -n
```

国内拉 raw.githubusercontent 常失败：优先用 **Release 附件 zip** 或 gitee 镜像；同一 URL 最多试 2 次，
第 3 次必须换源（和技能里的 R14 是同一条纪律）。

## 6. 升级 / 旧名冲突

旧名 `anti-loop-discipline` 已废弃（v1.3.0 改名，v2.0 改结构，v2.1 增国产宿主与项目级）：

```bash
rm -rf ~/.agents/skills/anti-loop-discipline ~/.codex/skills/anti-loop-discipline
```

然后重新跑一键激活。列表里同时出现两条 = 旧目录没删干净。

## 7. 验证生效

- 全局：新开对话问 **"说出 ai工作医生 的预算上限"** → `read 2 / search 2 / deploy 2 / no-op 2 / tool-err 3`。
- 项目级：在项目里让 agent 做一个小任务，看它是否**一条**批量搜索、并在回复里列出改动文件；
  故意让它撞一个不存在的命令（如 `rg`），看它是否一次探测后改用 `Select-String` 而不是反复重试。
- 国产 IDE：改完规则**必须新建对话**（Trae / CodeBuddy 都在会话开头注入规则）；CodeBuddy 插件需重启或重载项目才会扫描 `.codebuddy/rules`。

## 8. 发布前检查清单（维护者）

- [ ] `SKILL.md` 第一行必须是裸 `---`（不能是 `\---`，否则 frontmatter 非法、宿主静默忽略整条技能）
- [ ] `name:` 匹配 `^[a-z0-9]+(?:-[a-z0-9]+)*$`（中文名放 `metadata.displayName`）
- [ ] 仓库内所有 `foyeya` 占位符（README/INSTALL/Issue 模板）已替换
- [ ] `install.ps1` 存为 **UTF-8 with BOM**；`install.sh` 用 LF；`activate.cmd` 用 CRLF
- [ ] 跑 `.github/workflows/validate.yml`（frontmatter、name 正则、常驻卡行数、编码、脚本语法、全局+项目级自测）
- [ ] Release 附件：`ai-work-doctor-vX.Y.Z.zip` + `SHA256SUMS.txt`，zip 内目录名保持 ASCII
- [ ] 老版本 zip 从工作区清掉，避免和发行物混淆

## 9. 装完怎么验证（三个层次，从便宜到贵）

```powershell
# ① 30 秒：确认常驻卡真的被宿主读了（必须新开对话，别在当前对话里问）
#    问它：说出 ai工作医生 的预算上限
#    期望：read 2 / search 2 / deploy 2 / no-op 2 / 预埋失败 3

# ② 1 分钟：机械审计常驻卡本身（有没有被改坏、有没有超长、每条规则是否可判定）
.\eval\card-audit.ps1
.\eval\card-audit.ps1 -SelfTest    # 判定器自证：坏样本必抓、好样本不误伤

# ③ 40 分钟（可选）：14 条行为探针，装前/装后成对对比
.\eval\run.ps1 -List
.\eval\run.ps1 -Model "你的模型" -Phase before      # 先卸载或换干净宿主
.\eval\run.ps1 -Model "你的模型" -Phase after       # 装上后重开宿主
.\eval\run.ps1 -Report                              # 成对差值 + 硬失败清单

# ④ 给任意一段会话转录打分（CC GUI 里复制出来就行）
.\eval\scan.ps1 -Path 会话.txt
```

判定口径：**成对差值 ≥5 且硬失败数下降**才算有效提升；档位只作参考。
两个评审器都带 `-SelfTest` 并已进 CI——判定器自己不可信时，评测没有意义。

**回滚**：`.\install.ps1 -Uninstall`（只删本技能写入的标记块；`.aiw\ledger.md` 属于用户，本插件不动它）。
