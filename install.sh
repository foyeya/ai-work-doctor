#!/usr/bin/env bash
# ai工作医生（ai-work-doctor）一键激活 / 卸载 / 体检 —— macOS / Linux / Git Bash
# ================================================================
# 两种生效面：
#   A. 全局（用户级）：把 SKILL.md 的「常驻卡」注入各 agent 的用户级全局指令文件，
#      并把技能本体复制到用户级 skills 目录 —— 以后所有对话、所有项目自动生效。
#   B. 项目级（--project <目录>）：往项目里写各 IDE 型 agent 认的项目规则文件。
#
# 用法：
#   ./install.sh -l                      # 体检（不动文件）
#   ./install.sh -n                      # 预览
#   ./install.sh                         # 激活全局
#   ./install.sh -u                      # 卸载全局
#   ./install.sh -p ~/my-app             # 项目级注入（可多次 -p）
#   ./install.sh -p ~/my-app -u          # 项目级卸载
#   ./install.sh -a                      # 含未证实路径的候选宿主（谨慎）
#   ./install.sh --root DIR --only codex # 指定用户目录 / 只处理某宿主（测试用）
set -euo pipefail

SKILL_ID="ai-work-doctor"
MARK="ai-work-doctor"
BEGIN_MARK="<!-- ${MARK}:start -->"
END_MARK="<!-- ${MARK}:end -->"
HEADER_NEW="# 全局指令（用户级）"

ROOT="${HOME}"
DRY=0; UNINSTALL=0; LIST=0; ALLHOSTS=0; ONLY=""; SELECT=0; EXPLICIT=0
PROJECTS=()
SELECTED=""

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--dry-run) DRY=1 ;;
    -u|--uninstall) UNINSTALL=1 ;;
    -l|--list) LIST=1 ;;
    -a|--all) ALLHOSTS=1 ;;
    -i|--select) SELECT=1 ;;
    -p|--project) PROJECTS+=("$2"); shift ;;
    --root) ROOT="$2"; shift ;;
    --only) ONLY="$2"; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "未知参数：$1（-h 看用法）" >&2; exit 2 ;;
  esac
  shift
done

# --only 明确指定 = 明确意图：没检测到也按 -a 处理（只对该宿主）
if [ -n "$ONLY" ]; then EXPLICIT=1; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_FILE="$SCRIPT_DIR/SKILL.md"
REF_DIR="$SCRIPT_DIR/references"

[ -f "$SKILL_FILE" ] || { echo "找不到 SKILL.md：$SKILL_FILE（脚本要和 SKILL.md 放同一目录）" >&2; exit 1; }

CORE="$(awk '/<!--[[:space:]]*AIW_CORE:START[[:space:]]*-->/{f=1;next} /<!--[[:space:]]*AIW_CORE:END[[:space:]]*-->/{f=0} f' "$SKILL_FILE")"
[ -n "$CORE" ] || { echo "SKILL.md 里找不到 AIW_CORE 标记块，无法生成常驻卡" >&2; exit 1; }

