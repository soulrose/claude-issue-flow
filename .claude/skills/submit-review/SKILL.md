---
name: submit-review
description: Step 3 - send the work to the reviewer - review (/review-changes), related tests (/run-tests), commit (/commit-changes), push (/push-branch), then turn the Draft MR from /implement into Awaiting Review (or keep it Draft with "draft"; opens the MR if none exists), skipping any step already done for this exact code. Never force, never skip hooks. Runs only when the user types /submit-review.
argument-hint: "[draft]"
disable-model-invocation: true
---

# /submit-review [draft]

Confirm rule: ask with AskUserQuestion before anything that changes git (branch, stash, commit, merge, push) or the server (GitLab / GitHub), and before starting to edit code; read-only steps do not ask. Never take silence or an earlier answer as yes for a new step.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Server: GitLab or GitHub, detected from `origin`. "MR" = merge request on GitLab, pull request (PR) on GitHub; say the one that fits. On GitHub a PR cannot exist before the first push, so `start` stops at the branch and `/submit-review` opens the PR.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

Settings: `.claude/issue-flow.json`; `<base>` below = its `baseBranch`. Thai phrases are the original labels: show every label, question and summary in the language the user writes in. Drop the `@Tag` rules unless CLAUDE.md has them.

Tests: `related-tests` prints `runs` (one per project folder: `dir`, `command`, `all`) for Maven, Gradle, Node (Vitest / Jest / Mocha), Python, Go, Rust, .NET, PHP and Ruby, or the commands set in `issue-flow.json`. Run each `command` inside its `dir`; `command` empty = ask whether to run `all`; no runs = use the test command in CLAUDE.md / README, else ask.

Issue number = leading digits of `git branch --show-current`. Refuse on `<base>` / master / main.
This command chains the smaller ones: read and follow the `SKILL.md` for each step, with the differences below. Inside this chain, the only questions are: open สูง review finding, failing tests, MR mode, and the one final confirm before commit / push / MR (no separate asks from the smaller commands). Each step that was already done for this exact code (same `fingerprint`) is skipped — say "ข้าม: …" so the user sees it.

1. **Review** — `review-changes`. `review-status <n>` = `ok` → skip. An open สูง blocks: ask แก้ก่อน (แนะนำ) / ส่งต่อโดยไม่แก้ (user types the reason, saved as `decision: "skip"` + note).
2. **Tests** — `run-tests` (related + `issue-<n>`). Saved `tests-<n>.json` with the current fingerprint and `passed: true` → skip. Failing blocks: show which, offer to fix (then the fix goes back through step 1).
3. **Commit** — `commit-changes` steps 1 and 3 (files and message), but do not ask yet. Nothing uncommitted → skip.
4. **MR mode** — argument `draft` → Draft; otherwise ask with AskUserQuestion: "เปิด MR แบบไหน?" — ส่งรีวิวเลย (Awaiting review) / Draft (ยังไม่ส่ง).
5. Ask once to confirm, showing: files, commit message, commits to push, MR mode, review overrides. Ship / แก้ข้อความ / ยกเลิก.
6. `git add <files>` → `git commit` (if step 3 had files) → `git push -u origin <branch>` (if anything to push; never `--force`, never `--no-verify`; if a hook blocks, show why and fix) → `.claude/scripts/issue-flow.cmd open-change <n> [--draft]` (creates the MR, or updates the existing one, and sets the labels).
7. Report: commit, MR link, which steps were skipped, review overrides if any. When sent for review, give a message to paste in the team chat (do not send it): `ฝากรีวิวด้วยครับ #<n> <title>` + MR link.
