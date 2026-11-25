# claude-issue-flow

[Manual](docs/manual.en.md) · [คู่มือภาษาไทย](docs/manual.th.md)

Slash commands for [Claude Code](https://claude.com/claude-code) that take a **GitLab or GitHub** issue to a reviewed merge request / pull request. Claude asks before it changes git or the server. Nothing runs unless you type the command.

```
/plan-issue 766  →  /implement  →  /submit-review
```

| Command | What it does |
|---|---|
| `/setup-flow` | Once per repository: settings, labels, test commands, token check. |
| `/plan-issue 766` (number or link) | Reads the issue, its comments and the code, then writes a plan for you to approve. Changes nothing. |
| `/implement` | In-progress label, branch and (GitLab) Draft MR. Checks the branch out and codes the approved plan. No commit, no push. |
| `/implement 766 setup` | Only the label and branch part. You write the code. |
| `/submit-review [draft]` | Self-review, tests, commit, push, then opens the MR / PR or marks it ready for review. |
| `/merge-base` | Merges the latest base branch into yours, locally. |
| `/fix-review` | Reads unresolved review comments, puts the MR / PR back to Draft and fixes them. |
| `/read-issue` `/review-changes` `/run-tests` `/commit-changes` `/push-branch` | Single steps. |

Reviews and test results are tied to a fingerprint of the code, so `/submit-review` skips a step already done for exactly this code.

## GitLab and GitHub

| | GitLab | GitHub |
|---|---|---|
| Detected from `origin` | any other host | host contains `github` |
| Draft opened | at `/implement` | at `/submit-review draft` (a PR needs a commit first) |
| Draft on private repos | yes | depends on your GitHub plan |
| Reviewer | anyone with access | not the PR author (skipped) |

## Install

**As a plugin** (commands are named `/issue-flow:plan-issue` and so on):

```
/plugin install issue-flow --marketplace soulrose/claude-issue-flow
```

**Or copied into the repository**, so the whole team gets it with `git pull`: copy `.claude/` to the root of your repository. If you already have `.claude/settings.json`, merge it by hand.

Then, in your repository:

1. Run `/setup-flow` (plugin: `/issue-flow:setup-flow`).
2. Check `.claude/issue-flow.json`:

| Key | Meaning |
|---|---|
| `provider` | `gitlab` or `github`. Empty = detected. Set it for a self-hosted GitHub whose name does not contain `github`. |
| `host` | Server. Empty = taken from `git remote origin`. https only. |
| `baseBranch` | Target branch. Empty = the default branch of `origin`. |
| `defaultReviewer` | Username. Empty = no reviewer. |
| `labels` | Status labels put on the issue and MR / PR. `prefix` = labels that get replaced when the status changes. |
| `tests` | Your own `related`, `all` and `issue` commands (`{issue}` = number). Used when `all` is set. Empty = detected. |

3. Each person saves a personal access token once:
   - GitLab: scope `api`.
   - GitHub: fine-grained token for the repository with **Contents, Issues and Pull requests: read and write**.
   - Windows, copied install: double-click `.claude\setup-token.cmd`
   - Terminal: `.claude/scripts/issue-flow.cmd set-token` (macOS / Linux: `pwsh -NoProfile -File .claude/scripts/issue-flow.ps1 set-token`). Plugin: `/issue-flow:setup-flow` shows the full command.

   The token is stored outside the repository as plain text in `~/.config/issue-flow/token-<host>.txt`, one file per host. Never paste it into a chat.
4. Check: `.claude/scripts/issue-flow.cmd check`

## Requirements

- Git and Claude Code.
- Windows: the built-in PowerShell 5.1. macOS / Linux: PowerShell 7 (`pwsh`).
- Related tests: Maven, Gradle, Node, Python, Go, Rust, .NET, PHP, Ruby, or your own commands.

## Status

`node test/run.cjs` runs the helper against mock GitLab and GitHub servers and sample projects of every stack. The workflow in `.github/workflows` does this on Windows, Linux and macOS. Real servers have seen little use so far: try it on a test project first.

Commands answer in the language you write in. In the copied install, read-only commands are pre-approved and `git push --force` / `--no-verify` are denied in `.claude/settings.json`. A plugin cannot ship permissions, so Claude Code asks more often there.

## License

[MIT](LICENSE)
