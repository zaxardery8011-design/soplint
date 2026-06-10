# soplint

**Lint rules for your AI agent's discipline, not its code.**

I've run a personal AI agent 24/7 for a year. It writes good code — that was never the problem. The problem was discipline: it said "fixed and verified" without verifying, silently reversed its own judgments, and made policy decisions that rotted in memory while its behavior drifted back to old habits.

Code linters catch style violations. Memory tools catch broken links and stale notes. Harness linters (e.g. [AgentLint](https://github.com/0xmariowu/AgentLint)) check that your rules files are well-written. soplint checks something else: did the agent actually **keep the working agreements you made with it**?

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

## What this does NOT solve

This is a regression test suite for **known** failure modes, not alignment:

- Your agent will still make novel mistakes. Lint only stops the old ones from coming back.
- Every check here exists because something already went wrong. This is scar tissue, codified.
- It's PowerShell because my stack is — a better fit than it sounds: the AST parser the gate relies on ships in pwsh's standard library, zero dependencies. If your stack isn't PowerShell, steal the ideas — the mechanisms (external audit trail, discipline-as-CI, AST-based pre-action gates) are portable to any language.

## The loop that makes it compound

Anthropic's advice for agents: when your agent makes a mistake, have it write the lesson to CLAUDE.md or a skill. That's step one. **Step two is testing that it actually did** — a lesson written to memory is a hope; a lesson with a lint rule behind it becomes a regression signal you can run every day.

When your agent gets away with something this week, don't just correct it. Write the check.

## License

MIT
