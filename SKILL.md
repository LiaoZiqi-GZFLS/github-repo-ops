---
name: github-repo-ops
description: Create, clone, pull, sync, commit, push, branch, tag, release, and open pull requests on GitHub using git and gh as the account declared in the user's account document. Use when asked to create a GitHub repository, push local code to GitHub, clone or sync a remote, commit and push changes, open or merge a PR, cut a release, or whenever a git/gh operation must run as a specific GitHub account rather than whatever gh happens to have active.
---

# GitHub Repository Operations as a Declared Account

## Overview

Every git and gh operation in this skill runs as the GitHub account declared in one
document — the **account document**. Never assume the currently active `gh` account is
the right one, and never fall back to a personal account because it is convenient.
Resolve the identity first, then act.

- Account document: `$GH_ACCOUNT_DOC`, else `$HOME/.qoder-cn/github-account.md`
  (on Windows: `%USERPROFILE%\.qoder-cn\github-account.md`).
- Field schema: `references/account-format.md`.
- Helper: `<skill-dir>/scripts/gh-account.sh`, where `<skill-dir>` is the base directory
  this SKILL.md was loaded from.

## Step 1 — Resolve the account (mandatory, before any git/gh write)

```bash
bash "<skill-dir>/scripts/gh-account.sh" check
```

It reads the document, checks `git` and `gh` exist, verifies the declared account is
authenticated, and switches the active `gh` account to it when another one is active.
Add `--no-switch` for a strictly read-only probe.

| Exit | Meaning | What to do |
| --- | --- | --- |
| 0 | Resolved | Print the resolved identity, then proceed. |
| 2 | Document missing | Show the user the template from `references/account-format.md` and ask them to create the file. Do not invent an account. |
| 3 | Document invalid | Report the offending key and ask the user to fix the document. |
| 4 | `git` or `gh` missing | Report it; do not install anything without asking. |
| 5 | Not logged in, or token rejected | Print the `gh auth login` / `gh auth refresh` command the script suggests and ask the user to run it themselves — login is interactive. |
| 6 | Switch failed | Report the active vs declared account; ask the user before retrying. |
| 8 | Credentials exist but could not be verified | The GitHub API is unreachable (network or proxy). Transient — report it and retry; do **not** re-authenticate and do **not** fall back to another account. |

Do not run a write operation if `check` did not exit 0.

`gh auth status`'s own exit code and its "The token in keyring is invalid" wording are
unreliable: gh prints that same message when the API call merely fails, so a network blip
looks exactly like a revoked token. The script instead reads the per-account `state` and
`error` fields from `gh auth status --json hosts`, which stay readable offline. Trust the
script's exit code over gh's prose.

## Step 2 — Bind the commit identity

Repositories must commit under the document's identity, not whatever the global config
says:

```bash
bash "<skill-dir>/scripts/gh-account.sh" bind <repo-dir>
```

Writes `user.name` and `user.email` into that repository's local config. It follows
`bind_scope` from the document; override with `--local` or `--global`. Default to local —
a global write affects every repository on the machine, so use `--global` only when the
user asks or the document says so.

Binding does not rewrite existing commits. If a repository already has commits under the
wrong identity, tell the user and ask before rewriting history.

## Step 3 — Build remote URLs from the document

- `protocol = https` → `https://<host>/<owner>/<repo>.git`. `gh` injects the token; never
  print it and never put it in a URL.
- `protocol = ssh` → `git@<host>:<owner>/<repo>.git`. Ensure the key is loaded first.

Prefer `gh repo clone` / `gh repo create --remote`, which apply the `gh` protocol config
automatically, over hand-written URLs.

## Operation recipes

Run every command with an explicit working directory (`git -C <dir>`) and an explicit
`--repo` for `gh` when not inside the repository. Never rely on the ambient cwd.

### Create a repository

Blank repository, then work in it:

```bash
gh repo create <owner>/<repo> --<visibility> --description "<desc>" --clone
```

Existing local directory, first push:

```bash
git -C <dir> init -b main
git -C <dir> add <paths>
git -C <dir> commit -m "init: <what>"
gh repo create <owner>/<repo> --source <dir> --remote origin --<visibility> --push
```

