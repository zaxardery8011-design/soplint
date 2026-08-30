# soplint

**Lint rules for your AI agent's discipline, not its code.**

I've run a personal AI agent 24/7 for a year. It writes good code — that was never the problem. The problem was discipline: it said "fixed and verified" without verifying, silently reversed its own judgments, and made policy decisions that rotted in memory while its behavior drifted back to old habits.

Code linters catch style violations. Memory tools catch broken links and stale notes. Harness linters (e.g. [AgentLint](https://github.com/0xmariowu/AgentLint)) check that your rules files are well-written. soplint checks something else: did the agent actually **keep the working agreements you made with it**?

> **Start with the engine first.**
> soplint is the guardrail, not the runtime: it audits discipline after you already have an agent that can run.
> If you want a local agent that can take tasks, run workers, and leave file-based evidence, start with [aiwff-runtime](https://github.com/zaxardery8011-design/aiwff-runtime).
> 中文入口: [小主腦導入頁](https://zax.com.tw/minibrain)。

## How it works

Three mechanisms, all extracted from a year of real incidents:

### 1. Belief revision audit trail

Every time your agent overturns a prior judgment, it must log it:

```powershell
Import-Module ./lib/BeliefLog.psm1
Add-BeliefRevision -From "Assumed the cache layer was thread-safe" `
                   -To "Race confirmed under load; needs a lock" `
                   -Trigger estimate_correction -ConfidenceShift "high->low"
```

One JSON line per revision (`from_belief`, `to_belief`, `trigger`, `confidence_shift`), appended to a greppable JSONL file. The `trigger` field is a deliberate enum — free-text triggers turn an audit log into noise.

Why external file instead of a prompt rule? Because prompt rules fail. I watched my agent violate a written "acknowledge belief changes" rule three times in one day. An agent can ignore an instruction silently; a missing or stale log file is loud — and a lint check audits that the log is actually being written. (Could an agent with write access fake entries? Technically yes — but that's a far higher bar than ignoring a prompt, and fakes leave greppable inconsistencies.)

### 2. Discipline checks (run daily via cron / CI)

```
pwsh -NoProfile -File bin/soplint.ps1
```

| Check | What it catches | The incident behind it |
|---|---|---|
| `decision_propagation` | A "new default" decision written to memory but never propagated to your agent's operating instructions (CLAUDE.md) | A dispatch-policy decision rotted in memory for two weeks while every fresh session did the old thing |
| `belief_revision_audit` | The belief log not being written (lint the audit itself) | An audit nobody audits is decoration |
| `memory_frontmatter` | Memory files missing required metadata | Unsearchable memories are write-only memories |
| `index_health` | Memory index oversized or with duplicate entries | A bloated index silently truncates what your agent loads each session |

Each check exits non-zero on failure, so wiring into CI or a cron job is trivial. Failures should land somewhere your agent has to face them — an inbox, a ping, a blocked merge.

### 3. Pre-action gate (hook)

`hooks/pretool-guard.ps1` runs as a PreToolUse hook. For shell commands, it reduces the PowerShell input to AST command signatures before applying external deny/novelty regex rules, avoiding common quoted-string false positives. This is a guardrail, not a sandbox. Rules live in external JSON:

- **Deny rules** — hard red lines. Example shipped: an agent must never respawn its own daemon (learned via cascade process death).
- **Novelty gate** — before the agent builds a new tool, it must prove it scanned existing tools first (an acknowledgement comment). The agent that rebuilds tools it already has is burning your money twice.

See `rules/guard-rules.example.json` for the expected rule-file shape.

Scope: the AST parse understands PowerShell commands. If your agent shells out through bash or python, you need an equivalent parser on that side — the deny-rules JSON is portable, the parser is not.

## Quickstart

```powershell
# 1. Configure
Copy-Item soplint.config.example.json soplint.config.json
#    edit paths: memory_dir, claude_md_path, beliefs_log, index_file

# 2. Run the checks
pwsh -NoProfile -File bin/soplint.ps1

# 3. Run the test suite
pwsh -NoProfile -File tests/run_all_tests.ps1
```

Requires PowerShell 7+ (runs on Linux / macOS / Windows — CI covers all three). See `examples/CLAUDE.md.example` for the SOP block to paste into your agent's instructions.

## Install in an agent repo

There is no package manager wrapper yet. For now, vendor or clone the repo and point `soplint.config.json` at your agent's real files:

```powershell
git clone https://github.com/zaxardery8011-design/soplint.git tools/soplint
Copy-Item tools/soplint/soplint.config.example.json soplint.config.json
# edit paths in soplint.config.json
pwsh -NoProfile -File tools/soplint/bin/soplint.ps1 -Config soplint.config.json
```

Typical passing output:

```text
[OK ] belief_revision_audit.ps1 - PASS belief-revision-audit (log present and fresh within 30 days)
[OK ] decision_propagation.ps1 - PASS decision-propagation (memory decisions are present in the policy file)
[OK ] index_health.ps1 - PASS index-health (index 0KB, no duplicate links)
[OK ] memory_frontmatter.ps1 - PASS memory-frontmatter (1 memory files scanned)

============================================================
SOPLINT: 4 pass / 0 fail
```

In CI, run the same command and let non-zero exits fail the build. In a long-running agent, run it from a scheduler and route failures into the agent inbox.

## 中文簡介

soplint 是一個給 AI agent 用的「工作紀律 linter」。

它不檢查程式碼風格，而是檢查 agent 是否真的遵守你和它約好的工作規則：例如修正判斷時有沒有留下 belief revision 紀錄、重要決策有沒有同步到操作規範、memory index 是否過大或重複、執行高風險動作前是否被 pretool guard 擋下。

這個工具適合長期運行的 Claude Code / Codex / 自建 agent 系統，用來把事故後得到的教訓變成每天可跑的 regression check。它的目標不是讓 agent 變聰明，而是防止同一種錯誤反覆回來。

## What this does NOT solve

This is a regression test suite for **known** failure modes, not alignment:

- Your agent will still make novel mistakes. Lint only stops the old ones from coming back.
- Every check here exists because something already went wrong. This is scar tissue, codified.
- It's PowerShell because my stack is — a better fit than it sounds: the AST parser the gate relies on ships in pwsh's standard library, zero dependencies. If your stack isn't PowerShell, steal the ideas — the mechanisms (external audit trail, discipline-as-CI, AST-based pre-action gates) are portable to any language.

## The loop that makes it compound

Anthropic's advice for agents: when your agent makes a mistake, have it write the lesson to CLAUDE.md or a skill. That's step one. **Step two is testing that it actually did** — a lesson written to memory is a hope; a lesson with a lint rule behind it becomes a regression signal you can run every day.

When your agent gets away with something this week, don't just correct it. Write the check.

## Related — the discipline toolchain

soplint is a **guardrail** — it audits whether an AI work node stays disciplined. Want a local agent runtime that actually runs these disciplined agents? Start with the engine:

- **[aiwff-runtime](https://github.com/zaxardery8011-design/aiwff-runtime)** — the local agent runtime (the engine that runs disciplined agents) → **想要一台真的跑得動的 agent runtime？從這台小主腦開始。**
- **[aiwff-mini](https://github.com/zaxardery8011-design/aiwff-mini)** — a personal brain with a soul file, cross-chat memory and integrity guards; paste one line into your AI tool and it installs itself → **想要一顆有靈魂錨、記得住事、還會擋自己竄改設定的個人主腦？貼一句話就裝好。**
- **[execution-proofs](https://github.com/zaxardery8011-design/execution-proofs)** — MCP telemetry gateway: force agents to prove "done" with real files & timestamps
- **[soplint](https://github.com/zaxardery8011-design/soplint)** — static SOP-compliance audit for AI work nodes (this repo)

> 引擎（跑得動的 agent）＋護欄（審紀律、逼證明），同一套「讓 AI 守紀律」哲學的兩面。

## Install with an AI

Paste this into your AI tool (Claude Code, Codex, Cursor, Cline, Gemini, or similar):

```
Read README.md in this folder and install soplint for me.
```

It will first check whether it can finish, show you the files it plans to create, wait for your approval, and then run a self-check.

Requirement: PowerShell 7 or newer. If it is missing, stop and say so instead of pushing through.

## For the AI Performing the Installation

You are installing soplint for your human.

This installation is **additive only**: create only this tool's own files. Do not touch their other settings, do not edit their shell profile, and do not modify any existing files unless they explicitly allow it and you make a backup first.

There is no installer script and no package-manager wrapper. "Install" means: get a complete soplint checkout, copy `soplint.config.example.json` to `soplint.config.json`, and prove the package runs. Pointing that config at the agent's real files is a separate, approved edit.

### Step 0 - Capability Check First

**Do not start an installation you cannot finish.** Confirm that you can do all four:

1. Read files
2. Write files into a new directory
3. Run commands and see their output
4. Report the result back to the human

If any one is missing, stop here, state exactly what is missing, and **create no files at all**. A clean refusal is better than a half-installed system.

### Step 1 - Do Not Install Inside the Development Tree

**Never modify the author's own system.**

Check whether your current directory is this tool's own source tree, not someone else's copy.

**There is only one stop condition**: the marker file `.dev-tree` exists in the soplint checkout root. It appears only in the author's working directory and is not committed to the repo, so a copy you got from `git clone` will not have it.

The other two checks are supporting signals. **On their own, they are not a reason to stop**, but you should still report them:

- Does the current path contain fragments such as `open_source_prep/`?
- Does the current directory have uncommitted local changes?

> Warning: **A `git clone` copy normally has `.git`, and its remote normally points to this project's upstream. That is normal and does not count as a match.** Every legitimate copy looks like that; using it as a stop condition would block every user.

**Report which checks you actually ran and which ones were outside your permissions.** "I ran checks 2 and 3; check 1 was outside my permission scope" is a correct answer. **Silently skipping a check and saying everything is fine is not.**

If the marker file matches, stop and explain. Do not install, and do not "helpfully" install somewhere else.

### Step 2 - Detect the Environment

Actually run the checks. Do not assume:

| Item | How to check | Requirement |
|---|---|---|
| PowerShell | `pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'` | 7.0 or newer |
| Install destination | the path the human named (agent repo or `<repo-path>`) | Must be writable |
| Package completeness | Self-check 2 below | All listed files must exist after clone |

**If the machine has PowerShell 5.1 but not 7, stop and report it**, including this fix command: `winget install --id Microsoft.PowerShell`. Do not fall back to 5.1. This package has only been verified on PowerShell 7 or newer, and running quietly in an unverified environment is worse than not installing.

> Warning: **On many machines, `powershell` is 5.1 and `pwsh` is 7, and both may be installed side by side.** Confirming that 7 exists does not prove the next command will run under 7. Every later command must explicitly call **`pwsh`**, not the system default `powershell`.

### Step 3 - Show the Plan, Wait for Approval, Then Act

Ask which shape they want:

1. **Vendor into an existing agent repo** (the documented default): clone soplint to `tools/soplint` inside that repo, and copy the example config to `soplint.config.json` at the agent-repo root.
2. **Use an existing soplint checkout**: if `<repo-path>` already contains `bin/soplint.ps1` and the other required files, do not clone again. Only copy the config if they want a local `soplint.config.json`.

Always use this order:

1. **List** every file you are going to create, with its full path
2. **Show the list to the human**
3. **Wait for approval** - create nothing until they approve
4. **Run** the commands below. Type them exactly.

Vendor into an agent repo (current directory = the agent repo):

```powershell
git clone https://github.com/zaxardery8011-design/soplint.git tools/soplint
Copy-Item tools/soplint/soplint.config.example.json soplint.config.json
```

Already inside `<repo-path>`:

```powershell
Copy-Item soplint.config.example.json soplint.config.json
```

Rules while running:

- If the target file or clone directory already exists, **do not overwrite**. Back up every file that would be replaced as `<original-name>.bak.<timestamp>`, and say what you backed up
- Do not create anything outside the agreed destination
- Do not touch PATH or shell profiles in this step
- Do not edit the human's `CLAUDE.md`, memory files, or hook settings unless they explicitly asked

### Step 4 - Point the Config (only after they say so)

`soplint.config.json` copied from the example still points at `tests/fixtures/pass/...`. That is a **package fixture**, not the human's agent.

Ask:

- Where is their memory directory?
- Where is their `CLAUDE.md` (or equivalent policy file)?
- Where is their beliefs log (JSONL)?
- Where is their memory index file?

Write those four keys (`memory_dir`, `claude_md_path`, `beliefs_log`, `index_file`) and **read the file back for confirmation**. Do not invent paths.

If they only wanted to verify that soplint itself works, leave the example paths and skip this step.

> Warning: **Do not treat a green run against the unedited example config as a lint of the human's agent.** Example paths still point at `tests/fixtures/pass/...` (Step 4). The runner refreshes that bundled fixture's mtime before the checks so the Quickstart does not rot after 30 days; that refresh does not apply to a real `beliefs_log`. Package health is the test suite in Step 5. A run against the human's real files is a lint of *their* agent, not a verdict on the install.

### Step 5 - Acceptance Check

Run these from `<repo-path>` (the soplint checkout root; if you vendored it, that is `tools/soplint`). All five must pass:

1. PowerShell 7 or newer:

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
```

2. Package completeness (prints `True` eleven times, then `PACKAGE COMPLETE`):

```powershell
pwsh -NoProfile -Command ' $r = Test-Path -LiteralPath @("bin/soplint.ps1","checks/belief_revision_audit.ps1","checks/decision_propagation.ps1","checks/index_health.ps1","checks/memory_frontmatter.ps1","lib/BeliefLog.psm1","hooks/pretool-guard.ps1","soplint.config.example.json","tests/run_all_tests.ps1","tests/prepare_pass_fixtures.ps1","examples/CLAUDE.md.example"); $r -join ","; if ($r -contains $false) { exit 1 }; "PACKAGE COMPLETE" '
```

3. Example config parses:

```powershell
pwsh -NoProfile -Command 'Get-Content -Raw -LiteralPath soplint.config.example.json | ConvertFrom-Json | ConvertTo-Json -Compress'
```

4. Test suite (must print `TESTS: 6 pass / 0 fail`):

```powershell
pwsh -NoProfile -File tests/run_all_tests.ps1
```

5. BeliefLog module loads (must print `Add-BeliefRevision,Get-BeliefRevisions`):

```powershell
pwsh -NoProfile -Command 'Import-Module ./lib/BeliefLog.psm1 -Force; (Get-Command -Module BeliefLog | Select-Object -ExpandProperty Name) -join ","'
```

If they asked you to point the config at real agent files, you may then run:

```powershell
pwsh -NoProfile -File bin/soplint.ps1 -Config <path-to-their-soplint.config.json>
```

A non-zero exit there is a lint finding against those files. Report it. Do not edit soplint's checks to make it pass.

### Step 6 - Report Back

Report in this order:

1. Which Step 1 checks you actually ran, and which ones were outside your permissions
2. The file list you showed before acting in Step 3
3. The result of each of the five acceptance checks in Step 5
4. Whether the config still points at fixtures or at the human's real files
5. Anything you guessed, bypassed, or could not verify

If any item fails, say it failed and stop. **Do not edit the scripts or fixtures just to make the checks pass.** An honest failure is more useful than a secretly fixed success.

## Definition of Alive

It is only alive when all four are true:

1. Every soplint command is run with `pwsh` 7 or newer
2. The checkout contains the runner, four checks, BeliefLog, example config, and test runner
3. `tests/run_all_tests.ps1` reports `TESTS: 6 pass / 0 fail`
4. `bin/soplint.ps1 -Config soplint.config.example.json` prints `SOPLINT: 4 pass / 0 fail`

> 中文摘要：先自檢能否讀寫檔與執行 PowerShell 7；碰到 `.dev-tree` 就停；先列檔案等批准再 clone/copy；裝好的定義是測試套件 6 pass，且 example config 跑出 `SOPLINT: 4 pass / 0 fail`。

## License

MIT
