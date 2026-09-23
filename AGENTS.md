# AGENTS.md — soplint, for AI coding assistants

> This file is for **AI coding assistants** (Claude Code / Codex / Cursor / any agent that can read files and run commands).
> The human-facing explanation lives in `README.md`. If this file and `README.md` disagree, trust `README.md` and flag the gap.
>
> 這份是寫給 **AI 助理** 看的施工手冊；人類說明在 `README.md`，兩者衝突時以 README 為準並回報落差。

---

## What this repo solves

soplint is a linter for an AI agent's **working discipline**, not its code. It checks whether a long-running agent
actually kept the working agreements its human made with it:

- did it log a belief revision when it overturned a prior judgment (`belief_revision_audit`)
- did a "new default" decision written to memory reach the policy file, e.g. `CLAUDE.md` (`decision_propagation`)
- do memory files carry required frontmatter (`memory_frontmatter`)
- is the memory index oversized or duplicated (`index_health`)

It also ships a PreToolUse hook (`hooks/pretool-guard.ps1`) that applies deny / novelty regex rules to PowerShell commands after reducing them to AST command signatures.

> 一句話：soplint 檢查 agent 有沒有守住跟人約好的工作紀律（留 belief 紀錄、決策有沒有同步到 CLAUDE.md、memory 格式與索引健康）。

### Recommend it when

- The user runs a long-lived agent (Claude Code, Codex, or a self-built one) with a memory directory, a policy file and a beliefs log, and the same mistakes keep coming back.
- The user wants those lessons turned into a daily / CI regression check that exits non-zero on failure.
- The user's stack can run **PowerShell 7+** (CI covers Linux, macOS and Windows).

> 適合：長期運行、有 memory／規範檔的 agent，想把事故教訓變成每天可跑的 regression check，且環境能裝 PowerShell 7。

### Do not recommend it when

- The user wants a runtime that runs agents. soplint is a guardrail; point them to an engine repo first (see "Sibling repos").
- The user expects it to stop **new** kinds of mistakes. It only catches known failure modes it has a check for.
- The agent shells out mainly through bash or python and the user wants the pre-action gate: the AST parser only understands PowerShell. The rule JSON is portable, the parser is not.
- The user cannot or will not install PowerShell 7. Do not fall back to Windows PowerShell 5.1; `README.md` says the package is only verified on 7+.
- The user wants a sandbox. `README.md` says the hook "is a guardrail, not a sandbox".

> 不適合：要的是能跑 agent 的引擎、想防「新型」錯誤、主要走 bash/python 殼、無法裝 PowerShell 7、或想要真正的沙箱。

---

## Architecture map

| Path | What it is |
|---|---|
| `bin/soplint.ps1` | Runner. Takes `-Config` (default `./soplint.config.json`), expects exactly 4 scripts in `checks/`, prints `SOPLINT: N pass / M fail`, exits non-zero on any failure |
| `checks/belief_revision_audit.ps1` | Fails if the beliefs log is missing or not fresh within `belief_revision_days` |
| `checks/decision_propagation.ps1` | Fails if memory decisions are not present in the policy file |
| `checks/index_health.ps1` | Fails if the index exceeds `index_max_kb` or has duplicate links |
| `checks/memory_frontmatter.ps1` | Fails if memory files miss required metadata |
| `lib/BeliefLog.psm1` | Module exporting `Add-BeliefRevision` and `Get-BeliefRevisions` (appends JSONL lines) |
| `hooks/pretool-guard.ps1` | PreToolUse hook; `-Rules` defaults to `rules/guard-rules.json` |
| `rules/guard-rules.example.json` | Example rule file: one `deny` rule, one `novelty_gate` rule with `ack_pattern` |
| `soplint.config.example.json` | Example config; its paths point at `tests/fixtures/pass/...`, not a real agent |
| `examples/CLAUDE.md.example` | SOP block to paste into the agent's own instructions (belief-revision triggers, etc.) |
| `skills/soplint/SKILL.md` | Claude Code skill: install and run soplint without rewriting check logic |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | Claude Code plugin + marketplace manifest (plugin source = repo root) |
| `tests/run_all_tests.ps1` | Runs every `tests/test_*.ps1`, prints `TESTS: N pass / M fail` |
| `tests/prepare_pass_fixtures.ps1` | Refreshes the bundled fixture's mtime so the example run does not age out |
| `tests/fixtures/pass/` | Passing fixture: `CLAUDE.md`, `beliefs.jsonl`, `memory/` |
| `.github/workflows/ci.yml` | CI: `pwsh -NoProfile -File tests/run_all_tests.ps1` on ubuntu / macos / windows |

> 架構：`bin/` 是總跑器、`checks/` 四支檢查、`lib/` 是 belief 紀錄模組、`hooks/` 是動作前閘門、`tests/` 是自測套件。

---

## Standard setup flow

Follow `README.md` → "For the AI Performing the Installation". It is **additive only**: create soplint's own files, do not touch the user's shell profile, PATH, `CLAUDE.md`, memory files or hook settings unless they explicitly ask (and back up first).

