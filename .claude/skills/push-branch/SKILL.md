---
name: push-branch
description: Push the committed issue branch to origin (git push -u), without opening or changing an MR or any label. Never force, never skip hooks. Runs only when the user types /push-branch.
argument-hint: "[issue number]"
disable-model-invocation: true
---

# /push-branch [number]

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Issue number: argument, else the leading digits of `git branch --show-current`. Refuse on `<base>` / master / main.

1. Uncommitted tracked changes → say they will not be pushed; offer `/commit-changes` first.
2. Commits to push: `git fetch origin` → `git log --oneline origin/<branch>..HEAD` (or from `origin/<base>` if the branch is not on origin yet). None → say so and stop.
3. Status (do not block, just show): `review-status <n>` and the saved tests result vs `fingerprint`.
4. Ask once with AskUserQuestion, showing the commits: Push / ยกเลิก.
5. `git push -u origin <branch>` — never `--force` / `--force-with-lease`, never `--no-verify`. Rejected because the remote moved → show it, suggest `git pull --rebase` or `/merge-base`, and stop.
6. Report. No MR, no label change. Next: `/submit-review` (it uses the pushed branch).
