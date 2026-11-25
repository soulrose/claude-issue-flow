---
name: review-changes
description: Claude reviews the branch's own change against the base branch and the issue - bugs, security / personal data, transactions, missing tests - and records the result for this exact code, so /submit-review does not review it again. Changes code only if the user picks fix. Runs only when the user types /review-changes.
argument-hint: "[issue number]"
disable-model-invocation: true
---

# /review-changes [number]

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Issue number: argument, else the leading digits of `git branch --show-current`. Refuse on `<base>` / master / main.

1. `.claude/scripts/issue-flow.cmd review-status <n>`: `ok` → say this exact code was already reviewed (show the saved findings briefly) and stop, unless the user asked for a fresh review.
2. Diff = `git diff $(git merge-base origin/<base> HEAD)` + untracked files; the issue (`.claude/scripts/issue-flow.cmd issue <n>`) and `<git-dir>/claude-flow/plan-<n>.md` if present.
3. Look for, in order: bugs / not what the issue asks → security and personal-data privacy (exposure, missing auth, injection, secrets, logging personal data) → data and transactions (N+1, unbounded results, legacy HTTP calls inside a DB transaction, migrations) → missing tests. Focus by `Type:` label: Bug = root cause + a test that would have caught it; Change = all callers handled, old tests updated not deleted; New = contract, validation, edge / error tests; Enhancement = behaviour unchanged; Security = root cause + same pattern elsewhere. No style nits.
4. Show findings: ระดับ สูง / กลาง / ต่ำ · ไฟล์:บรรทัด · ปัญหา · แนะนำ. None → say so.
5. Any finding → ask with AskUserQuestion: แก้ที่แนะนำ (แนะนำ) / แก้เฉพาะข้อสูง / ไม่แก้. For each สูง left unfixed the user types the reason (saved as `decision: "skip"` + note). After fixing, review only the fix.
6. Save `<git-dir>/claude-flow/review-<n>.json` (create the folder): `{ "iid": n, "fingerprint": "<.claude/scripts/issue-flow.cmd fingerprint>", "at": "<ISO>", "findings": [ { "severity": "high|medium|low", "file": "...", "line": 0, "title": "...", "decision": "fixed|skip|open", "note": "..." } ] }` — taken after any fixes, so it matches the current code. Any code change later makes it stale.
7. Never commit or push. Next: `/run-tests` or `/submit-review`.