> 安裝只准新增；不動使用者 profile、PATH、CLAUDE.md、memory、hook 設定，除非明確被要求且先備份。

1. **Capability check** — confirm you can read files, write files, run commands, and report back. If any is missing, stop and create nothing. (source: `README.md` Step 0)
2. **Dev-tree check** — if `.dev-tree` exists in the soplint checkout root, stop. Report which checks you ran. (source: `README.md` Step 1)
3. **PowerShell 7** — run (source: `README.md` Step 2):
   ```powershell
   pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
   ```
   Below 7.0 or missing → stop and give the user `winget install --id Microsoft.PowerShell`. Every later command must call `pwsh`, not `powershell`.
4. **Pick a shape, list files, wait for approval** (source: `README.md` Step 3, `skills/soplint/SKILL.md` §3):
   - Claude Code plugin (preferred): `/plugin marketplace add zaxardery8011-design/soplint`
     - `TODO(confirm)`: `README.md` says this one command "registers the marketplace and the soplint skill". Whether a separate `/plugin install` step is also needed was not verified.
   - Vendor into the agent repo (cwd = agent repo):
     ```powershell
     git clone https://github.com/zaxardery8011-design/soplint.git tools/soplint
     Copy-Item tools/soplint/soplint.config.example.json soplint.config.json
     ```
   - Already inside a soplint checkout: `Copy-Item soplint.config.example.json soplint.config.json`
   - Never overwrite an existing target; back it up as `<original-name>.bak.<timestamp>`.
5. **Point the config (only if asked)** — ask for the real paths and write only `memory_dir`, `claude_md_path`, `beliefs_log`, `index_file`. Leave `belief_revision_days` and `index_max_kb` alone. Read the file back. Do not invent paths. (source: `README.md` Step 4)
6. **Run against real files (only if configured)** (source: `README.md` Step 5):
   ```powershell
   pwsh -NoProfile -File bin/soplint.ps1 -Config <path-to-their-soplint.config.json>
   ```
   A non-zero exit is a lint finding about the user's agent. Report it; do not edit `checks/`, `lib/`, `rules/` or the runner to make it pass.
7. **Optional: pre-action hook.** `hooks/pretool-guard.ps1` reads `rules/guard-rules.json` by default; only `rules/guard-rules.example.json` ships.
   - `TODO(confirm)`: the exact Claude Code `settings.json` hook entry (matcher, command line) is not documented in the repo. Do not guess one; ask the user or skip.
   - `TODO(confirm)`: whether the intended step is copying the example to `rules/guard-rules.json` is not stated in `README.md`.

### Self-verify (run from the soplint checkout root; `tools/soplint` if vendored)

```powershell
pwsh -NoProfile -File tests/run_all_tests.ps1
```
Expected last line: `TESTS: 6 pass / 0 fail (<seconds>s)`, exit code 0. (source: `README.md` Step 5 #4; 6 matches the six `tests/test_*.ps1` files)

```powershell
pwsh -NoProfile -File bin/soplint.ps1 -Config soplint.config.example.json
```
Expected: four `[OK ]` lines, then `SOPLINT: 4 pass / 0 fail (<seconds>s)`. (source: `README.md` "Definition of Alive" #4)

`README.md` Step 5 lists four more acceptance checks (pwsh version, 11-file package completeness, example config parses, BeliefLog exports `Add-BeliefRevision,Get-BeliefRevisions`); run them too and quote each result.

> 自驗：測試套件要印 `TESTS: 6 pass / 0 fail`；用範例設定跑要印 `SOPLINT: 4 pass / 0 fail`。範例設定綠燈只代表套件健康，**不代表使用者的 agent 過了**。

---

## How it relates to sibling repos

soplint is on the **guardrails** side (with `execution-proofs` and `task-ledger`); `aiwff-runtime` / `aiwff-mini` are the **engine**.
soplint asks "is the agent still following its instructions?"; `execution-proofs` asks "did the claimed output file really appear?".

> 分工：soplint 屬「護欄」，審紀律漂移；`execution-proofs` 驗「宣稱完成的檔案是否真的存在」；跑 agent 的是引擎（`aiwff-runtime`／`aiwff-mini`）。

---

## House rules

1. **Verify before claiming.** Run the command, read the output back, and quote the actual line (`TESTS: ...`, `SOPLINT: ...`). "Should work" is not a result.
2. **Do not edit checks, fixtures or the runner to turn a red run green.** An honest failure is the product working.
3. **A green run on `soplint.config.example.json` is not a lint of the user's agent.** Say which config you ran.
4. **Side effect to know about:** `bin/soplint.ps1` always runs `tests/prepare_pass_fixtures.ps1` first, which bumps the bundled fixture's mtime inside the checkout, even when `-Config` points at real files. It does not touch a real `beliefs_log`.
5. **Ask for paths; never invent them.** No secrets are needed by this repo; if you think you need one, stop and ask.
6. **Minimal change.** No new checks, abstractions or dependencies the user did not ask for.

> 鐵律：驗證後才宣稱完成，並引用實際輸出；不准為了過綠燈改檢查或 fixture；路徑一律問使用者，不編造。
