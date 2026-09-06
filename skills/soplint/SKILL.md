---
name: soplint
description: Install and run soplint, the discipline linter for AI agents. Use when adding soplint to an agent repo, writing soplint.config.json, or running belief-revision / decision-propagation / memory-frontmatter / index-health checks.
---

# soplint

Lint rules for your AI agent's discipline, not its code.

Do **not** rewrite check logic. Call the existing runner only:

```powershell
pwsh -NoProfile -File <soplint-checkout>/bin/soplint.ps1 -Config <path-to-soplint.config.json>
```

Installation is **additive only**: create this tool's own files. Do not edit the human's shell profile, `CLAUDE.md`, memory files, or hooks unless they explicitly asked and you backed the file up first.

## 1. PowerShell 7 first

Do not start an install you cannot finish. Confirm you can read files, write files, run commands, and report back. Then **actually run**:

```powershell
pwsh -NoProfile -Command '$PSVersionTable.PSVersion.ToString()'
```

If `pwsh` is missing or the version is below 7.0, **stop**. Tell the human: `winget install --id Microsoft.PowerShell`. Do not fall back to Windows PowerShell 5.1. Every later command must call `pwsh`, not `powershell`.

## 2. Do not install inside the author's tree

**Stop condition**: the marker file `.dev-tree` exists in the soplint checkout root. It is not committed; a normal `git clone` will not have it. If it matches, stop. Do not install somewhere else "helpfully".

Supporting signals (report them; they are not stop conditions on their own): path fragments like `open_source_prep/`; uncommitted local changes. A clone whose remotes point at this project's upstream is normal.

Report which checks you ran and which were outside your permissions. Silently skipping a check is not allowed.

## 3. Get a complete checkout, then write config

Ask which shape they want:

1. **Claude Code plugin** (preferred): `/plugin marketplace add zaxardery8011-design/soplint`. The plugin root **is** the soplint checkout.
2. **Vendor into an agent repo**: clone to `tools/soplint` inside that repo.
3. **Use an existing checkout**: if the path already contains `bin/soplint.ps1` and the other required files, do not clone again.

Vendor clone (current directory = the agent repo):

```powershell
git clone https://github.com/zaxardery8011-design/soplint.git tools/soplint
Copy-Item tools/soplint/soplint.config.example.json soplint.config.json
```

Already inside a soplint checkout:

```powershell
Copy-Item soplint.config.example.json soplint.config.json
```

Always: **list every file you will create, show the list, wait for approval, then act.** If the target already exists, do not overwrite; back it up as `<original-name>.bak.<timestamp>` and say what you backed up.

Do not create files outside the agreed destination. Do not touch PATH.

## 4. Fill `soplint.config.json` paths

The copied example still points at `tests/fixtures/pass/...`. That is a **package fixture**, not the human's agent.

Ask, then write only these four keys — do not invent paths, and do not change other keys (`belief_revision_days`, `index_max_kb`):

- `memory_dir`
- `claude_md_path`
- `beliefs_log`
- `index_file`

Read the file back for confirmation.

If they only wanted to prove soplint itself runs, leave the example paths and skip this step. A green run against the unedited example config is **not** a lint of the human's agent.

## 5. Run the checks once

From the soplint checkout root (plugin root, or `tools/soplint` if vendored):

```powershell
pwsh -NoProfile -File bin/soplint.ps1 -Config <path-to-their-soplint.config.json>
```

A non-zero exit is a lint finding against those files. Report it. Do not edit `bin/soplint.ps1`, `checks/`, `lib/`, or `rules/` to make it pass.

Optional package-health extras (not a substitute for the runner above): `tests/run_all_tests.ps1` should print `TESTS: 6 pass / 0 fail`; `bin/soplint.ps1 -Config soplint.config.example.json` should print `SOPLINT: 4 pass / 0 fail`.

## 6. Report pass/fail

Report in this order:

1. PowerShell 7 version you observed (or that you stopped because it was missing)
2. Which `.dev-tree` / path / dirty-tree checks you ran
3. Files created, and whether config points at fixtures or at the human's real files
4. The exact `bin/soplint.ps1` command and its pass/fail output
5. Anything you guessed, bypassed, or could not verify

If any item fails, say it failed and stop.
