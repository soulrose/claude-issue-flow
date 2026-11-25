---
name: implement
description: Step 2 - implement the approved /plan-issue - on the server set the issue to "In progress", create the issue branch from `<base>` and a Draft MR (team convention), check the branch out, write the code and tests, run the tests of what changed. With "setup": only the server + branch part, the person codes. No commit, no push. Runs only when the user types /implement.
argument-hint: "[issue number] [setup = เตรียม branch + Draft MR อย่างเดียว ไม่เขียนโค้ด]"
disable-model-invocation: true
---

# /implement [number] [setup]

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Tests: `related-tests` prints `runs` (one per project folder: `dir`, `command`, `all`) for Maven, Gradle, Node (Vitest / Jest / Mocha), Python, Go, Rust, .NET, PHP and Ruby, or the commands set in `issue-flow.json`. Run each `command` inside its `dir`; `command` empty = ask whether to run `all`; no runs = use the test command in CLAUDE.md / README, else ask.

`setup` (anywhere in the arguments) = prepare only: steps 1, 3 and 4, then stop — no plan needed, no code written. The person codes; next is `/submit-review`.

1. Issue number: the number in the arguments, else the leading digits of the current branch, else the newest `<git-dir>/claude-flow/plan-*.md`. If unclear, ask.
2. (Skipped with `setup`.) Plan: read `<git-dir>/claude-flow/plan-<n>.md`.
   - Missing or not `status: approved` → ask: "รัน /plan-issue ก่อน (แนะนำ)" / "ทำต่อโดยไม่มีแผน". Never invent an approval.
3. Uncommitted changes (`git status --porcelain`) that are not this issue's → ask whether to stash (`git stash push -u -m "before #<n>"`); never discard.
4. Branch name = `branch` from `.claude/scripts/issue-flow.cmd issue <n>`; existing MR: `.claude/scripts/issue-flow.cmd find-change <n>` (read-only).
   Ask once with AskUserQuestion: "เริ่ม implement #<n>? (issue → In progress, branch <name> + Draft MR <ใหม่ / เดิม> (GitHub: branch only) · reviewer @<name>)" — เริ่ม / ยกเลิก. With `setup` the question starts "เตรียม #<n> ให้เขียนโค้ดเอง?" instead.
   If the issue is already "Awaiting review", say it will go back to In progress. Then:
   - `.claude/scripts/issue-flow.cmd start <n>` — label In progress, branch on the server from `<base>`, Draft MR (assignee = you, reviewer from the reviewer setting, "Closes #<n>"); an existing branch / MR is reused, never duplicated. Use the `branch` and `change` (link) it prints; `change` is null on GitHub until `/submit-review` opens the PR, so never promise a PR there.
   - Local: already on that branch → `git pull --ff-only`. Else `git fetch origin` → `git checkout <branch>` (tracks origin; a local branch of that name that already exists is checked out, not recreated).
   - Report the MR link. With `setup`, stop here: tell the person the branch is checked out and ready, tests for this issue need `@Tag("issue-<n>")` + `@Tag("TC-<n>-<nn>")` if CLAUDE.md asks for it, and next is `/submit-review` when done (or `/implement` later to let Claude code from an approved plan).
5. Implement the plan, in the existing style, following CLAUDE.md. If the plan turns out wrong or incomplete, stop and say what differs before doing something else than planned.
   - Quality rules (inside the plan's scope; a rule that needs more than the plan → stop and ask):
     1. Root cause: trace to the first place it goes wrong and fix it there; a guard is a fix only when the state it handles is legitimate.
     2. Smallest change that does the job: no layer, abstraction or refactor the plan does not ask for.
     3. Validate input at the boundary (controller / resolver / external client); keep the logic inside simple.
     4. Test behaviour, not implementation: each new test must fail when the code is wrong. `Type: Bug` → write the failing test first, see it fail for the right reason, then fix.
     5. One plan item at a time: run its tests before the next.
     6. Before saying done, exercise the real thing when a local server is available (read-only request); anything that writes data → DEV / LOCAL only and ask first. Not possible → say it was not checked, never imply it was.
     7. Last, read your own `git diff` (and new files): remove dead code, debug output and comments that only repeat the code.
   - superpowers plugin (optional; not in the available skills → skip this block, the quality rules above are enough):
     - Use `superpowers:test-driven-development` for `Type: Bug` and new logic (not for config, mapping or wording changes), `superpowers:systematic-debugging` when a test fails unexpectedly or the cause is unclear, `superpowers:verification-before-completion` before step 6.
     - Do not use `brainstorming`, `writing-plans`, `executing-plans`, `subagent-driven-development`, `using-git-worktrees` or `finishing-a-development-branch` here: the approved plan (or the person's choice to go on without one) is the design, and `/submit-review` does the commit and push.
     - This file wins over any skill: ask first, no commit / push, stay inside the plan. TDD's "delete it and start over" applies only to code written in this run, never to the person's code or code already on the branch.
   - Tests from the plan, tagged if CLAUDE.md asks for it: `@Tag("issue-<n>")` (method or class) and on each new test method its own `@Tag("TC-<n>-<nn>")`, numbered from 01 per issue, never reused.
   - While coding run only the tests of what you changed. `/submit-review` runs all related tests.
6. Never commit or push (the Draft MR stays empty until `/submit-review` pushes; `/submit-review` then turns it into Awaiting Review or keeps it Draft). Finish with a summary: each plan item (ทำแล้ว / ยังไม่ทำ / ทำต่างจากแผน + why), files changed, test result, how to check by hand. Next: `/submit-review` (or ask for changes first).
