# Manual

[ภาษาไทย](manual.th.md) · [README](../README.md)

## The flow

| Step | You type | Claude does | You answer |
|---|---|---|---|
| 0 | `/setup-flow` (once per repository) | Creates `.claude/issue-flow.json`, checks server, labels, test commands and token | Reviewer, labels, commands |
| 1 | `/plan-issue 766` | Reads the issue, comments and code. Writes a plan to `.git/claude-flow/`. Changes nothing | Approve, change or cancel |
| 2 | `/implement` | In-progress label, branch, Draft MR (GitLab). Codes the plan with tests | Start or cancel |
| 3 | `/submit-review` | Reviews its own change, runs tests, commits, pushes, opens the MR / PR or marks it ready | Ready or Draft, then confirm |
| 4 | `/fix-review` (if rejected) | Reads unresolved comments, back to Draft, fixes each one | Confirm |

In plugin form the names start with `issue-flow:`, for example `/issue-flow:plan-issue 766`.

Options: `/implement 766 setup` prepares the branch and lets you code. `/submit-review draft` pushes without asking for review. `/merge-base` merges the base branch locally.

## What Claude may do

| | |
|---|---|
| Read issue, code, diff | without asking |
| Edit code, commit, push, labels, MR / PR | only after you confirm |
| `--force`, `--no-verify`, merging the MR / PR, sending messages | never |

A review or test result counts only for the exact code it was made on. Committing keeps it valid. Any edit makes it stale.

## Quality rules of `/implement`

1. Fix the root cause, not the symptom.
2. Make the smallest change the plan needs.
3. Validate input at the boundary.
4. Test behaviour. For bugs, write the failing test first.
5. Work one plan item at a time and run its tests.
6. Check the real thing before saying done, and say so when that was not possible.
7. Read your own diff last.

If the [superpowers](https://github.com/obra/superpowers) plugin is installed, Claude also uses its TDD, debugging and verification skills. These rules win when they conflict.

## Tests

| Stack | Found by | Related tests run with |
|---|---|---|
| Maven, Gradle | `pom.xml`, `build.gradle(.kts)` | `-Dtest=…`, `--tests` |
| Node | `package.json` | Vitest, Jest or Mocha on the matching files |
| Python | `pyproject.toml`, `pytest.ini`, `setup.py`, `requirements.txt` | `pytest` on the matching files |
| Go | `go.mod` | `go test` on the changed packages |
| .NET | `*.csproj`, `*.sln` | `dotnet test --filter` |
| PHP, Ruby | `composer.json`, `Gemfile` | PHPUnit, RSpec |
| Rust | `Cargo.toml` | `cargo test` (all) |

Each changed file belongs to the nearest folder with a build file, so a mixed repository gets one run per folder. Set `tests.related`, `tests.all` and `tests.issue` in `issue-flow.json` to use your own commands.

## Troubleshooting

| You see | Do |
|---|---|
| `No token for <host>` | Run `set-token` (see README) |
| `401` | Token expired or revoked. Create a new one and run `set-token` again |
| `403` / `404` on GitHub | The token lacks access to this repository, or a permission (Contents, Issues, Pull requests) |
| `422` when opening a Draft on GitHub | Your plan has no draft PRs for this repository. Use `/submit-review` without `draft` |
| `User @x not found` | Use the username, not the display name |
| `The issue is on … but this repo uses …` | Open Claude in the repository the issue belongs to |
| Wrong server type | Set `provider` in `issue-flow.json` |
