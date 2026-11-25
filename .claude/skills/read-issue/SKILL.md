---
name: read-issue
description: Read a GitLab / GitHub issue (URL or number) with its comments and summarize it - what is asked, what is unclear. No plan, no code changes, nothing written to the server. Runs only when the user types /read-issue.
argument-hint: "766 (เลข issue) หรือลิงก์ issue"
disable-model-invocation: true
---

# /read-issue <issue URL | number>

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Helper: `.claude/scripts/issue-flow.cmd <command>` from the repo root. Never print, ask for or paste the token.

1. Argument = issue URL or number; if missing, ask. If the URL's project is not this repo's `origin`, say so and stop.
2. `.claude/scripts/issue-flow.cmd issue <URL or number>` (read-only).
3. Summarize, short:
   - **หัวข้อ / ประเภท / กำหนดส่ง / สถานะ** (labels, assignee, milestone)
   - **ต้องทำอะไร** — what is asked, in bullets; later comments override earlier text, say when they do
   - **ยังไม่ชัด** — questions to ask the issue author (empty if none)
   - **branch** — the name `/implement` will use, and whether it already exists on origin (`git ls-remote --heads origin <name>`)
4. Change nothing. Next: `/plan-issue <n>` for a plan, or ask questions.