# ================================================================ 数据区
# 1) 已证实路径（官方文档/源码可查）：宿主目录存在才写
HOSTS=(
  "codex|Codex CLI|.codex|AGENTS.md|skills"
  "claude|Claude Code|.claude|CLAUDE.md|skills"
  "dsh|DSH / CC GUI|.dsh|AGENTS.md|skills"
  "agents|通用 SKILL.md|.agents||skills"
  "gemini|Gemini CLI|.gemini|GEMINI.md|skills"
  "qwen|Qwen Code|.qwen|QWEN.md|skills"
  "trae|Trae（字节）|.trae|user_rules/ai-work-doctor.md|skills"
  "traecn|Trae CN（字节）|.trae-cn|user_rules/ai-work-doctor.md|skills"
  "traecli|Trae CLI（字节）|.traecli||skills"
  "codebuddy|CodeBuddy（腾讯）|.codebuddy|CODEBUDDY.md|skills"
  "comate|文心快码（百度）|.comate||skills"
  "roo|Roo Code|.roo|rules/ai-work-doctor.md|"
  "cline|Cline|Documents/Cline|Rules/ai-work-doctor.md|"
  "qoder|Qoder CLI（阿里）|.qoder|AGENTS.md|"
  "qodercn|Qoder CN CLI（阿里）|.qoder-cn|AGENTS.md|"
  "lingma|Qoder CN IDE（原通义灵码）|.lingma||skills"
  "iflow|iFlow CLI（已停服）|.iflow|IFLOW.md|"
  "kimi|Kimi Code CLI|.kimi||skills"
  "zed|Zed|.config/zed|AGENTS.md|"
  "copilot|Copilot（用户级）|.copilot|copilot-instructions.md|"
)
# 2) 候选宿主（路径未获官方证实）：只有"该目录 + 它自己的 rules 子目录"都存在才写。
#    v2.1 起这张表为空 —— 已支持宿主都有官方文档依据；将来要试"查不到路径"的宿主，在这里加一行。
PROBES=()
# 3) 项目级注入点（--project）：v=1 为已证实；v=0 只在 -a 下写
TRAE_FRONT='---\ndescription: ai工作医生（桌面端 agent 熔断纪律）\nalwaysApply: true\n---'
CB_FRONT='---\ndescription: ai工作医生（桌面端 agent 熔断纪律）\nalwaysApply: true\nenabled: true\n---'
QODER_FRONT='---\ndescription: ai工作医生（桌面端 agent 熔断纪律）\ntrigger: always_on\nalwaysApply: true\n---'
CP_FRONT='---\napplyTo: "**"\n---'
PROJECT_TARGETS=(
  "AGENTS.md|AGENTS.md 通用约定|1|"
  "CLAUDE.md|Claude Code|1|"
  "GEMINI.md|Gemini CLI|1|"
  "QWEN.md|Qwen Code|1|"
  "CODEBUDDY.md|CodeBuddy CLI|1|"
  "IFLOW.md|iFlow CLI（已停服）|1|"
  "CONVENTIONS.md|Aider|1|"
  ".trae/rules/ai-work-doctor.md|Trae|1|$TRAE_FRONT"
  ".codebuddy/rules/ai-work-doctor/RULE.mdc|CodeBuddy IDE|1|$CB_FRONT"
  ".comate/rules/ai-work-doctor.mdr|文心快码 Comate|1|"
  ".lingma/rules/ai-work-doctor.md|Qoder CN IDE|1|$QODER_FRONT"
  ".qoder/rules/ai-work-doctor.md|Qoder IDE/CLI|1|$QODER_FRONT"
  ".clinerules/ai-work-doctor.md|Cline|1|"
  ".roo/rules/ai-work-doctor.md|Roo Code|1|"
  ".continue/rules/ai-work-doctor.md|Continue|1|"
  ".github/copilot-instructions.md|GitHub Copilot|1|"
  ".github/instructions/ai-work-doctor.instructions.md|Copilot 指令文件|1|$CP_FRONT"
  ".cursor/rules/ai-work-doctor.mdc|Cursor 项目规则|1|$TRAE_FRONT"
)

# ================================================================ 工具
strip_block() {
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    index($0,b) { skip=1; next }
    index($0,e) { skip=0; next }
    !skip { print }
  '
}
trim_trailing_blank() { awk '{l[NR]=$0} NF{last=NR} END{for(i=1;i<=last;i++) print l[i]}'; }
# 去掉标记块 / .mdc frontmatter / 自动加的标题行后，还剩不剩用户内容（空=文件是我们建的）
residual_is_empty() {
  local out
  out=$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    NR==1 && $0 ~ /^---[[:space:]]*$/ { fm=1; next }
    fm==1 { if ($0 ~ /^---[[:space:]]*$/) fm=0; next }
    index($0,b) { skip=1; next }
    index($0,e) { skip=0; next }
    skip { next }
    $0 ~ /^# 全局指令（用户级）[[:space:]]*$/ { next }
    { print }
  ' "$1" | tr -d '[:space:]')
  [ -z "$out" ]
}
tmpfile() { mktemp "${TMPDIR:-/tmp}/aiw.XXXXXX"; }

