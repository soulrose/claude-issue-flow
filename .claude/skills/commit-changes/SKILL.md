---
name: commit-changes
description: Commit the current issue work locally with a Conventional Commit message the user confirms, leaving out local-only and sensitive files. No push, no MR. Runs only when the user types /commit-changes.
argument-hint: "[issue number]"
disable-model-invocation: true
---

# /commit-changes [number]

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Issue number: argument, else the leading digits of `git branch --show-current`. Refuse on `<base>` / master / main.

1. Files from `git status --porcelain`, leaving out local-only / sensitive ones (`*-local.*`, `.env*`, `.idea/`, `*.iml`, `target/`, credentials, anything that looks like a key or token). Nothing left → say so and stop.
2. Status (do not block, just show): `review-status <n>` and `<git-dir>/claude-flow/tests-<n>.json` vs `fingerprint` — e.g. "ยังไม่ได้รีวิว / test ยังไม่ได้รัน กับโค้ดชุดนี้".
3. Message in Conventional Commits, English, like `git log --oneline -10`: `<type>(<scope>): <summary> (#<n>)` (< 72 chars), blank line, 2-5 bullets.
4. Ask once with AskUserQuestion, showing the files left in / out and the message: Commit / แก้ข้อความ / ยกเลิก.
5. `git add <files>` → `git commit` (never `--no-verify`; if a hook blocks, show why and fix).
6. Report the commit hash. Never push. Next: `/push-branch` or `/submit-review`.
