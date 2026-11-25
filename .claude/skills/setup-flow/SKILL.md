---
name: setup-flow
description: One-time setup of the issue flow in a repository - create .claude/issue-flow.json, agree on base branch, labels, reviewer and test commands, check the token. Runs only when the user types /setup-flow.
disable-model-invocation: true
---

# /setup-flow

Confirm rule: ask with AskUserQuestion before writing a file. Never print, ask for or paste the token.

macOS / Linux: run `pwsh -NoProfile -File <the same folder>/issue-flow.ps1` with the same arguments instead of `issue-flow.cmd`.

Helper path: `.claude/scripts/issue-flow.cmd` in the repository; when it is not there (installed as a plugin) use `"${CLAUDE_SKILL_DIR}/../../scripts/issue-flow.cmd"`, always run from the repository root. Other commands named here are `${CLAUDE_SKILL_DIR}/../<name>/SKILL.md`.

1. No `.claude/issue-flow.json` → ask, then `.claude/scripts/issue-flow.cmd init`. It exists → show it.
2. Show the detected server and base branch, and the test commands from `related-tests` / the build files. Ask once about what is missing: default reviewer, status labels the team already uses, own test commands (`tests.related`, `tests.all`, `tests.issue`). Update the file.
3. Token: `.claude/scripts/issue-flow.cmd check`. "No token" → tell the person to run `set-token` themselves in a terminal (Windows with `.claude/` in the repository: double-click `.claude\setup-token.cmd`; as a plugin: show the full command with the resolved helper path, to be run from the repository root). The token never goes through this chat.
4. Report what is ready, and labels that do not exist yet (they are created on first use, if the person may create labels). Next: `/plan-issue <n>`.
