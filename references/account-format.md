# GitHub account document — format reference

The account document is the single source of truth for *which* GitHub identity this
skill acts as. The script `scripts/gh-account.sh` reads it before every operation.

## Location

| Order | Path |
| --- | --- |
| 1 | `$GH_ACCOUNT_DOC` (environment override, if set) |
| 2 | `$HOME/.qoder-cn/github-account.md` — on Windows, `%USERPROFILE%\.qoder-cn\github-account.md` |

The file is Markdown, so prose notes for humans are welcome and ignored by the parser.
The parser only reads `key = value` lines; everything else is commentary.

## Keys

| Key | Required | Default | Meaning |
| --- | --- | --- | --- |
| `host` | yes | — | GitHub host. `github.com`, or the enterprise hostname. |
| `account` | yes | — | The gh login of the account to act as. Must appear in `gh auth status`. |
| `git_name` | yes | — | `user.name` written into repositories before committing. |
| `git_email` | yes | — | `user.email` written into repositories before committing. |
| `protocol` | no | `https` | `https` or `ssh` — determines the remote URL form. |
| `default_visibility` | no | `private` | `public`, `private` or `internal` — used when creating repositories. |
| `bind_scope` | no | `local` | `local` or `global` — where `bind` writes the commit identity. |

Rules enforced by the script:

- Keys are matched case-insensitively on the left of the first `=` of a line.
- A value may be wrapped in double quotes; the quotes are stripped.
- CRLF line endings and trailing whitespace are tolerated (Windows-safe).
- Missing required key, or a value outside the allowed set, aborts with exit code 3.
- Comment lines (`# ...`) are ignored.

## Template

```ini
host = github.com
account = <gh-login>
git_name = <commit author name>
git_email = <commit author email>
protocol = https
default_visibility = private
bind_scope = local
```

## Example, filled in

```ini
host = github.com
account = octocat
git_name = Octo Cat
git_email = 583231+octocat@users.noreply.github.com
protocol = https
default_visibility = private
bind_scope = local
```

Using the GitHub noreply address as `git_email` keeps the real mailbox out of public
commit metadata. The address is
`<numeric-id>+<login>@users.noreply.github.com`; read the numeric id from
`https://api.github.com/users/<login>` (`.id`) if it is unknown.

## Granting access to a newly declared account

`gh` can only switch between accounts it already holds. A new account must be added
once, interactively, by the user:

```bash
gh auth login --hostname <host> --git-protocol <protocol>
```

This prompts for a browser flow. Never run it unattended — the script fails with
exit code 5 and prints this command instead of attempting it.