inject_file() { # name path note header front
  local name="$1" path="$2" note="$3" header="${4-}" front="${5-}"
  local block existing tmp
  block="$(printf '%s\n%s\n\n%s\n%s' "$BEGIN_MARK" "$CORE" "$note" "$END_MARK")"

  if [ ! -f "$path" ]; then
    if [ "$UNINSTALL" = 1 ]; then printf '  %-14s 无需处理（文件不存在）\n' "$name"; return 0; fi
    if [ "$DRY" = 1 ]; then printf '  %-14s [dry] 将新建 %s\n' "$name" "$path"; return 0; fi
    mkdir -p "$(dirname "$path")"
    {
      [ -n "$front" ] && printf '%s\n\n' "$front"
      [ -n "$header" ] && printf '%s\n\n' "$header"
      printf '%s\n' "$block"
    } > "$path"
    printf '  %-14s 已新建 %s\n' "$name" "$path"
    return 0
  fi

  if [ "$UNINSTALL" = 1 ]; then
    if ! grep -qF "$BEGIN_MARK" "$path"; then printf '  %-14s 无需处理 %s\n' "$name" "$path"; return 0; fi
    if [ "$DRY" = 1 ]; then printf '  %-14s [dry] 将删除标记块 %s\n' "$name" "$path"; return 0; fi
    if residual_is_empty "$path"; then
      rm -f "$path"; printf '  %-14s 删除空文件 %s\n' "$name" "$path"
    else
      tmp="$(tmpfile)"; strip_block < "$path" | trim_trailing_blank > "$tmp"; cat "$tmp" > "$path"; rm -f "$tmp"
      printf '  %-14s 已删除标记块 %s\n' "$name" "$path"
    fi
    return 0
  fi

  existing="$(awk -v b="$BEGIN_MARK" -v e="$END_MARK" 'index($0,b){f=1} f{print} index($0,e){f=0}' "$path")"
  if [ "$existing" = "$block" ]; then printf '  %-14s 已是最新 %s\n' "$name" "$path"; return 0; fi
  if [ "$DRY" = 1 ]; then printf '  %-14s [dry] 将写入 %s\n' "$name" "$path"; return 0; fi
  tmp="$(tmpfile)"; strip_block < "$path" | trim_trailing_blank > "$tmp"
  { cat "$tmp"; printf '\n%s\n' "$block"; } > "$path"
  rm -f "$tmp"
  printf '  %-14s 已写入 %s\n' "$name" "$path"
}

copy_skill() { # name skillsDir
  local name="$1" dir="$2" dest
  [ -n "$dir" ] || return 0
  dest="$dir/$SKILL_ID"
  if [ "$UNINSTALL" = 1 ]; then
    if [ -d "$dest" ]; then
      if [ "$DRY" = 1 ]; then printf '  %-14s [dry] 将删除技能目录 %s\n' "$name" "$dest"
      else rm -rf "$dest"; printf '  %-14s 已删除技能目录 %s\n' "$name" "$dest"; fi
    else printf '  %-14s 无需处理 %s\n' "$name" "$dest"; fi
    return 0
  fi
  if [ -f "$dest/SKILL.md" ] && cmp -s "$SKILL_FILE" "$dest/SKILL.md"; then
    printf '  %-14s 技能已最新 %s\n' "$name" "$dest"; return 0
  fi
  if [ "$DRY" = 1 ]; then printf '  %-14s [dry] 将复制技能 %s\n' "$name" "$dest"; return 0; fi
  mkdir -p "$dest"
  cp "$SKILL_FILE" "$dest/SKILL.md"
  [ -d "$REF_DIR" ] && cp -R "$REF_DIR" "$dest/"
  printf '  %-14s 已复制技能 %s\n' "$name" "$dest"
}

# ================================================================ 选择宿主（菜单 / --only）
in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

