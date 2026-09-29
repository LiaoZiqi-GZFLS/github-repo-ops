# github-repo-ops

A Qoder skill that runs `git` and `gh` operations as the GitHub account declared in a
local **account document**, instead of whatever account `gh` happens to have active.

## Why this exists

`gh` holds one *active* account per host. Any script that shells out to `git` or `gh`
silently acts as that account. On a machine with more than one identity — personal plus
work, or a client account — a push can go out under the wrong name, and the commit author
can be wrong too.

This skill makes the identity explicit: it resolves the declared account from a document
you control, verifies it is authenticated, and refuses to proceed if it cannot.

## What it handles

| Task | Examples |
| --- | --- |
| Create repositories | `gh repo create`, `git init`, first push |
| Clone / pull / sync | `gh repo clone`, `git fetch --prune`, `git pull --ff-only` |
| Commit / push | staging, commit messages, `push -u`, branch tracking |
| Branch / PR | `switch -c`, `gh pr create` |
| Tag / release | annotated tags, `gh release create` |
| Inspect | `gh repo view`, `gh pr list`, `gh run list` |

Every operation runs as the resolved account, with the commit identity bound into the
repository first.

## Install

Requirements: `git` and `gh` on `PATH`, with `gh` already authenticated
(`gh auth login`).

Copy this directory into one of:

- user level — `~/.qoder-cn/skills/github-repo-ops/`
- project level — `<project>/.qoder/skills/github-repo-ops/`

Then run `/skills reload` (or restart the session) and invoke `/github-repo-ops`, or just
describe the task — the skill triggers on GitHub repository operations.

## The account document

The single source of truth for which identity to act as. Read from `$GH_ACCOUNT_DOC` if
set, otherwise `$HOME/.qoder-cn/github-account.md` (`%USERPROFILE%\.qoder-cn\github-account.md`
on Windows).

It is Markdown, so prose is fine — only `key = value` lines are parsed.

```ini
host = github.com
account = octocat
git_name = Octo Cat
git_email = 583231+octocat@users.noreply.github.com
protocol = https
default_visibility = private
bind_scope = local
```

| Key | Required | Default | Meaning |
| --- | --- | --- | --- |
| `host` | yes | — | `github.com`, or an enterprise hostname |
| `account` | yes | — | The `gh` login to act as; must appear in `gh auth status` |
| `git_name` | yes | — | `user.name` written into repositories before committing |
| `git_email` | yes | — | `user.email` written into repositories before committing |
| `protocol` | no | `https` | `https` or `ssh` — determines the remote URL form |
| `default_visibility` | no | `private` | `public`, `private`, or `internal` |
| `bind_scope` | no | `local` | `local` or `global` — where `bind` writes the identity |

Full schema, quoting rules, and CRLF handling: [`references/account-format.md`](references/account-format.md).

Adding a second account is a one-time interactive step you run yourself:

```bash
gh auth login --hostname github.com --git-protocol https
```

## Usage

The helper is the entry point. It is safe to call directly:

```bash
bash scripts/gh-account.sh show           # print the resolved settings
bash scripts/gh-account.sh check          # validate config, git/gh, and gh auth
bash scripts/gh-account.sh check --no-switch   # strictly read-only probe
bash scripts/gh-account.sh bind <dir>     # write the commit identity into <dir>
```

`check` switches the active `gh` account when another one is active, then reports what it
did. Its stdout is the authoritative statement of which identity is in use.

| Exit | Meaning | What to do |
| --- | --- | --- |
| 0 | Resolved | Proceed |
| 2 | Account document missing | Create it from the template above |
| 3 | Account document invalid | Fix the reported key |
| 4 | `git` or `gh` missing | Install it |
| 5 | Not logged in, or token rejected | `gh auth login`, or `gh auth refresh` |
| 6 | Switch failed | Check the account name against `gh auth status` |
| 7 | Not a git repository | `git init` first, for `bind` |
| 8 | Credentials unverifiable | Transient network/proxy problem — retry, do not re-authenticate |

## Safety rules the skill enforces

It asks for your agreement before anything that reaches shared state or destroys work:

- `git push`, including a repository's first push
- `gh repo create`, `gh pr create`, `gh pr merge`, `gh release create`, pushing a tag
- force-push, history rewrite, branch deletion, `git reset --hard`, `git clean`

And it never, short of an explicit instruction to do exactly that:

- force-pushes to `main` or `master`
- uses `--no-verify` to bypass a hook
- writes `git config --global` unless the document sets `bind_scope = global`
- echoes a token or embeds one in a remote URL
- runs `gh auth login` unattended — that flow is interactive and yours to run

## Notes

`gh auth status` reports **"The token in keyring is invalid"** whenever the GitHub API call
fails for *any* reason, including a network blip — it conflates "could not verify" with
"rejected". This skill reads the per-account `state` and `error` fields instead, which stay
readable offline, and separates the two cases: a transient failure exits 8 (retry), a real
rejection exits 5 (re-authenticate). Trust the exit code, not `gh`'s wording.

## Layout

```
SKILL.md                        instructions the agent follows
scripts/gh-account.sh           account resolver: show / check / bind
references/account-format.md    account document schema and template
```

## License

[MIT](LICENSE) © 2026 LiaoZiqi-GZFLS
