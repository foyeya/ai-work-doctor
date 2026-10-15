# 中文桌面端坑位表（命中即用，一次修好）

> 这是 SKILL.md 的**按需附件**：只在真的撞上对应症状时才读、才执行。
> 通用纪律：**同一命令最多 2 次**；第 3 次必须换工具/换参数/换路径，并在回复里说明换了什么。

## 0. 先探一次环境（别一个个试错）

```powershell
$PSVersionTable.PSVersion      # 5.1 与 7.x 行为不同，必须先知道
chcp                            # 936 = GBK/中文，65001 = UTF-8
Get-Command rg,git,node,npm,python,curl,findstr -ErrorAction SilentlyContinue |
  Select-Object Name,Version
```

**Windows 自带的真相**（本机与大多数中文 Windows 实测）：`rg`、`grep`、`sed`、`awk`、`head`、`wc`、`iconv`
**默认都不存在**，只有 `findstr.exe`、`curl.exe`、`git`、`node`、`npm`、`python`。
所以命令里出现 `grep`/`sed ... | head` 会直接报"无法识别"，然后 agent 就开始无限试错——这是最高频的坑。

## 1. 搜索（含中文关键词）

| 场景 | 正确写法 |
|---|---|
| 有 `rg`（探测到再用） | `rg -n "符号\|类名" -g '*.{ts,py,md}'`；GBK 文件加 `--encoding gbk` |
| Windows 兜底（**GBK 文件也能命中**） | `Select-String -Path .\src\*.ts -Pattern '符号\|类名' -Encoding Default`（Default = 当前代码页 936） |
| 再兜底 | `findstr /s /n /i /c:"符号" *.ts` |
| 中文 0 命中 | **不代表不存在**：GNU grep 不做转码，UTF-8 pattern 搜 GBK 文件是**静默 0 命中**。换编码/换同义词/换英文标识符，最多 3 条命令，然后问用户入口 |
| 限定范围 | 加 `-Include`/`-g`；不要把 `node_modules`、lock 文件、minified 产物读进上下文 |

## 2. 编码（GBK / 936）

| 症状 | 一次修好 |
|---|---|
| 中文输出乱码、`UnicodeEncodeError`、`'gbk' codec can't decode/encode` | 先设一次：`[Console]::OutputEncoding=[Text.Encoding]::UTF8; $OutputEncoding=[Text.Encoding]::UTF8`；Python 加 `$env:PYTHONIOENCODING='utf-8'`。设完继续，**不要重跑那条注定报错的命令** |
| 中文/emoji 走管道就崩 | 不要打印，落盘再读：`... \| Out-File -Encoding utf8 run.log`（注意 BOM 见下一行） |
| 写 JSON / frontmatter 后解析报错 | PS 5.1 的 `Out-File -Encoding utf8` 会加 BOM，`\|\|` 用 `>` 默认写 UTF-16LE。改用：<br>`[IO.File]::WriteAllText($p,$t,(New-Object Text.UTF8Encoding($false)))` |
| 含中文的 `.ps1` 执行报错/中文变问号 | PS 5.1 必须存 **UTF-8 with BOM**；PS 7 用 UTF-8 无 BOM。读用 `Get-Content -Encoding UTF8` |
| 老文件是 GBK | 显式按 GBK 读（Python `encoding='gbk'`、Node `iconv-lite`），**不要"顺手统一成 UTF-8"** |
| Git 把中文文件名显示成 `\344\270\255` | `git config --global core.quotepath false` |

## 3. 路径与权限

- 含空格/中文/括号的路径**一律加引号**；PowerShell 用 `-LiteralPath` 避免通配符被解释。
- `ENAMETOOLONG` / "文件名或扩展名太长"：项目放盘根短目录（`C:\dev\x`）；必要时开长路径
  （管理员：`Set-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' LongPathsEnabled 1`）。
- 用户名是中文（`C:\Users\张三`）：node-gyp / MSBuild / 部分 venv 会炸 → 项目放 `C:\dev\...`，临时目录指到 ASCII 路径。
- `EPERM` / `EBUSY` / "无法删除，正在被另一进程使用" / "写完文件却回到原样"：
  先停 dev server、关预览、退出占用进程；仍失败考虑 Defender 实时防护拦截 → 让用户加排除项，或换目录。
  **同一路径连续 2 次失败就停手诊断，不做第 3 次重试。**
- 目录被 OneDrive 同步（Desktop/Documents 重定向）：文件锁 + 文件监听不触发 → 项目移出同步目录。
- 软链：`New-Item -ItemType Junction -Path <链接> -Target <目标>`（不需要管理员；`SymbolicLink` 才要）。

## 4. Shell 差异（agent 死循环第一高发区）