# 交互式菜单：把选中的宿主 id 写进全局 SELECTED
select_hosts() {
  local i=0 ans part k from to hid hname hdir instr skills hostpath det target found
  local all_ids=() det_ids=()
  printf '本机可处理的宿主（按编号选，可多选）：\n'
  printf '%3s  %-26s %-10s %s\n' '#' '宿主' '状态' '将写入'
  for entry in "${HOSTS[@]}"; do
    IFS='|' read -r hid hname hdir instr skills <<< "$entry"
    i=$((i+1)); all_ids+=("$hid")
    hostpath="$ROOT/$hdir"
    if [ -d "$hostpath" ]; then det='已检测到'; det_ids+=("$hid"); else det='未检测到'; fi
    if [ -n "$instr" ]; then target="$hostpath/$instr"; else target="$hostpath/$skills/$SKILL_ID"; fi
    printf '%3d  %-26s %-10s %s\n' "$i" "$hname" "$det" "$target"
  done
  printf '\n输入编号（如 1,3,5 或 2-4），all=全部（含未检测到的，会新建目录），detected=只处理已检测到的，q=退出；回车=detected\n'
  printf '选择：'
  read -r ans || ans=""
  ans="$(printf '%s' "$ans" | tr -d ' \t')"
  case "$ans" in
    q|quit) return 1 ;;
    ""|d|detected) SELECTED="${det_ids[*]}"; return 0 ;;
    a|all) SELECTED="${all_ids[*]}"; return 0 ;;
  esac
  ans="${ans//，/,}"; ans="${ans//、/,}"
  local picked=()
  IFS=',' read -r -a parts <<< "$ans"
  for part in "${parts[@]}"; do
    [ -n "$part" ] || continue
    if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      from="${BASH_REMATCH[1]}"; to="${BASH_REMATCH[2]}"
      for ((k = from; k <= to; k++)); do
        if [ "$k" -ge 1 ] && [ "$k" -le "${#HOSTS[@]}" ]; then
          IFS='|' read -r hid _ <<< "${HOSTS[$((k - 1))]}"; picked+=("$hid")
        fi
      done
    elif [[ "$part" =~ ^[0-9]+$ ]]; then
      k="$part"
      if [ "$k" -ge 1 ] && [ "$k" -le "${#HOSTS[@]}" ]; then
        IFS='|' read -r hid _ <<< "${HOSTS[$((k - 1))]}"; picked+=("$hid")
      else printf '忽略无效编号：%s\n' "$k"; fi
    else
      found=""
      for entry in "${HOSTS[@]}"; do IFS='|' read -r hid _ <<< "$entry"; [ "$hid" = "$part" ] && found="$hid"; done
      if [ -n "$found" ]; then picked+=("$found"); else printf '忽略无法识别的宿主：%s\n' "$part"; fi
    fi
  done
  SELECTED="$(printf '%s\n' "${picked[@]}" | awk 'NF && !seen[$0]++' | tr '\n' ' ')"
  return 0
}

# ================================================================ 主流程
if [ "${#PROJECTS[@]}" -gt 0 ]; then
  printf '\nai工作医生 / %s  ·  项目级注入\n' "$SKILL_ID"
else
  printf '\nai工作医生 / %s  ·  用户目录：%s\n' "$SKILL_ID" "$ROOT"
fi
if [ "$UNINSTALL" = 1 ]; then mode="卸载"; elif [ "$DRY" = 1 ]; then mode="预览(dry-run)"; elif [ "$LIST" = 1 ]; then mode="体检"; else mode="激活"; fi
printf '模式：%s\n\n' "$mode"

if [ "$SELECT" = 1 ] && [ "${#PROJECTS[@]}" -gt 0 ]; then
  printf '  --select 只用于全局模式，本次已忽略（项目级按 --project 处理）。\n'
fi
if [ "$SELECT" = 1 ] && [ "${#PROJECTS[@]}" -eq 0 ]; then
  if ! select_hosts; then printf '已取消，未改动任何文件。\n'; exit 0; fi
  if [ -z "$SELECTED" ]; then printf '没有选到任何宿主，未改动任何文件。\n'; exit 0; fi
  ONLY="$SELECTED"; EXPLICIT=1
  printf '\n将对以下宿主执行「%s」：%s\n' "$mode" "$ONLY"
  if [ "$DRY" = 0 ] && [ "$LIST" = 0 ]; then
    printf '确认执行？[Y/n] '
    read -r ok || ok=""
    case "$ok" in ""|y|Y|yes|YES|是) ;; *) printf '已取消，未改动任何文件。\n'; exit 0 ;; esac
  fi
  printf '\n'
fi

