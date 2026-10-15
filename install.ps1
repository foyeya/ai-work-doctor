#Requires -Version 5.1
<#
  ai工作医生（ai-work-doctor）一键激活 / 卸载 / 体检
  ---------------------------------------------------------------
  两种生效面：
    A. 全局（用户级）：把 SKILL.md 的「常驻卡」注入各 agent 的用户级全局指令文件，
       并把技能本体复制到用户级 skills 目录 —— 以后所有对话、所有项目自动生效。
    B. 项目级（-Project <目录>）：往项目里写各 IDE 型 agent 认的项目规则文件
       （AGENTS.md / CLAUDE.md / .cursor/rules / .trae/rules / .clinerules ...）。

  特性：幂等（重复运行不重复写入）、可预览（-DryRun）、可卸载（-Uninstall）、
        不覆盖用户已有内容、保留原文件编码、不写未证实的路径、无网络、无需管理员。

  用法：
    .\install.ps1 -List                     # 体检：认出本机装了哪些宿主（不动文件）
    .\install.ps1 -DryRun                   # 预览：将写哪些文件
    .\install.ps1                           # 激活全局（只处理检测到的宿主）
    .\install.ps1 -Uninstall                # 卸载全局（只删自己写的块）
    .\install.ps1 -Project D:\my-app        # 往项目里写项目级规则
    .\install.ps1 -Project D:\my-app -Uninstall
    .\install.ps1 -Select                   # 交互式：菜单里挑要装哪几个 agent（可多选/全选）
    .\install.ps1 -Select -Uninstall        # 交互式卸载
    .\install.ps1 -All                      # 含"未证实路径"的候选宿主（谨慎）
  可选：-Root <目录> 指定用户目录（默认 $HOME，测试用）
        -Only codex,trae 只处理指定宿主（非交互，等价于菜单里选它们）
#>
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Uninstall,
    [switch]$List,
    [switch]$All,
    [switch]$Select,
    [string[]]$Only,
    [string]$Root,
    [string[]]$Project
)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

$SkillId   = 'ai-work-doctor'
$MarkerTag = 'ai-work-doctor'
$BeginMark = "<!-- $MarkerTag`:start -->"
$EndMark   = "<!-- $MarkerTag`:end -->"

if (-not $Root) { $Root = $HOME }
$Root = [IO.Path]::GetFullPath($Root)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$SkillFile = Join-Path $ScriptDir 'SKILL.md'
$RefDir    = Join-Path $ScriptDir 'references'

