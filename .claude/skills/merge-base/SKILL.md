---
name: merge-base
description: Bring the latest origin/<base> into the checked-out issue branch locally: refuses with uncommitted work, aborts cleanly on conflicts unless the user wants help resolving, never pushes. Runs only when the user types /merge-base.
disable-model-invocation: true
---

# /merge-base

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Tests: `related-tests` prints `runs` (one per project folder: `dir`, `command`, `all`) for Maven, Gradle, Node (Vitest / Jest / Mocha), Python, Go, Rust, .NET, PHP and Ruby, or the commands set in `issue-flow.json`. Run each `command` inside its `dir`; `command` empty = ask whether to run `all`; no runs = use the test command in CLAUDE.md / README, else ask.

1. `git branch --show-current`. Refuse on `<base>` / `master` / `main`.
2. Uncommitted work: `git status --porcelain`. Tracked files that are modified block the merge — tell the user to ship (`/submit-review`) or stash first, and stop. Untracked files and local-only config (`*-local.properties`, `*-local.yml`, `.env*`, `.idea/`, `*.iml`, `target/`) do not block; git itself refuses if the merge would overwrite them.
3. `.claude/scripts/issue-flow.cmd base-behind` → if `behind` is 0, say the branch already has everything from `<base>` and stop.
4. Show `git log --oneline HEAD..origin/<base>` (at most 15 lines) and ask with AskUserQuestion: "Merge <base> (<n> commit) เข้า <branch> ในเครื่อง? (ยังไม่ push)" — Merge / ยกเลิก.
5. `git merge --no-edit origin/<base>`.
6. Conflict (`git diff --name-only --diff-filter=U` lists files):
   - Show the conflicted files and ask: "ยกเลิก merge (แนะนำ)" / "ให้ Claude ช่วยแก้ conflict".
   - ยกเลิก: `git merge --abort`, confirm with `git status` that the branch is back as before, tell the user to resolve in IntelliJ if they prefer.
   - ช่วยแก้: for each file read both sides, keep both intents (the issue's change and the base branch's change); when unsure ask instead of guessing. Show a short per-file summary of what was kept, run the related tests (`.claude/scripts/issue-flow.cmd related-tests`), then `git add` the files and `git commit --no-edit`.
7. Never push. Report: commits brought in, merge commit, test result if run. Remind: the code changed; `/submit-review` reviews and tests it again before sending.
