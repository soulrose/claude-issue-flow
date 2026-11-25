---
name: plan-issue
description: Step 1 - read a GitLab / GitHub issue (URL or number) with its comments and the code it touches, then write an implementation plan for the user to review. Changes no code and nothing on the server. Runs only when the user types /plan-issue.
argument-hint: "766 (เลข issue) หรือลิงก์ issue"
disable-model-invocation: true
---

# /plan-issue <issue URL | number>

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Helper: `.claude/scripts/issue-flow.cmd <command> <issue URL or number>` from the repo root. Never print, ask for or paste the token.

1. Argument = issue URL (`https://<host>/<group>/<project>/…/issues/<n>`) or number; if missing, ask. If the URL's project is not this repo's `origin`, say so and stop (open Claude in that project's folder).
2. `.claude/scripts/issue-flow.cmd issue <URL or number>` → read title, description, labels (`Type:`), due date, and the comments (later comments can change what is asked).
3. Read the code the issue touches — read only: do not edit, create or delete files, do not run builds, do not touch git branches.
4. Write the plan, short and concrete:
   - **เป้าหมาย** — 1-2 sentences of what "done" means.
   - **สิ่งที่จะแก้** — per file: what changes and why (new files marked as new).
   - **การทดสอบ** — tests to add or change (tagged if CLAUDE.md asks for it: `@Tag("issue-<n>")` + `@Tag("TC-<n>-<nn>")` per test method — list the TC numbers in the plan), which existing tests must still pass, and how to check by hand (endpoint / GraphQL query, sample input, expected output).
   - **ผลกระทบ / ความเสี่ยง** — callers affected, data / migration, behaviour changes others will notice.
   - **คำถาม** — anything the issue leaves unclear (empty if none). Never guess silently.
5. Save it to `<git-dir>/claude-flow/plan-<n>.md` (`git rev-parse --git-dir`; create the folder), starting with `status: draft`, the issue URL and the date.
6. Ask with AskUserQuestion: "แผนนี้โอเคไหม?" — อนุมัติ / แก้แผน / ยกเลิก.
   - แก้แผน: ask what to change (or answer the open questions), update the plan and the file, ask again.
   - อนุมัติ: set `status: approved` in the file. Next step for the user: `/implement`.
