---
name: run-tests
description: Run the tests related to the changed files, plus the tests tagged issue-<n>, report real numbers and record the result for this exact code, so /submit-review does not run them again. Runs only when the user types /run-tests.
argument-hint: "[issue number] [all]"
disable-model-invocation: true
---

# /run-tests [number] [all]

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Tests: `related-tests` prints `runs` (one per project folder: `dir`, `command`, `all`) for Maven, Gradle, Node (Vitest / Jest / Mocha), Python, Go, Rust, .NET, PHP and Ruby, or the commands set in `issue-flow.json`. Run each `command` inside its `dir`; `command` empty = ask whether to run `all`; no runs = use the test command in CLAUDE.md / README, else ask.

Issue number: argument, else the leading digits of `git branch --show-current`.

1. Fingerprint = `.claude/scripts/issue-flow.cmd fingerprint`. If `<git-dir>/claude-flow/tests-<n>.json` has the same fingerprint and `"passed": true` → say the tests already passed for this exact code and stop, unless the user asked to run again.
2. Show what will run (the `runs` from `.claude/scripts/issue-flow.cmd related-tests`, or `all`, plus the issue tests) and ask: "รัน test? (<k> ชุด)" — รัน / ยกเลิก. When run as part of `/submit-review`, do not ask: the user already asked for the whole chain.
3. Related: run each `command` from `related-tests` (argument `all`: each `all`). Do not add a tag / group filter: it can skip untagged tests silently and still report success. A listed test file or class that ran 0 tests is a warning to show, never a pass.
4. Issue tests: `issue_command` with `<n>` / `{issue}` replaced by the number; empty → Maven with `@Tag("issue-<n>")` in CLAUDE.md: `mvn test "-Dgroups=issue-<n>" -DfailIfNoTests=false`; otherwise skip.
5. Report with real numbers (run / failed / skipped per run). No related tests or no `issue-<n>` tests → say so (warning, not a failure).
6. Failing → show which test and why (short), offer to fix. Fixing changes the code: the saved review becomes stale (`/review-changes` checks the fix).
7. Save `<git-dir>/claude-flow/tests-<n>.json`: `{ "iid": n, "fingerprint": "<fingerprint from step 1>", "at": "<ISO>", "passed": true|false, "runs": [ { "cmd": "...", "tests": 0, "failures": 0, "errors": 0, "skipped": 0 } ] }`. If code changed during this command, take the fingerprint again and run again instead of saving an old one.
8. Never commit or push.