| 现象 | 真相 | 正确写法 |
|---|---|---|
| `mkdir -p` 报参数错 | Windows 的 `mkdir` 是 `New-Item -ItemType Directory` 的包装，没有 `-p` | `New-Item -ItemType Directory -Force -Path <dir>` |
| `curl -o x -L <url>` 报参数错 | `curl` 是 `Invoke-WebRequest` 的别名 | 写 `curl.exe`（真 curl），或用 `Invoke-WebRequest -Uri <url> -OutFile x` |
| `&&` 语法错 | PowerShell 5.1 不支持 `&&` / `\|\|` | 用 `;`、拆两条命令；要 `&&` 就调 `pwsh -c "..."` |
| `grep/sed/head/find/which` 找不到 | 不是 Windows 自带命令 | §1 的三种写法 + `Get-ChildItem -Recurse` + `Get-Command` |
| `ls/cat/rm` 行为怪 | 都是 PS 别名，语义与 bash 不同 | 脚本里写全名 `Get-ChildItem` / `Get-Content` / `Remove-Item` |
| `$` 被吃掉 | 双引号里 `$xxx` 会被展开 | 传给外部程序的字面量用单引号，或 `` `$ `` 转义 |
| `.sh` 在 Git Bash / WSL 报 `bad interpreter: /bin/bash^M` | Git for Windows 默认 `core.autocrlf=true`，检出成 CRLF | 仓库加 `.gitattributes`（`*.sh text eol=lf`），或 `git config --global core.autocrlf input` |

## 5. 进程 / 端口 / 后台（桌面端特有，云沙箱没有）

- **端口占用**：`Get-NetTCPConnection -LocalPort 3000 -State Listen | Select-Object -Expand OwningProcess`，
  再看 `Get-Process -Id <pid>` 确认是**自己这次启动的**；是才 `Stop-Process -Id <pid> -Force`。杀别人的进程前必须问用户。
- **dev server 阻塞**：不要前台跑。后台起 + 日志落盘：
  `Start-Process -NoNewWindow -PassThru -RedirectStandardOutput dev.log -FilePath npm -ArgumentList 'run','dev'`
  再轮询 `dev.log` 的就绪关键字（`Local:` / `Ready in`）判定。**不要靠反复重启来"确认启动了"。**
- **残留进程**：收尾必须清理自己起的后台进程并报出 PID；没清就在回复里写明还留着哪个 PID。
- 端口验证（收口）：`Get-NetTCPConnection -LocalPort <port> -State Listen` 应为空。

## 6. 网络与镜像（中国网络环境）

| 症状 | 一次修好 |
|---|---|
| npm 装包超时/卡住 | `npm i --registry=https://registry.npmmirror.com`（或写进 `.npmrc`） |
| pip 超时 | `pip install -i https://pypi.tuna.tsinghua.edu.cn/simple <pkg>` |
| GitHub / raw 拉不动 | 同一 URL **最多 2 次**（直连 + 代理各一次）；第 3 次换镜像源（ghproxy 类服务 / gitee 镜像），并说明换了哪个源 |
| Electron / Playwright 二进制下载失败 | `$env:ELECTRON_MIRROR='https://npmmirror.com/mirrors/electron/'`；`$env:PLAYWRIGHT_DOWNLOAD_HOST='https://npmmirror.com/mirrors/playwright/'` |
| 不确定是不是网络问题 | 先判定一次：`Test-NetConnection github.com -Port 443`（或 `curl.exe -I --max-time 8 <url>`），再决定要不要代理；不要盲目堆 proxy 参数 |

## 7. 假成功（"已部署"幻觉）

- 改了源码但页面没变 → 先确认改的是**被真正加载的那份**（源码 vs `dist/`、`build/`、打包产物）；再确认 dev server 没报错；必要时重启**一次**并看日志。
- 浏览器缓存 / HMR 失效 → 硬刷新或换无缓存请求；不要连续重启服务"试试看"。
- "服务起来了"不算完成：至少要一条真实证据 —— `curl.exe -s -o - -w "%{http_code}" http://127.0.0.1:PORT/health`，或一次真实的查询/交互输出。
- "编译通过"不算完成：给出「输入 → 输出」或「点击 → 状态变化」的实测对。

## 8. 交互式命令挂死（无人值守杀手）

| 危险命令 | 安全写法 |
|---|---|
| `npm create` / `npm init` | `npm init -y`，或直接用模板参数 |
| `git commit`（无 `-m` 会开编辑器） | `git commit -m "..."` |
| `git rebase -i` | 不要用交互式 rebase；用 `git rebase --onto` / `git cherry-pick` 达到同样结果 |
| `ssh` 输密码 | `ssh -o BatchMode=yes`（失败即报错，不挂起），用密钥认证 |
| `npm login` / `gh auth login` 等要浏览器或密码的登录 | 交给用户手动做，并提供确切步骤 |
| 任何长时间无输出的命令 | 后台 + 日志落盘 + 轮询 + 超时后 `Stop-Process` |

判定标准：命令 60 秒无输出且无进度文件 → 视为卡死，终止并换非交互形态。

## 9. 多 agent / 并发写同一工作区

- 开工先看 `git status --porcelain`；有**非本次**的未提交改动 → 先 `git stash push -u -m "ai-work-doctor"` 或直接问用户，不要覆盖式继续。
- 改文件前后各取一次 `(Get-FileHash -LiteralPath $f).Hash`；哈希没变说明改错了文件或写到了别处。
- 多 agent（或用户开着编辑器）同时改同一文件：先提交/备份再改，改完**列出动过的文件清单**。

## 10. 预算与无人值守

- 用户说"我先走了/你自己跑"→ 先在回复里写死线：`预算：≤N 次工具调用 / ≤M 分钟`。
- 每 10 步或 10 分钟写 `CHECKPOINT: 改了什么 / 验证了什么 / 下一步`；到点必须输出 HANDOFF 并停。

## 11. 危险操作（桌面端直接操作用户真实文件）

- 删除/覆盖/移动前先备份并写出路径：
  `Copy-Item -LiteralPath $p -Destination "$p.bak-$(Get-Date -Format yyyyMMddHHmmss)"`（代码项目优先 `git stash`/`git commit`）。
- 未经用户明确确认，禁止：`git push --force`、`git reset --hard`、对非本次任务目录 `Remove-Item -Recurse -Force`、杀非本次启动的进程、改全局配置（包管理器源、PATH、环境变量、hosts、代理、注册表）。
- 必须改全局配置时：**先打印将执行的命令 → 等用户确认 → 执行 → 打印恢复命令**。
- 密钥 / token / 私钥写进文件、日志、示例代码都是事故；一律用占位符（`<TOKEN>`、`sk-xxx`）。
