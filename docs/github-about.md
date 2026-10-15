# 上传开源仓库：首屏与元信息（复制粘贴用）

> 这份文档只服务一件事：**让人 10 秒内看出这个插件是干什么的、凭什么用它**。
> 里面的文字可以直接粘到 GitHub 的对应输入框。

## 1. 仓库信息

| 项 | 建议值 | 理由 |
|---|---|---|
| 仓库名 | `ai-work-doctor` | ASCII，URL 干净、clone/CI/Docker 无坑 |
| 显示名 / 宣传名 | `ai工作医生` | 中文搜索与口碑传播用；**只做显示层，不做路径** |
| 一句话（About） | 见下方 | ≤350 字符 |
| Topics | 见下方 | 中英都放，覆盖"技能名 + 宿主名 + 场景" |
| 默认分支 | `main` | — |
| Release 标题 | `ai工作医生 vX.Y.Z（ai-work-doctor）` | 中英同现，搜索两条都能命中 |

### About（中文，推荐）

```
给你的桌面端 AI 编程助手装「熔断器」：不让它空转、不假装完成、不把你的机器搞坏。
一条命令注入全局，永久生效，换任何模型都吃。覆盖 20 个桌面端 agent（Trae / CodeBuddy / 文心快码 / Qoder 通义灵码 / Kimi / Codex / Claude Code / Cursor …）+ 18 个项目级注入点。零依赖、不联网、可预览、可精确卸载。
```

### About（English，可选，末尾加在中文后面）

```
Hard circuit-breakers for desktop coding agents: no more repeated reads, no more fake
"deployed OK", no more `rm -rf` on your real machine. One command installs it globally
for 20 agents (Trae, CodeBuddy, Comate, Qoder, Kimi, Codex, Claude Code, Cursor…),
works with any model, zero dependencies, fully reversible.
```

### Topics（建议全填）

```
ai, ai-agents, coding-agent, agent-reliability, llm, prompt-engineering,
skill, skill-md, claude-code, codex, cursor, cline, copilot, zed,
trae, codebuddy, comate, qoder, lingma, kimi, qwen-code, windows, chinese, developer-tools
```

## 2. 首屏顺序（README 已经按这个排好了）

1. **标题 + 一句人话**：给桌面端 AI 编程助手装「熔断器 + 行车记录仪」
2. **三条承诺**（表格，一眼看懂）：不空转 / 不假装完成 / 不搞坏机器
3. **30 秒看懂**（ASCII 流程图：一条命令 → 注入宿主全局指令 → 每轮对话自动生效）
4. **和其他做法比，差在哪**（对照表：裸 agent / 提醒式 prompt / 云端沙箱 / 本插件）
5. **六条别人没做的**（优势表，每条都写"你怎么验证"）
6. **30 秒上手** + 验证方法 + 卸载
7. 兼容矩阵（20 个宿主 + 证据链接）→ 手动兜底 → FAQ

**要点**：优势不要只写形容词，每条后面都要有"你能怎么验证"。README 里所有卖点都对应一条可执行命令或可观测行为。

## 3. Release 文案模板

```markdown
# ai工作医生 v2.2.1（ai-work-doctor）

给你的桌面端 AI 编程助手装「熔断器」：不让它空转、不假装完成、不把你的机器搞坏。

## 这个版本有什么
- …（每条一句，动词开头）

## 装机（选一个）
Windows：解压后双击 `activate.cmd`，或
  powershell -ExecutionPolicy Bypass -File .\install.ps1 -Select
macOS / Linux：./install.sh -i

## 验证生效
新开一个对话，问「说出 ai工作医生 的预算上限」→ read 2 / search 2 / deploy 2 / no-op 2 / tool-err 3

## 卸载
.\install.ps1 -Uninstall（只删本技能写入的内容）

## 校验
见附件 SHA256SUMS.txt
```

## 4. Release 附件清单

| 附件 | 说明 |
|---|---|
| `ai-work-doctor-vX.Y.Z.zip` | 完整包，zip 内顶层目录名保持 ASCII |
| `SHA256SUMS.txt` | 逐文件哈希 + zip 自身哈希 |
| （可选）`README-安装.txt` | 给 GBK 控制台用户看的纯文本版安装步骤 |

国内网络拉 `raw.githubusercontent.com` 常失败 → **优先引导下载 Release 附件**或 gitee 镜像；
README/INSTALL 里已经写明"同一 URL 最多试 2 次，第 3 次必须换源"。

## 5. 首次发布前的检查清单

见 [INSTALL.md](../INSTALL.md) §8，摘要：

- [ ] `SKILL.md` 第一行是**裸 `---`**（`\---` 会让宿主静默忽略整条技能）
- [ ] `name:` 匹配 `^[a-z0-9]+(?:-[a-z0-9]+)*$`（中文名只放 `metadata.displayName`）
- [ ] 所有 `foyeya` 占位符已替换（README / INSTALL / Issue 模板）
- [ ] `install.ps1` = UTF-8 **with BOM**；`install.sh` = LF；`activate.cmd` = CRLF
- [ ] CI（`.github/workflows/validate.yml`）全绿：frontmatter / name 正则 / 常驻卡行数 / 编码 / 脚本语法 / 安装自测
- [ ] Release 附件与 `SHA256SUMS.txt` 一致

## 6. 建议的第一个 pinned issue

标题：**装了没生效？先看这 5 步**
正文：① `install.ps1 -List` 看是否认出宿主 → ② 打开宿主全局指令文件确认有 `<!-- ai-work-doctor:start -->` →
③ **重启宿主 / 新开对话**（多数 agent 只在启动或会话开头读规则）→ ④ IDE 型宿主改用 `-Project` 项目级注入 →
⑤ 兜底：把 README「手动兜底」那段粘进设置里。

> 这条能把最常见的 issue 挡在门外：**90% 的"没生效"是没新开对话，或者宿主根本不读文件（规则存在 UI/账号里）。**