if [ "${#PROJECTS[@]}" -gt 0 ]; then
  for proj in "${PROJECTS[@]}"; do
    if [ ! -d "$proj" ]; then printf '  %-14s 跳过（目录不存在）%s\n' "$proj" "$proj"; continue; fi
    printf '项目：%s\n' "$proj"
    for entry in "${PROJECT_TARGETS[@]}"; do
      IFS='|' read -r rel tname verified front <<< "$entry"
      # 数据表里用字面 \n 表示换行（避免破坏 IFS='|' read 的单行解析），这里还原成真换行
      if [ -n "$front" ]; then front="${front//\\n/$'\n'}"; fi
      if [ "$verified" != "1" ] && [ "$ALLHOSTS" != 1 ]; then
        printf '  %-14s 跳过（未证实路径，用 -a 才写）%s\n' "$tname" "$proj/$rel"; continue
      fi
      inject_file "$tname" "$proj/$rel" "> 本块由 ai工作医生安装脚本写入（项目级）。卸载：install.sh --project <项目> --uninstall" "" "$front"
    done
  done
else
  for entry in "${HOSTS[@]}"; do
    IFS='|' read -r hid hname hdir instr skills <<< "$entry"
    if [ -n "$ONLY" ] && ! in_list "$hid" "$ONLY"; then continue; fi
    hostpath="$ROOT/$hdir"
    if [ ! -d "$hostpath" ] && [ "$ALLHOSTS" = 0 ] && [ "$EXPLICIT" = 0 ]; then
      [ "$LIST" = 1 ] && printf '  %-14s 跳过（未检测到）%s\n' "$hname" "$hdir"
      continue
    fi
    if [ "$LIST" = 1 ]; then printf '  %-14s 检测到 %s\n' "$hname" "$hostpath"; continue; fi
    if [ -n "$instr" ]; then
      inject_file "$hname" "$hostpath/$instr" "> 本块由 ai工作医生安装脚本写入（技能目录：$hostpath/$skills/$SKILL_ID）。卸载：install.sh --uninstall" "$HEADER_NEW" ""
    fi
    [ -n "$skills" ] && copy_skill "$hname" "$hostpath/$skills"
  done

  # 国产 IDE 型 agent：只在该目录 + 它自己的 rules 子目录都存在时才写（不猜、不建陌生目录）
  for entry in "${PROBES[@]}"; do
    IFS='|' read -r pid pname pdir rule_sub <<< "$entry"
    if [ -n "$ONLY" ] && [ "$ONLY" != "$pid" ]; then continue; fi
    dir="$ROOT/$pdir"
    [ -d "$dir" ] || continue
    rules_dir="$dir/$rule_sub"
    if [ ! -d "$rules_dir" ]; then
      printf '  %-14s 未激活  检测到 %s 但没有 %s/ 子目录 → 路径未知，请把 README 里那段粘进它的「用户规则」设置\n' "$pname" "$pdir" "$rule_sub"
      continue
    fi
    if [ "$LIST" = 1 ]; then printf '  %-14s 检测到 %s（路径未官方证实）\n' "$pname" "$rules_dir"; continue; fi
    inject_file "$pname" "$rules_dir/ai-work-doctor.md" "> 本块由 ai工作医生安装脚本写入（路径未官方证实，嗅探命中）。卸载：install.sh --uninstall" "" ""
  done
fi

echo
if [ "$LIST" = 1 ]; then
  echo "体检完成。要激活：去掉 -l；要预览：加 -n。"
elif [ "$UNINSTALL" = 1 ]; then
  echo "卸载完成：只删了本技能写入的标记块与技能目录，你自己的内容没动。"
elif [ "$DRY" = 1 ]; then
  echo "以上是预览，没有写入任何文件。"
else
  echo "激活完成。验证生效：新开一个对话，让 agent 复述预算上限（read 2 / search 2 / deploy 2 / no-op 2 / tool-err 3）。"
  echo "UI 里配规则的宿主（Cursor / Trae / 灵码 / Comate / CodeBuddy…）：把 README「手动兜底」那段粘进它的用户规则设置。"
  echo "卸载：./install.sh --uninstall（项目级：./install.sh --project <目录> --uninstall）"
fi