# ================================================================ 数据区（改这里即可增减宿主）
#
# 1) 已证实路径（官方文档/源码可查）：只有当 HostDir 存在（=该 agent 装过）时才写；-All 强制。
$Hosts = @(
    [pscustomobject]@{ Id = 'codex';  Name = 'Codex CLI';      HostDir = '.codex';           InstrFile = 'AGENTS.md';                     SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'claude'; Name = 'Claude Code';    HostDir = '.claude';          InstrFile = 'CLAUDE.md';                     SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'dsh';    Name = 'DSH / CC GUI';   HostDir = '.dsh';             InstrFile = 'AGENTS.md';                     SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'agents'; Name = '通用 SKILL.md';   HostDir = '.agents';          InstrFile = $null;                           SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'gemini'; Name = 'Gemini CLI';     HostDir = '.gemini';          InstrFile = 'GEMINI.md';                     SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'qwen';   Name = 'Qwen Code';      HostDir = '.qwen';            InstrFile = 'QWEN.md';                       SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'trae';   Name = 'Trae（字节）';     HostDir = '.trae';            InstrFile = 'user_rules\ai-work-doctor.md';  SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'traecn'; Name = 'Trae CN（字节）';  HostDir = '.trae-cn';         InstrFile = 'user_rules\ai-work-doctor.md';  SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'traecli';Name = 'Trae CLI（字节）'; HostDir = '.traecli';         InstrFile = $null;                           SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'codebuddy'; Name = 'CodeBuddy（腾讯）'; HostDir = '.codebuddy';    InstrFile = 'CODEBUDDY.md';                  SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'comate'; Name = '文心快码（百度）'; HostDir = '.comate';           InstrFile = $null;                           SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'qoder';  Name = 'Qoder CLI（阿里）'; HostDir = '.qoder';          InstrFile = 'AGENTS.md';                     SkillsRel = $null }
    [pscustomobject]@{ Id = 'qodercn';Name = 'Qoder CN CLI（阿里）'; HostDir = '.qoder-cn';     InstrFile = 'AGENTS.md';                     SkillsRel = $null }
    [pscustomobject]@{ Id = 'lingma'; Name = 'Qoder CN IDE（原通义灵码）'; HostDir = '.lingma'; InstrFile = $null;                           SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'iflow';  Name = 'iFlow CLI（已停服）'; HostDir = '.iflow';          InstrFile = 'IFLOW.md';                      SkillsRel = $null }
    [pscustomobject]@{ Id = 'roo';    Name = 'Roo Code';       HostDir = '.roo';             InstrFile = 'rules\ai-work-doctor.md';       SkillsRel = $null }
    [pscustomobject]@{ Id = 'cline';  Name = 'Cline';          HostDir = '@DOCUMENTS\Cline'; InstrFile = 'Rules\ai-work-doctor.md';       SkillsRel = $null }
    [pscustomobject]@{ Id = 'kimi';   Name = 'Kimi Code CLI';  HostDir = '.kimi';            InstrFile = $null;                           SkillsRel = 'skills' }
    [pscustomobject]@{ Id = 'zed';    Name = 'Zed';            HostDir = '.config\zed';      InstrFile = 'AGENTS.md';                     SkillsRel = $null }
    [pscustomobject]@{ Id = 'zedwin'; Name = 'Zed（Windows）';  HostDir = '@APPDATA\Zed';     InstrFile = 'AGENTS.md';                     SkillsRel = $null }
    [pscustomobject]@{ Id = 'copilot';Name = 'Copilot（用户级）'; HostDir = '.copilot';       InstrFile = 'copilot-instructions.md';       SkillsRel = $null }
)
#
# 2) 候选宿主（路径未获官方证实）：只在"该目录已存在，且它自己的 rules 子目录也存在"时才写
#    （不创建陌生目录），动作标注"嗅探"。v2.1 起这张表是空的 —— 所有已支持宿主都有官方文档依据；
#    将来遇到"路径没法证实但用户又想试"的宿主，往这里加一行即可（CONTRIBUTING 有说明）。
$ProbeHosts = @()
#
# 3) 项目级注入点（-Project 用）：Verified=$false 的只在 -All 下写。
$TraeFront   = "---`r`ndescription: ai工作医生（桌面端 agent 熔断纪律）`r`nalwaysApply: true`r`n---"
$CbFront     = "---`r`ndescription: ai工作医生（桌面端 agent 熔断纪律）`r`nalwaysApply: true`r`nenabled: true`r`n---"
$QoderFront  = "---`r`ndescription: ai工作医生（桌面端 agent 熔断纪律）`r`ntrigger: always_on`r`nalwaysApply: true`r`n---"
$CpFront     = "---`r`napplyTo: ""**""`r`n---"
$ProjectTargets = @(
    [pscustomobject]@{ File = 'AGENTS.md';                               Name = 'AGENTS.md 通用约定'; Verified = $true;  Front = $null }
    [pscustomobject]@{ File = 'CLAUDE.md';                               Name = 'Claude Code';        Verified = $true;  Front = $null }
    [pscustomobject]@{ File = 'GEMINI.md';                               Name = 'Gemini CLI';         Verified = $true;  Front = $null }
    [pscustomobject]@{ File = 'QWEN.md';                                 Name = 'Qwen Code';          Verified = $true;  Front = $null }
    [pscustomobject]@{ File = 'CODEBUDDY.md';                            Name = 'CodeBuddy CLI';      Verified = $true;  Front = $null }
    [pscustomobject]@{ File = 'IFLOW.md';                                Name = 'iFlow CLI（已停服）'; Verified = $true;  Front = $null }
    [pscustomobject]@{ File = 'CONVENTIONS.md';                          Name = 'Aider';              Verified = $true;  Front = $null }
    [pscustomobject]@{ File = '.trae\rules\ai-work-doctor.md';            Name = 'Trae';               Verified = $true;  Front = $TraeFront }
    [pscustomobject]@{ File = '.codebuddy\rules\ai-work-doctor\RULE.mdc'; Name = 'CodeBuddy IDE';      Verified = $true;  Front = $CbFront }
    [pscustomobject]@{ File = '.comate\rules\ai-work-doctor.mdr';         Name = '文心快码 Comate';     Verified = $true;  Front = $null }
    [pscustomobject]@{ File = '.lingma\rules\ai-work-doctor.md';          Name = 'Qoder CN IDE';       Verified = $true;  Front = $QoderFront }
    [pscustomobject]@{ File = '.qoder\rules\ai-work-doctor.md';           Name = 'Qoder IDE/CLI';      Verified = $true;  Front = $QoderFront }
    [pscustomobject]@{ File = '.clinerules\ai-work-doctor.md';            Name = 'Cline';              Verified = $true;  Front = $null }
    [pscustomobject]@{ File = '.roo\rules\ai-work-doctor.md';             Name = 'Roo Code';           Verified = $true;  Front = $null }
    [pscustomobject]@{ File = '.continue\rules\ai-work-doctor.md';        Name = 'Continue';           Verified = $true;  Front = $null }
    [pscustomobject]@{ File = '.github\copilot-instructions.md';          Name = 'GitHub Copilot';     Verified = $true;  Front = $null }
    [pscustomobject]@{ File = '.github\instructions\ai-work-doctor.instructions.md'; Name = 'Copilot 指令文件'; Verified = $true; Front = $CpFront }
    [pscustomobject]@{ File = '.cursor\rules\ai-work-doctor.mdc';         Name = 'Cursor 项目规则';     Verified = $true;  Front = $TraeFront }
)

