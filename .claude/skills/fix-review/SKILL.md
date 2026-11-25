---
name: fix-review
description: The reviewer rejected the MR (or a problem was found after shipping) - read the unresolved MR comments, put issue + MR back to "In progress" and Draft, fix each comment. No commit, no push. Runs only when the user types /fix-review.
argument-hint: "[issue URL or number]"
disable-model-invocation: true
---

# /fix-review [issue URL | number]

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Tests: `related-tests` prints `runs` (one per project folder: `dir`, `command`, `all`) for Maven, Gradle, Node (Vitest / Jest / Mocha), Python, Go, Rust, .NET, PHP and Ruby, or the commands set in `issue-flow.json`. Run each `command` inside its `dir`; `command` empty = ask whether to run `all`; no runs = use the test command in CLAUDE.md / README, else ask.

1. Issue number: argument, else the leading digits of the current branch; if neither, ask.
2. `.claude/scripts/issue-flow.cmd feedback <n>` (read-only) → show each unresolved comment: `file:line`, who, what. None → the user may describe the problem.
3. Ask: "ดึง #<n> กลับมาแก้? (issue + MR → In progress, MR กลับเป็น Draft)" — then `.claude/scripts/issue-flow.cmd reopen <n>`.
4. Uncommitted work → ask whether to stash. `git fetch origin` → `git checkout <branch>` → `git pull --ff-only`.
5. Fix each comment. If a comment looks wrong or unclear, say why and ask instead of changing code. Do not resolve or reply to MR threads — the reviewer does that.
6. Run the tests of the touched classes. Never commit or push. summary per comment (แก้แล้ว / ไม่แก้ เพราะ…). Next: `/submit-review`.
