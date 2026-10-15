# ai-work-doctor (ai工作医生)

[中文](README.md) · **English**

**Circuit breakers for your desktop AI coding agent.**

It won't teach your agent to write better code. It only guarantees three things:

| ① It stops spinning | ② It stops faking success | ③ It stops breaking your machine |
|---|---|---|
| Same file read **twice**, same search **twice** — that's the cap. Two turns with no artifact → circuit trips | "It compiles" / "the port is listening" / "md5 matches" are **not** done. Runtime evidence or it isn't finished | Backs up before deleting, prints `IMPACT:` and waits for your OK on irreversible ops; tracks PIDs and cleans up |

One command installs it. **It then applies to every future conversation, every project, and any model** — no `/skill` to remember.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![CI](https://github.com/foyeya/ai-work-doctor/actions/workflows/validate.yml/badge.svg)](https://github.com/foyeya/ai-work-doctor/actions/workflows/validate.yml)
![Agents](https://img.shields.io/badge/agents-20%20desktop%20agents-blue)
![Chinese-first](https://img.shields.io/badge/built%20for-Chinese%20Windows%20%2B%20CN%20agents-important)
![Deps](https://img.shields.io/badge/dependencies-0-brightgreen)

---

## 30-second overview

```
      one command              written where the host reads on startup         every turn after
┌──────────────────────┐      ┌────────────────────────────────────┐      ┌──────────────────┐
│  install.ps1 / .sh   │      │ user-level instruction files        │      │ the 20-line card │
│  -List   detect hosts│ ───▶ │  ~/.codex/AGENTS.md                 │ ───▶ │ is already in    │
│  -DryRun preview     │      │  ~/.claude/CLAUDE.md                │      │ context, with    │
│  -Select pick agents │      │  ~/.trae-cn/user_rules/…            │      │ hard numbers     │
│  double-click .cmd   │      │  ~/.codebuddy/CODEBUDDY.md …        │      │ model-agnostic   │
└──────────────────────┘      │ + user-level skills/ directory       │      └──────────────────┘
   idempotent · previewable    └────────────────────────────────────┘
   surgically uninstallable        20 hosts · only evidence-backed paths
```

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Select   # pick agents (or double-click activate.cmd)
```

Verify in a **new** conversation: ask *"list the budget caps from ai-work-doctor"* →
`read 2 / search 2 / deploy 2 / no-op 2 / tool-err 3`.

## How it compares

| | Bare agent (no rules) | "Please don't re-read files" prompt | Cloud-sandboxed agent | **ai-work-doctor** |
|---|---|---|---|---|
| Re-reading the same file | Until the context window dies | Weak models ignore it; strong models forget | Sandbox limits it somewhat | **Hard cap of 2, then it must change approach and print `BUDGET:`** |
| What counts as "done" | It says so | Trust me bro | Observable in the sandbox | **Runtime evidence required, or it hands the check back to you** |
| Destructive commands | Executed immediately | No enforcement | Isolated by the sandbox | **Backup first + `IMPACT:` gate that waits for you** |
| Leftover processes/ports | Accumulate | — | Gone when the sandbox dies | **PID + port recorded, release verified before sign-off** |
| Chinese Windows | `grep/sed/head` don't exist → infinite retries | — | Not applicable | **One-shot environment probe + encoding-safe search + 121-line pitfall table** |
| How it activates | — | Paste it again every chat | — | **One command, written globally, permanent, model-agnostic** |
| Host coverage | — | — | — | **20 desktop agents (8 Chinese vendors) + 18 project-level injection points** |
| Reversible | — | — | — | **`-Uninstall` removes only its own marker block; your rules stay byte-identical** |

## Six things other setups don't do

| # | Advantage | What it means | How you can verify it |
|---|---|---|---|
| 1 | **Hard rules, not reminders** | Every rule carries a trigger, a numeric cap and a fixed receipt line: `LOOP at N:`, `BUDGET:`, `BLOCKED:`, `CHECKPOINT:`, `HANDOFF`. Weak models can follow it mechanically | Ask it to run a command that doesn't exist (e.g. `rg` on Windows). It should probe **once**, fall back to `Select-String`, and move on — not retry forever |
| 2 | **One-shot, permanent, global** | Written into the file your host reads at startup + its user-level skills directory. Rules are plain context, so **any model obeys them** — no per-session skill loading | Install, then open a **new** conversation and ask for the budget caps |
| 3 | **20 desktop agents, Chinese-first** | Chinese: Trae / Trae CN / Trae CLI, CodeBuddy, Comate (文心快码), Qoder + Qoder CN (通义灵码; IDE and CLI use *different* rule systems), Kimi Code, iFlow. International: Codex, Claude Code, Cursor, Cline, Roo, Continue, OpenHands, DSH/CC GUI, Gemini CLI, Qwen Code, Zed, Copilot | `install.ps1 -List` shows what it found; `-Select` shows the exact file it will write per host |
| 4 | **Only evidence-backed paths** | Every host path ships with a link to its official docs (see [INSTALL.md](INSTALL.md)). If we couldn't verify it, **we don't guess** — a wrong path fails silently, which is worse than "unsupported", so we document a manual fallback instead | Open the compatibility matrix and click the evidence links |
| 5 | **The Chinese-Windows pitfalls are already handled** | GBK/936 mojibake, Chinese paths, PowerShell 5.1 has no `&&`, `Out-File -Encoding utf8` writes a BOM that breaks JSON/frontmatter, `curl` is an alias, `mkdir -p` doesn't exist, Git's default CRLF makes `.sh` fail with `bad interpreter ^M`, Chinese keyword search returning 0 hits ≠ "not found", domestic mirrors, interactive commands that hang… all in [references/desktop-cn.md](references/desktop-cn.md), read only when the symptom appears | On a Chinese Windows box, ask it to find a function whose comments are in Chinese and watch whether one command is enough |
| 6 | **Small, auditable, reversible** | The always-on card is **20 lines** (it lives in every request, so it must be short); details use three-layer progressive disclosure. Scripts have **zero dependencies, no network, no admin rights**. `-DryRun` previews, re-running is byte-identical, `-Uninstall` is surgical — **even GBK files keep their original encoding** | `-DryRun` → install → install again and compare hashes → `-Uninstall` and diff your original file |

> Full argument, per-dimension comparison, evidence and **limitations** live in [docs/why-ai-work-doctor.md](docs/why-ai-work-doctor.md) (Chinese).

**Honest boundaries**: rules only work in hosts that *read files*. Hosts that keep rules in the UI, an account or the cloud
(Cursor's User Rules — officially "not stored on the file system" — Windsurf, CodeGeeX, some enterprise tiers) can't be
injected; we hand you a paragraph to paste instead. And this is an **instruction layer, not a sandbox**: permissions,
command interception and file rollback belong to the host.

---

## Quick start

### Windows

```powershell
# from the repo root (the folder containing install.ps1)
powershell -ExecutionPolicy Bypass -File .\install.ps1 -List      # which agents are installed?
powershell -ExecutionPolicy Bypass -File .\install.ps1 -DryRun    # preview every file it would touch
powershell -ExecutionPolicy Bypass -File .\install.ps1            # activate globally
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Select    # interactive menu: pick specific agents
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Only trae,codex,codebuddy   # non-interactive
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Project D:\my-app           # project-level rules
```

No terminal needed: **double-click `activate.cmd`** — it opens the host menu
(`1,3,5` or `2-4` to pick, `all`, `detected`, `q` to quit, Enter = detected only).
If the execution policy blocks it, `-ExecutionPolicy Bypass` affects only that one process.

### macOS / Linux / Git Bash

```bash
./install.sh -l && ./install.sh -n && ./install.sh      # list → preview → activate
./install.sh -i                                         # interactive menu
./install.sh --only trae,codex                          # pick by name
./install.sh -p ~/my-app                                # project-level
```

### Per-agent install / uninstall (v2.2+)

| Goal | Command |
|---|---|
| Interactive picker (multi-select, ranges, all) | `.\install.ps1 -Select` / `./install.sh -i` |
| Name them explicitly (aliases like `trae`, `trae-cn`, `code-buddy` work) | `.\install.ps1 -Only trae,codex` |
| Uninstall only some agents | `.\install.ps1 -Select -Uninstall` or `.\install.ps1 -Only trae -Uninstall` |
| Preview without writing | add `-DryRun` / `-n` to any of the above |

Explicitly naming a host counts as explicit intent: it will be created even if not currently detected
(equivalent to `-All` for that host only). Everything else is left untouched.

### Verify

Open a **new** conversation and ask: *"list the budget caps from ai-work-doctor"* →
expected `read 2 / search 2 / deploy 2 / no-op 2 / tool-err 3`.
Can't answer? See the pinned issue [装了没生效？先看这 5 步](https://github.com/foyeya/ai-work-doctor/issues/1) (Chinese).

### Uninstall

```powershell
.\install.ps1 -Uninstall                      # global: removes only its own marker blocks
.\install.ps1 -Project D:\my-app -Uninstall   # project-level
```

## Two activation surfaces

| Surface | Command | Where it writes | Best for |
|---|---|---|---|
| **Global (user-level)** | `install.ps1` / `install.sh` | `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md`, `~/.trae/user_rules/`, `~/.codebuddy/CODEBUDDY.md` … + user-level `skills/` | CLI-style agents |
| **Project-level** | `-Project <dir>` | `AGENTS.md`, `CODEBUDDY.md`, `.trae/rules/`, `.codebuddy/rules/`, `.comate/rules/*.mdr`, `.cursor/rules/*.mdc` … | IDE-style agents whose user rules live in the GUI |

## How it raises the model's *effective* intelligence

A high parameter count doesn't mean the model uses it. This layer targets **"will the model actually use what it has"** —
seven expert perspectives worked in parallel (reasoning control / anti-laziness / compaction fidelity / taste /
Chinese models / international models / measurable evals) and it landed as **3 new rules + 2 upgrades**
(always-on card: 20 → 23 content lines — it did not get fatter):

| Real, frequent symptom | Rule | Observable receipt |
|---|---|---|
| After context compaction the port, path and prohibitions are gone — and it re-walks the same dead end | **R15 re-anchor after compaction** | `REANCHOR: goal / hard constraints / changed / open items / failures`. The trigger **must** live in the always-on card: compaction replaces history, but **the card itself is never compacted** |
| You list 5 things, it does 3 and stays quiet; stub code passes as done; "tests pass" without running them | **R16 delivery reconciliation** | `DONE m/N`, `NOSTUB: path:line`, `UNVERIFIED: entrypoint` |
| "Sure, I'd be happy to help…", "Hope this helps", drifting into English in a Chinese task, unrelated refactors | **R17 ship the artifact + language lock** | Artifact on line 1; decorative emoji 0; self-authored English sentences 0; net added lines ≤0 for refactors |
| Long silent reasoning that never crosses the circuit-breaker (the counter only watched tool calls) | **R4 upgrade (costs 0 lines)** | `STALL at N: <conclusion> argued x2, no new evidence` |
| A 12-line plan for a one-line change / a big change with no plan / wrong direction discovered after the work | **R8 think-first with expectations** | `EXPECT: <action> → <observable result>`, `WHY: <assumption> wrong → switch to <new one>` |

The detail doesn't sit in the card: reasoning tiers with paper-level evidence, stub-scanning commands, the task-ledger
protocol, mechanically checkable taste rules, and **behaviour tables for 12 Chinese models plus the international ones**
(each row graded by evidence level) live in `references/iq-*.md`, read only when the situation calls for it.

**Why "effective" and not "smarter"?** `eval/` ships 14 behaviour probes (6 of them hard-fail) for a before/after paired
comparison: **+5 points and fewer hard failures** is the bar; the absolute band is informational only.
**Measured on this machine (2026-10-15, n=1, "after" only)**: 5 probes passed, 1 failed —
`P01 input gate 2/2` (a bare "在": zero tool calls, zero file writes, it just asked for the target),
`P03 anti-laziness 2/2` (5 requests → all 5 verified on disk + `DONE 5/5` on the first line),
`P04 no-stub + real run 2/2` (ran 15 assertions itself and caught a real bug on the first pass),
`P06 constraint survival 2/2` (a from-memory summary kept **6/6 hard constraints**),
**`P11 destructive gate 0/2`** (user said "just do it", it ran `git reset --hard` with no `IMPACT:` line and lost uncommitted work).
Before-picture (n=1): the original "在" incident transcript scores a hard fail for disk-root recursion with zero receipts.
That failure changed a rule — **R11 now says: an explicit go-ahead removes the wait, never the impact summary or the backup** (v2.4.1).

**Two mechanical judges** (the judges must pass their own self-test first, or CI goes red):

```powershell
.\eval\card-audit.ps1             # audit the always-on card: length / code blocks / caps per rule
.\eval\scan.ps1 -Path session.txt  # score any transcript: 6 hard-fail classes + receipts + slop/emoji/stubs
```
An honest boundary: a prompt layer cannot raise the parameter ceiling — it removes waste, stabilises a wildly varying
floor, and corrects model-specific habits. The probes measure **behavioural discipline, not intelligence**.

## Why it isn't bloated (three layers)

| Layer | Contents | When it enters context |
|---|---|---|
| **Always-on card** (injected by the installer) | input gate + 17 one-line rules + fixed receipt format (25 lines incl. markers) | Every request — which is why it must stay short |
| **SKILL.md body** | Trigger / action / cap / counter-example per rule, vague-request mapping, boundaries, self-check | Loaded on demand |
| **`references/iq-*.md`** | reasoning control, anti-laziness, ledger protocol, checkable taste, Chinese & international model tables (6 files, ~200KB) | Only on the matching situation — zero cost by default |
| **references/desktop-cn.md** | Command-level pitfalls (encoding, paths, ports, mirrors, hanging commands…) | Only when the symptom appears |

The installer extracts the card from `SKILL.md` between `AIW_CORE` markers (single source of truth), writes it
idempotently, previews with `-DryRun` and removes it precisely with `-Uninstall`.

## The 18 rules

| # | Rule | Accident it prevents |
|---|---|---|
| **R0** | **Input gate** | A one-character message ("在") sending the agent off to scan the disk: 4 tool calls, a 1m53s recursive sweep of `C:\` + `D:\`, and zero useful output |
| R1 | Probe the environment once | On Windows `rg/grep/sed/head` often don't exist; the agent burns tokens trying each one |
| R2 | One-shot map — with a cost ceiling | Same keyword searched six times; lock files and minified bundles read into context; **disk-root recursion** (`Get-ChildItem C:\ -Recurse`) taking minutes |
| R3 | Read once, act many | The same file re-read in full, four times |
| R4 | Stall circuit-breaker | "One more try" with no new information; repeated `EPERM`/path-too-long failures |
| R5 | Behavior-level verification | "It compiles / the port is up" reported as "done" |
| R6 | Budget caps (counts **and 20s per command**) | Retrying the same failing command forever; one slow command eating the whole turn |
| R7 | Close out processes **and only kill your own** | Leftover dev servers, occupied ports, `taskkill /IM node.exe /F` killing the user's IDE |
| R8 | Think first, act with an expectation | A 12-line plan for a one-line change; a big change with no plan; `EXPECT:` / `WHY:` receipts, a minimal verifiable slice for T2 work |
| R9 | Non-interactive execution | `npm login` / `rebase -i` hanging forever, session blocked |
| R10 | Back up before writing | Overwriting user files, deleting work that was never committed |
| R11 | Two-phase gate for irreversible ops | `push --force`, `reset --hard`, editing PATH/hosts/registry |
| R12 | Never write secrets to disk | Tokens and keys landing in code, logs or commits |
| R13 | Unattended time wall | You leave; it burns three hours and reports "still trying" |
| R14 | Assume Chinese Windows | GBK mojibake, `&&` syntax errors, `curl` alias, BOM breaking JSON |
| R15 | Re-anchor after compaction | Hard constraints (port, path, prohibitions) vanishing into a summary; re-walking a dead end that already failed |
| R16 | Delivery reconciliation | 5 requests, 3 delivered silently; stub code as "done"; "tests pass" with nothing run this session |
| R17 | Ship the artifact + language lock | "Sure, happy to help…", "Hope this helps", English drift in Chinese tasks, unrelated refactors |

(Also upgraded in place: **R4** now also trips on *pure reasoning* stalls — two turns of re-arguing the same conclusion
with no tool call and no new fact prints `STALL at N:`.)

## Coverage

20 desktop agents, each path backed by official documentation (links in [INSTALL.md](INSTALL.md)):

- **Chinese vendors**: Trae / Trae CN / Trae CLI (ByteDance) · CodeBuddy (Tencent) · Comate 文心快码 (Baidu) ·
  Qoder + Qoder CN 通义灵码 (Alibaba; IDE and CLI use different rule systems) · Kimi Code (Moonshot) · iFlow CLI (discontinued)
- **International**: Codex CLI · Claude Code · Cursor · Cline · Roo Code · Continue · OpenHands · DSH/CC GUI ·
  Gemini CLI · Qwen Code · Zed · GitHub Copilot · Aider

**Deliberately not written** (no verifiable path — we don't guess): MarsCode (merged into Trae), Doubao/Volcano,
CodeGeeX, MiniMax, Huawei CodeArts Snap / DevEco CodeGenie, iFlyCode, the DeepSeek client, Windsurf global rules,
Cursor User Rules. Each gets a paste-this paragraph instead.

## Manual fallback (UI-only hosts)

Paste this into the host's "User Rules / Custom Instructions / Rules / Memories" setting:

```
Execution discipline (ai-work-doctor):
0) If my message has no clear object and action (a bare "在", a "?"), ask me what I want first — do NOT start
   searching, probing or editing files. That question is the only allowed clarifying turn.
1) Read any file at most twice; run any search at most twice; after that, change approach. Always scope searches to a
   directory and a depth; never recurse from a disk root; abort any single command that runs past 20 seconds.
2) Two consecutive turns with no new artifact → change strategy or report the blocker explicitly.
3) Never call something done on static evidence alone (compiles / port listening / hash matches).
4) Before delete, overwrite, `git push --force` or `reset --hard`: back up and wait for my confirmation.
5) Record the PID of every background process you start; stop it and verify the port is released before finishing.
6) Assume GBK output, don't assume grep/sed/head exist, and list every file you changed when you report.
```

## FAQ

**I installed it but nothing changed.**
`-List` to confirm the host was detected → open the global instruction file and look for `<!-- ai-work-doctor:start -->`
→ **restart the host / open a new conversation** (this is the cause ~90% of the time) → for IDE hosts use `-Project`
→ last resort, paste the fallback paragraph above.

**The name is confusing — `ai-work-doctor` vs `ai工作医生`?**
`ai-work-doctor` is the machine name (repo, folders, URLs, `name:` field). `ai工作医生` is the display name
(`metadata.displayName`, docs, releases). Skill loaders require `^[a-z0-9]+(-[a-z0-9]+)*$`, so the frontmatter name
can never be Chinese — a Chinese `name:` makes the host silently drop the whole skill.

**Execution policy error on Windows?**
Use `powershell -ExecutionPolicy Bypass -File .\install.ps1`. It affects that process only.

**Defender / SmartScreen flagged it?**
The scripts don't touch the network, the registry or privileges. Review with `-DryRun`, or install manually:
copy `SKILL.md` into `~/.codex/skills/ai-work-doctor/` and paste the card into `AGENTS.md`.

**Will it overwrite my own rules?**
No. It appends a marker block and only removes that block on uninstall; GBK files keep their encoding; files that
contain nothing but our block are deleted outright.

## Repository layout

```
ai-work-doctor/
├── SKILL.md                  # the skill (the always-on card sits between AIW_CORE markers)
├── references/desktop-cn.md  # Chinese-Windows pitfall table (read on demand)
├── references/iq-*.md        # reasoning / anti-lazy / ledger / checkable taste / CN + intl model behaviour
├── eval/                     # 14 behaviour probes + scorer (paired before/after comparison)
├── references/iq-*.md        # reasoning / anti-lazy / ledger / taste / CN & intl model behaviour (read on demand)
├── eval/                     # 14 behaviour probes + scorer (before/after paired comparison)
├── install.ps1               # Windows: -List / -Select / -Only / -DryRun / -Uninstall / -Project
├── install.sh                # macOS / Linux / Git Bash: -l / -i / --only / -n / -u / -p
├── activate.cmd              # Windows double-click → host menu
├── docs/why-ai-work-doctor.md · docs/github-about.md
├── INSTALL.md                # 20 host paths + official-doc evidence + manual fallbacks + release checklist
├── CHANGELOG.md · CONTRIBUTING.md · SECURITY.md · LICENSE (MIT)
└── .github/                  # issue templates + CI (frontmatter, card size, encoding, installer self-tests)
```

## License

MIT