# ================================================================ 工具函数
function Get-DocumentsDir {
    # 显式给了 -Root（含测试场景）就在该根下取，避免写到真实用户目录
    if ($Root -and ($Root.TrimEnd('\') -ne $HOME.TrimEnd('\'))) { return (Join-Path $Root 'Documents') }
    try {
        $reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $v = (Get-ItemProperty -Path $reg -Name 'Personal' -ErrorAction Stop).Personal
        if ($v) { return [Environment]::ExpandEnvironmentVariables($v) }
    } catch { }
    return (Join-Path $HOME 'Documents')
}
function Get-AppDataDir {
    # Windows 的 %APPDATA%（Zed 等把用户级规则放这里）；-Root 覆盖时保持在沙箱内
    if ($Root -and ($Root.TrimEnd('\') -ne $HOME.TrimEnd('\'))) { return (Join-Path $Root 'AppData\Roaming') }
    $v = [Environment]::GetFolderPath('ApplicationData')
    if ($v) { return $v }
    return (Join-Path $HOME 'AppData\Roaming')
}
function Resolve-HostPath {
    param([string]$Rel)
    if ($Rel -like '@DOCUMENTS*') {
        $rest = $Rel.Substring('@DOCUMENTS'.Length).TrimStart('\')
        if ($rest) { return (Join-Path (Get-DocumentsDir) $rest) }
        return (Get-DocumentsDir)
    }
    if ($Rel -like '@APPDATA*') {
        $rest = $Rel.Substring('@APPDATA'.Length).TrimStart('\')
        if ($rest) { return (Join-Path (Get-AppDataDir) $rest) }
        return (Get-AppDataDir)
    }
    return (Join-Path $Root $Rel)
}
function Read-TextFile {
    param([string]$Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @{ Text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3); Enc = (New-Object Text.UTF8Encoding($true)); Name = 'UTF-8 BOM' }
    }
    try {
        $strict = New-Object Text.UTF8Encoding($false, $true)
        return @{ Text = $strict.GetString($bytes); Enc = (New-Object Text.UTF8Encoding($false)); Name = 'UTF-8' }
    } catch {
        # 老文件是 GBK/936：按原编码读写，不"顺手统一"
        $gbk = [Text.Encoding]::GetEncoding(936)
        return @{ Text = $gbk.GetString($bytes); Enc = $gbk; Name = 'GBK(936)' }
    }
}
function Write-TextFile {
    param([string]$Path, [string]$Text, $Enc, [string]$Front)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if ($Front) { $Text = $Front + "`r`n`r`n" + $Text }
    [IO.File]::WriteAllText($Path, $Text, $Enc)
}
function Remove-MarkerBlock {
    param([string]$Text)
    $pattern = "(?s)\r?\n?$([regex]::Escape($BeginMark)).*?$([regex]::Escape($EndMark))[ \t]*\r?\n?"
    return [regex]::Replace($Text, $pattern, "`r`n")
}
function Test-OnlyOurs {
    param([string]$Text)
    $t = Remove-MarkerBlock -Text $Text
    $t = [regex]::Replace($t, "(?s)^\s*---\s*\r?\n.*?\r?\n---\s*\r?\n?", '')
    $t = [regex]::Replace($t, "^\s*#\s*全局指令（用户级）\s*\r?\n?", '')
    return [string]::IsNullOrWhiteSpace($t)
}

# ================================================================ 常驻卡
if (-not (Test-Path -LiteralPath $SkillFile)) { throw "找不到 SKILL.md：$SkillFile（请把本脚本和 SKILL.md 放在同一目录）" }
$skillRaw = (Read-TextFile -Path $SkillFile).Text
$m = [regex]::Match($skillRaw, '(?s)<!--\s*AIW_CORE:START\s*-->(.*?)<!--\s*AIW_CORE:END\s*-->')
if (-not $m.Success) { throw "SKILL.md 里找不到 AIW_CORE 标记块，无法生成常驻卡（文件被改坏？）" }
$core = $m.Groups[1].Value.Trim()

function New-Block {
    param([string]$NoteLine)
    return (@($BeginMark, $core, "", $NoteLine, $EndMark) -join "`r`n")
}

$results = New-Object System.Collections.ArrayList
function Add-Result($host_, $action, $target, $note) {
    [void]$results.Add([pscustomobject]@{ Host = $host_; Action = $action; Target = $target; Note = $note })
}

# ---------------------------------------------------------------- 注入一个文件（幂等 + 可卸载）
function Invoke-Inject {
    param(
        [string]$Name,
        [string]$Path,
        [string]$NoteLine,
        [string]$HeaderIfNew = "# 全局指令（用户级）",
        [string]$Front = $null,
        [switch]$NoCreate      # 嗅探模式：文件不存在就只报告，不创建
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        if ($NoCreate) { Add-Result $Name '跳过' $Path '目标文件不存在（未证实路径，不创建）'; return }
        if ($Uninstall) { Add-Result $Name '无需处理' $Path '文件不存在'; return }
        if ($DryRun) { Add-Result $Name '将新建' $Path '' ; return }
        $body = (New-Block $NoteLine) + "`r`n"
        if ($HeaderIfNew) { $body = $HeaderIfNew + "`r`n`r`n" + $body }
        Write-TextFile -Path $Path -Text $body -Enc (New-Object Text.UTF8Encoding($false)) -Front $Front
        Add-Result $Name '已新建' $Path 'UTF-8'
        return
    }
    $f = Read-TextFile -Path $Path
    if ($Uninstall) {
        if ($f.Text -notlike "*$BeginMark*") { Add-Result $Name '无需处理' $Path '没找到本技能的标记块'; return }
        if ($DryRun) { Add-Result $Name '将删除标记块' $Path $f.Name; return }
        if (Test-OnlyOurs -Text $f.Text) {
            Remove-Item -LiteralPath $Path -Force
            Add-Result $Name '删除空文件' $Path '内容只有本技能的块'
        } else {
            $new = Remove-MarkerBlock -Text $f.Text
            Write-TextFile -Path $Path -Text ($new.TrimEnd() + "`r`n") -Enc $f.Enc
            Add-Result $Name '已删除标记块' $Path $f.Name
        }
        return
    }
    $block = New-Block $NoteLine
    $existing = [regex]::Match($f.Text, "(?s)$([regex]::Escape($BeginMark)).*?$([regex]::Escape($EndMark))")
    if ($existing.Success -and $existing.Value.Trim() -eq $block.Trim()) { Add-Result $Name '已是最新' $Path $f.Name; return }
    $base = Remove-MarkerBlock -Text $f.Text
    $newText = $base.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
    if ($DryRun) {
        Add-Result $Name '将写入' $Path ("{0}，{1} → {2} 字符" -f $f.Name, $f.Text.Length, $newText.Length)
    } else {
        Write-TextFile -Path $Path -Text $newText -Enc $f.Enc
        Add-Result $Name '已写入' $Path $f.Name
    }
}

# ---------------------------------------------------------------- 复制技能本体
function Invoke-CopySkill {
    param([string]$Name, [string]$SkillDir)
    if (-not $SkillDir) { return }
    $dest = Join-Path $SkillDir $SkillId
    $destFile = Join-Path $dest 'SKILL.md'
    if ($Uninstall) {
        if (Test-Path -LiteralPath $dest) {
            if ($DryRun) { Add-Result $Name '将删除技能目录' $dest '' }
            else { Remove-Item -LiteralPath $dest -Recurse -Force; Add-Result $Name '已删除技能目录' $dest '' }
        } else { Add-Result $Name '无需处理' $dest '技能目录不存在' }
        return
    }
    $same = (Test-Path -LiteralPath $destFile) -and ((Get-FileHash -LiteralPath $destFile).Hash -eq (Get-FileHash -LiteralPath $SkillFile).Hash)
    if ($same) { Add-Result $Name '技能已最新' $dest ''; return }
    if ($DryRun) { Add-Result $Name '将复制技能' $dest 'SKILL.md + references/'; return }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Copy-Item -LiteralPath $SkillFile -Destination $destFile -Force
    if (Test-Path -LiteralPath $RefDir) {
        $destRef = Join-Path $dest 'references'
        if (-not (Test-Path -LiteralPath $destRef)) { New-Item -ItemType Directory -Force -Path $destRef | Out-Null }
        Copy-Item -Path (Join-Path $RefDir '*') -Destination $destRef -Recurse -Force
    }
    Add-Result $Name '已复制技能' $dest 'SKILL.md + references/'
}

# ---------------------------------------------------------------- 选择宿主（菜单 / -Only）
function Normalize-Id { param([string]$Id) return ($Id -replace '[-_\s]', '').ToLower() }
function Resolve-HostChoice {
    param([string]$Text)
    $n = Normalize-Id $Text
    if (-not $n) { return $null }
    foreach ($h in $Hosts) { if ((Normalize-Id $h.Id) -eq $n) { return $h } }
    foreach ($h in $Hosts) { if ((Normalize-Id $h.Name) -eq $n) { return $h } }
    foreach ($h in $Hosts) { if ((Normalize-Id $h.Name) -like "$n*") { return $h } }
    return $null
}
function Select-HostsInteractive {
    $rows = New-Object System.Collections.ArrayList
    $i = 0
    foreach ($h in $Hosts) {
        $i++
        $hostPath = Resolve-HostPath $h.HostDir
        $what = ''
        if ($h.InstrFile) { $what = (Join-Path $hostPath $h.InstrFile) }
        if ($h.SkillsRel) {
            $sd = Join-Path $hostPath (Join-Path $h.SkillsRel $SkillId)
            if ($what) { $what = "$what  +  $sd" } else { $what = $sd }
        }
        [void]$rows.Add([pscustomobject]@{ N = $i; Id = $h.Id; Name = $h.Name; Detected = (Test-Path -LiteralPath $hostPath); What = $what })
    }
    Write-Host "本机可处理的宿主（按编号选，可多选）：" -ForegroundColor Cyan
    Write-Host ("{0,3}  {1,-26} {2,-10} {3}" -f '#', '宿主', '状态', '将写入') -ForegroundColor DarkGray
    foreach ($r in $rows) {
        if ($r.Detected) { $color = 'Green' } else { $color = 'DarkGray' }
        Write-Host ("{0,3}  {1,-26} {2,-10} {3}" -f $r.N, $r.Name, $(if ($r.Detected) { '已检测到' } else { '未检测到' }), $r.What) -ForegroundColor $color
    }
    Write-Host ""
    Write-Host "输入编号（如 1,3,5 或 2-4），all=全部（含未检测到的，会新建目录），detected=只处理已检测到的，q=退出；回车=detected" -ForegroundColor DarkGray
    $ans = ''
    try { $ans = (Read-Host "选择").Trim().ToLower() } catch { $ans = '' }
    if ($ans -eq 'q' -or $ans -eq 'quit') { return $null }
    if ($ans -eq '' -or $ans -eq 'd' -or $ans -eq 'detected') { return @($rows | Where-Object { $_.Detected } | ForEach-Object { $_.Id }) }
    if ($ans -eq 'a' -or $ans -eq 'all') { return @($rows | ForEach-Object { $_.Id }) }
    $picked = New-Object System.Collections.ArrayList
    foreach ($part in ($ans -split '[,，、\s]+')) {
        if (-not $part) { continue }
        if ($part -match '^(\d+)\s*-\s*(\d+)$') {
            $from = [int]$Matches[1]; $to = [int]$Matches[2]
            for ($k = $from; $k -le $to; $k++) { if ($k -ge 1 -and $k -le $rows.Count) { [void]$picked.Add($rows[$k - 1].Id) } }
        } elseif ($part -match '^\d+$') {
            $k = [int]$part
            if ($k -ge 1 -and $k -le $rows.Count) { [void]$picked.Add($rows[$k - 1].Id) }
            else { Write-Host "忽略无效编号：$k" -ForegroundColor Yellow }
        } else {
            $h = Resolve-HostChoice $part
            if ($h) { [void]$picked.Add($h.Id) } else { Write-Host "忽略无法识别的宿主：$part" -ForegroundColor Yellow }
        }
    }
    return @($picked | Select-Object -Unique)
}

# ================================================================ 主流程
$isProjectMode = ($Project -and $Project.Count -gt 0)
Write-Host ""
Write-Host "ai工作医生 / $SkillId  ·  $(if ($isProjectMode) { '项目级注入' } else { "用户目录：$Root" })" -ForegroundColor Cyan
Write-Host "模式：$(if ($Uninstall) {'卸载'} elseif ($DryRun) {'预览(-DryRun)'} elseif ($List) {'体检(-List)'} else {'激活'})"
Write-Host ""

$explicitPick = $false
if ($Select -and $isProjectMode) { Write-Host "-Select 只用于全局模式，本次已忽略（项目级按 -Project 处理）。" -ForegroundColor Yellow }
if ($Select -and -not $isProjectMode) {
    $picked = Select-HostsInteractive
    if ($null -eq $picked) { Write-Host "已取消，未改动任何文件。" -ForegroundColor Cyan; exit 0 }
    if (@($picked).Count -eq 0) { Write-Host "没有选到任何宿主，未改动任何文件。" -ForegroundColor Cyan; exit 0 }
    $Only = @($picked)
    $explicitPick = $true
    $verb = '激活'
    if ($Uninstall) { $verb = '卸载' }
    Write-Host ""
    Write-Host ("将对 {0} 个宿主执行「{1}」：{2}" -f @($picked).Count, $verb, (@($picked) -join ', ')) -ForegroundColor Cyan
    if (-not $DryRun -and -not $List) {
        $ok = ''
        try { $ok = (Read-Host "确认执行？[Y/n]").Trim().ToLower() } catch { $ok = 'y' }
        if ($ok -ne '' -and $ok -ne 'y' -and $ok -ne 'yes' -and $ok -ne '是') { Write-Host "已取消，未改动任何文件。" -ForegroundColor Cyan; exit 0 }
    }
    Write-Host ""
}
if ($Only -and @($Only).Count -gt 0) {
    $norm = New-Object System.Collections.ArrayList
    foreach ($o in $Only) {
        $h = Resolve-HostChoice $o
        if ($h) { [void]$norm.Add($h.Id) } else { Write-Host "警告：认不出宿主「$o」，已忽略（用 -List 看可用 id）。" -ForegroundColor Yellow }
    }
    $Only = @($norm | Select-Object -Unique)
    if (@($Only).Count -gt 0) { $explicitPick = $true }   # 明确指定 = 明确意图：没检测到也按 -All 处理
}

if ($isProjectMode) {
    # ---------------------------------------------------------- B. 项目级
    foreach ($proj in $Project) {
        $projPath = [IO.Path]::GetFullPath($proj)
        if (-not (Test-Path -LiteralPath $projPath)) { Add-Result $proj '跳过' $projPath '目录不存在'; continue }
        Write-Host "项目：$projPath" -ForegroundColor DarkGray
        foreach ($t in $ProjectTargets) {
            if (-not $t.Verified -and -not $All) {
                Add-Result $t.Name '跳过' (Join-Path $projPath $t.File) '未证实路径（要用加 -All）'
                continue
            }
            $p = Join-Path $projPath $t.File
            $note = "> 本块由 ai工作医生安装脚本写入（项目级）。卸载：install.ps1 -Project <项目> -Uninstall"
            Invoke-Inject -Name $t.Name -Path $p -NoteLine $note -HeaderIfNew '' -Front $t.Front
        }
    }
} else {
    # ---------------------------------------------------------- A. 全局（用户级）
    foreach ($h in $Hosts) {
        if ($Only -and ($Only -notcontains $h.Id)) { continue }
        $hostPath = Resolve-HostPath $h.HostDir
        if (-not (Test-Path -LiteralPath $hostPath) -and -not $All -and -not $explicitPick) {
            Add-Result $h.Name '跳过' $h.HostDir '未检测到该宿主（装了再用 -All 强制）'
            continue
        }
        if ($List) { Add-Result $h.Name '检测到' $h.HostDir ''; continue }
        if ($h.InstrFile) {
            $skillDir = $null
            if ($h.SkillsRel) { $skillDir = Join-Path $hostPath $h.SkillsRel }
            $note = "> 本块由 ai工作医生安装脚本写入（技能目录：$skillDir）。卸载：install.ps1 -Uninstall"
            Invoke-Inject -Name $h.Name -Path (Join-Path $hostPath $h.InstrFile) -NoteLine $note
        }
        if ($h.SkillsRel) { Invoke-CopySkill -Name $h.Name -SkillDir (Join-Path $hostPath $h.SkillsRel) }
    }

    # ---- 国产 IDE 型 agent：只在该目录 + 它自己的 rules 子目录都已存在时才写（不猜、不建陌生目录）
    foreach ($p in $ProbeHosts) {
        if ($Only -and ($Only -notcontains $p.Id)) { continue }
        $dir = Join-Path $Root $p.Dir
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $rulesDir = Join-Path $dir $p.RuleSub
        if (-not (Test-Path -LiteralPath $rulesDir)) {
            Add-Result $p.Name '未激活' $dir "检测到 $($p.Dir) 但没有 $($p.RuleSub)\ 子目录 → 路径未知，请把 README 里那段粘进它的「用户规则」设置"
            continue
        }
        if ($List) { Add-Result $p.Name '检测到' $rulesDir "$($p.RuleSub)\ 已存在（路径未官方证实）"; continue }
        $note = "> 本块由 ai工作医生安装脚本写入（路径未官方证实，嗅探命中）。卸载：install.ps1 -Uninstall"
        Invoke-Inject -Name $p.Name -Path (Join-Path $rulesDir 'ai-work-doctor.md') -NoteLine $note -HeaderIfNew ''
    }
}

# ---------------------------------------------------------------- 汇总
Write-Host ("{0,-16} {1,-16} {2}" -f '宿主/目标', '动作', '位置') -ForegroundColor DarkGray
Write-Host ('-' * 86) -ForegroundColor DarkGray
foreach ($r in $results) {
    $color = 'Gray'
    if ($r.Action -like '*已写入*' -or $r.Action -like '*已新建*' -or $r.Action -like '*已复制*') { $color = 'Green' }
    elseif ($r.Action -like '*将*') { $color = 'Yellow' }
    elseif ($r.Action -like '*未激活*') { $color = 'Magenta' }
    elseif ($r.Action -like '*跳过*' -or $r.Action -like '*无需*') { $color = 'DarkGray' }
    Write-Host ("{0,-16} {1,-16} {2}" -f $r.Host, $r.Action, $r.Target) -ForegroundColor $color
    if ($r.Note) { Write-Host ("{0,-16} {1,-16} {2}" -f '', '', $r.Note) -ForegroundColor DarkGray }
}
Write-Host ""

if ($List) {
    Write-Host "体检完成。要真激活：去掉 -List；要先预览：加 -DryRun。" -ForegroundColor Cyan
} elseif ($Uninstall) {
    Write-Host "卸载完成：只删了本技能写入的标记块与技能目录，你自己的内容没动。" -ForegroundColor Cyan
} elseif ($DryRun) {
    Write-Host "以上是预览，没有写入任何文件。要真激活：去掉 -DryRun。" -ForegroundColor Cyan
} else {
    Write-Host "激活完成。" -ForegroundColor Cyan
    Write-Host "验证生效：新开一个对话，让 agent 复述预算上限（read 2 / search 2 / deploy 2 / no-op 2 / tool-err 3）。" -ForegroundColor Cyan
    Write-Host "UI 里配规则的宿主（Cursor / Trae / 灵码 / Comate / CodeBuddy…）：把 README「手动兜底」那段粘进它的用户规则设置。" -ForegroundColor DarkGray
    Write-Host "卸载：install.ps1 -Uninstall（项目级用 -Project <目录> -Uninstall）" -ForegroundColor DarkGray
}

$failed = @($results | Where-Object { $_.Action -like '*失败*' })
if ($failed.Count -gt 0) { Write-Host "有 $($failed.Count) 项失败，见上表。" -ForegroundColor Red; exit 1 }
exit 0