Use `<visibility>` from `default_visibility` unless the user states otherwise.

### Clone / pull / sync

```bash
gh repo clone <owner>/<repo> <dir>
git -C <dir> fetch --prune origin
git -C <dir> pull --ff-only          # shared branch: fail loudly instead of merging
git -C <dir> pull --rebase --autostash   # local-only branch
```

On a conflict or a non-fast-forward, stop and report the state. Do not merge, rebase, or
reset to make it go away.

### Commit and push

```bash
git -C <dir> status --short
git -C <dir> add <explicit paths>          # avoid `add -A` / `add .`
git -C <dir> diff --cached --stat
git -C <dir> commit -m "<message>"
git -C <dir> push -u origin <branch>
```

Review stage 2 before committing: if a credential file (`.env`, `*.pem`, `id_rsa`,
`credentials.json`) or a token appears, stop and tell the user instead of committing.
Match the repository's existing message style — check `git log --oneline -10` first.

### Branch and pull request

```bash
git -C <dir> switch -c <branch>
git -C <dir> push -u origin <branch>
gh pr create --repo <owner>/<repo> --base <base> --head <branch> \
  --title "<title>" --body-file -
```

Pass the body on stdin via a heredoc. Summarise what changed and why, then a test plan.
Do not merge; report the PR URL and let the user decide.

### Tag and release

```bash
git -C <dir> tag --sort=-v:refname | head        # match the existing version scheme
git -C <dir> tag -a <tag> -m "<message>"
git -C <dir> push origin <tag>
gh release create <tag> --repo <owner>/<repo> --title "<title>" --notes-file - [--prerelease]
```

### Inspect without changing anything

```bash
gh auth status
gh repo view <owner>/<repo> --json name,visibility,defaultBranchRef,url
gh pr list --repo <owner>/<repo> --state open
gh run list --repo <owner>/<repo> --limit 5
git -C <dir> remote -v
```

## Confirmation rules

These actions reach shared state or destroy work. State the exact command and get the
user's agreement before running them:

- `git push` — including the first push of a repository.
- `gh repo create` — it publishes content, and makes the visibility choice permanent in
  the audit trail.
- `gh pr create`, `gh pr merge`, `gh release create`, pushing a tag.
- `gh auth switch` when it changes the account another session may be relying on.
- Anything destructive: `git push --force`, history rewrite, branch deletion,
  `gh repo delete`, `git reset --hard`, `git clean`.

Read-only inspection, `git add`, and `git commit` in a working tree the user asked you to
change need no separate confirmation — but report what you staged and committed.

Never, under any instruction short of an explicit user request to do exactly this:

- `git push --force` (any form, including `--force-with-lease`) to `main` / `master`.
- `--no-verify` or bypassing a hook.
- `git config --global` writes unless `bind_scope = global` or the user asks.
- Echoing a token, writing one into a remote URL, or committing one.
- Editing `~/.ssh/config` or `gh` keyring entries.

## Failure handling

| Symptom | Action |
| --- | --- |
| `check` exits 5 | Ask the user to run `gh auth login` themselves; do not run it unattended. |
| `check` exits 8 | Transient. The API is unreachable, not the token. Report and retry; never re-authenticate or switch accounts to work around it. |
| `remote: Permission to ... denied` | The active account differs from the repository owner. Re-run `check`, then confirm the document names the correct account. |
| `failed to push some refs` / non-fast-forward | Fetch, inspect the divergence, report it. Do not force. |
| Commit author is wrong | Re-run `bind`, then report which commits carry the old author; ask before rewriting. |
| `could not read Username` | Missing or expired credential. Re-run `check`; if still failing, the user must re-authenticate. |
| Hook fails | Fix the underlying cause. Never re-run with `--no-verify`. |
| Repository not found | Verify owner/repo spelling and that the declared account has access. |

## Resources

- `scripts/gh-account.sh` — `show` / `check` / `bind`. Run this before any git or gh
  operation. Its stdout is the authoritative statement of which identity is in use.
- `references/account-format.md` — account document schema, key semantics, template, and
  a filled-in example.
