#!/usr/bin/env bash
# Resolve the declared GitHub account, verify gh auth, bind the git commit identity.
#
# Usage:
#   gh-account.sh show            Print the resolved account settings.
#   gh-account.sh check [--no-switch]
#                                 Validate config + git/gh presence + gh auth.
#                                 Switches the active gh account to the declared
#                                 one unless --no-switch is given.
#   gh-account.sh bind [DIR] [--global|--local]
#                                 Write user.name/user.email into DIR (default .)
#                                 or globally. Defaults to bind_scope from config.
#
# Config doc path: $GH_ACCOUNT_DOC, else $HOME/.qoder-cn/github-account.md
#
# Exit codes: 0 ok | 1 usage/other | 2 config missing | 3 config invalid
#             4 git or gh missing | 5 account not logged in / token rejected
#             6 switch failed | 7 not a git repository
#             8 credentials could not be verified (GitHub API unreachable)

set -uo pipefail

CONFIG="${GH_ACCOUNT_DOC:-$HOME/.qoder-cn/github-account.md}"

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

cfg() {
  # cfg <key> -> value of the first "key = value" line (case-insensitive key), or empty
  [ -f "$CONFIG" ] || return 0
  grep -m1 -iE "^[[:space:]]*$1[[:space:]]*=" "$CONFIG" 2>/dev/null \
    | sed -E "s/^[[:space:]]*[^=]+=[[:space:]]*//" \
    | sed -E 's/[[:space:]]*$//' \
    | tr -d '\r' \
    | sed -E 's/^"(.*)"$/\1/'
}

load() {
  [ -f "$CONFIG" ] || die "config doc not found: $CONFIG
Create it using the template in references/account-format.md of this skill." 2
  HOST="$(cfg host)"
  ACCOUNT="$(cfg account)"
  GIT_NAME="$(cfg git_name)"
  GIT_EMAIL="$(cfg git_email)"
  PROTOCOL="$(cfg protocol)"
  VISIBILITY="$(cfg default_visibility)"
  BIND_SCOPE="$(cfg bind_scope)"
  [ -n "$PROTOCOL" ]   || PROTOCOL=https
  [ -n "$VISIBILITY" ] || VISIBILITY=private
  [ -n "$BIND_SCOPE" ] || BIND_SCOPE=local

  for pair in "host:$HOST" "account:$ACCOUNT" "git_name:$GIT_NAME" "git_email:$GIT_EMAIL"; do
    key="${pair%%:*}"
    value="${pair#*:}"
    [ -n "$value" ] || die "missing required key '$key' in $CONFIG" 3
  done

  case "$PROTOCOL" in https|ssh) ;; *) die "protocol must be 'https' or 'ssh', got '$PROTOCOL'" 3 ;; esac
  case "$VISIBILITY" in public|private|internal) ;; *) die "default_visibility must be 'public', 'private' or 'internal', got '$VISIBILITY'" 3 ;; esac
  case "$BIND_SCOPE" in local|global) ;; *) die "bind_scope must be 'local' or 'global', got '$BIND_SCOPE'" 3 ;; esac
}

cmd_show() {
  load
  printf 'config=%s\n' "$CONFIG"
  printf 'host=%s\n' "$HOST"
  printf 'account=%s\n' "$ACCOUNT"
  printf 'git_name=%s\n' "$GIT_NAME"
  printf 'git_email=%s\n' "$GIT_EMAIL"
  printf 'protocol=%s\n' "$PROTOCOL"
  printf 'default_visibility=%s\n' "$VISIBILITY"
  printf 'bind_scope=%s\n' "$BIND_SCOPE"
}

# Probe gh's account list for $HOST. Prints TSV rows: login, active, state, protocol, error.
# Reads only local + keyring state, so it still reports the configured accounts offline.
probe_host() {
  gh auth status --json hosts \
    --jq ".hosts[\"$HOST\"][]? | [.login, (.active|tostring), (.state//\"-\"), (.gitProtocol//\"-\"), (.error//\"-\")] | @tsv" \
    2>/dev/null | tr -d '\r' || true
}

# gh's bare "The token in keyring is invalid" wording also fires on network and proxy
# failures — it reports "could not verify" as "invalid". Tell the two apart by the reason.
is_connectivity_error() {
  printf '%s' "$1" | grep -qiE 'proxyconnect|dial tcp|no such host|i/o timeout|connection refused|connection reset|network is unreachable|TLS handshake|unexpected EOF|context deadline|HTTP 5[0-9][0-9]|Bad Gateway|Service Unavailable|Gateway Timeout'
}

cmd_check() {
  local no_switch=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --no-switch) no_switch=1; shift ;;
      *) die "unknown option for check: $1" 1 ;;
    esac
  done

  load
  command -v git >/dev/null 2>&1 || die "git not found on PATH" 4
  command -v gh  >/dev/null 2>&1 || die "gh not found on PATH. Install GitHub CLI first." 4

  local rows
  rows="$(probe_host)"
  if [ -z "$rows" ]; then
    die "no gh account is configured for $HOST.
Ask the user to run: gh auth login --hostname $HOST --git-protocol $PROTOCOL
(This is interactive; never run it unattended.)" 5
  fi

  local login active state proto errmsg found=0 switched=no
  while IFS=$'\t' read -r login active state proto errmsg; do
    [ "$login" = "$ACCOUNT" ] || continue
    found=1
    if [ "$state" != success ]; then
      if is_connectivity_error "$errmsg"; then
        die "cannot verify '$ACCOUNT@$HOST' — the GitHub API is unreachable.
  reason: $errmsg
Local credentials for '$ACCOUNT' exist and were NOT rejected, so this is a network
or proxy problem rather than a bad token. Retry when connectivity returns. Do not
run 'gh auth refresh', and do not fall back to another account." 8
      fi
      die "'$ACCOUNT@$HOST' is configured but GitHub rejected the credentials.
  reason: $errmsg
Ask the user to run: gh auth refresh --hostname $HOST" 5
    fi
    if [ "$active" != true ]; then
      if [ "$no_switch" = 1 ]; then
        die "gh is active as another account but the doc declares '$ACCOUNT' (switch suppressed by --no-switch)." 6
      fi
      gh auth switch --hostname "$HOST" --user "$ACCOUNT" >/dev/null 2>&1 \
        || die "failed to switch gh account to '$ACCOUNT' on $HOST. Run: gh auth switch --hostname $HOST --user $ACCOUNT" 6
      switched=yes
    fi
  done <<EOF
$rows
EOF

  if [ "$found" != 1 ]; then
    die "declared account '$ACCOUNT' is not logged in to $HOST.
Logged in accounts: $(printf '%s\n' "$rows" | cut -f1 | paste -sd', ' -)
Ask the user to run: gh auth login --hostname $HOST --git-protocol $PROTOCOL
then select '$ACCOUNT' (interactive; never run it unattended)." 5
  fi

  local active_login gh_proto
  rows="$(probe_host)"
  active_login="$(printf '%s\n' "$rows" | awk -F'\t' '$2=="true"{print $1; exit}')"
  gh_proto="$(printf '%s\n' "$rows" | awk -F'\t' -v a="$ACCOUNT" '$1==a{print $4; exit}')"
  [ "$active_login" = "$ACCOUNT" ] || die "gh active account is '$active_login', expected '$ACCOUNT'." 6

  printf 'OK: gh active account = %s@%s (switched=%s, gh-protocol=%s)\n' "$ACCOUNT" "$HOST" "$switched" "$gh_proto"
  printf 'declared: protocol=%s default_visibility=%s bind_scope=%s\n' "$PROTOCOL" "$VISIBILITY" "$BIND_SCOPE"
  printf 'commit identity to bind: %s <%s>\n' "$GIT_NAME" "$GIT_EMAIL"

  local gname gmail
  gname="$(git config --global user.name 2>/dev/null)"
  gmail="$(git config --global user.email 2>/dev/null)"
  if [ "$gname" = "$GIT_NAME" ] && [ "$gmail" = "$GIT_EMAIL" ]; then
    printf 'global git identity matches the doc.\n'
  else
    printf 'NOTE: global git identity is "%s <%s>" — run "gh-account.sh bind <dir>" (or --global) to align a repo with the doc.\n' "$gname" "$gmail"
  fi
}

cmd_bind() {
  load
  local scope="$BIND_SCOPE" dir="" arg
  for arg in "$@"; do
    case "$arg" in
      --global) scope=global ;;
      --local)  scope=local ;;
      -*) die "unknown option for bind: $arg" 1 ;;
      *)  [ -z "$dir" ] || die "only one directory may be given" 1; dir="$arg" ;;
    esac
  done
  [ -n "$dir" ] || dir=.
  [ -d "$dir" ] || die "no such directory: $dir" 7

  if [ "$scope" = global ]; then
    git config --global user.name "$GIT_NAME"  || die "failed to set global user.name" 7
    git config --global user.email "$GIT_EMAIL" || die "failed to set global user.email" 7
    printf 'OK: global git identity = %s <%s>\n' "$(git config --global user.name)" "$(git config --global user.email)"
    return 0
  fi

  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $dir
Run 'git init' there first, or pass a directory that already contains .git" 7
  git -C "$dir" config user.name "$GIT_NAME"  || die "failed to set local user.name in $dir" 7
  git -C "$dir" config user.email "$GIT_EMAIL" || die "failed to set local user.email in $dir" 7
  printf 'OK: local git identity in %s = %s <%s>\n' "$(cd "$dir" && pwd)" "$(git -C "$dir" config user.name)" "$(git -C "$dir" config user.email)"
}

case "${1:-}" in
  show)  shift; cmd_show "$@" ;;
  check) shift; cmd_check "$@" ;;
  bind)  shift; cmd_bind "$@" ;;
  ""|-h|--help|help)
    printf 'Usage: gh-account.sh <show|check|bind> [options]\n'
    printf '  show                     print resolved account settings\n'
    printf '  check [--no-switch]      validate config, git/gh, and gh auth\n'
    printf '  bind [DIR] [--global]    write commit identity into DIR (default bind_scope)\n'
    printf 'Config doc: %s\n' "$CONFIG"
    [ -n "${1:-}" ] || exit 1
    ;;
  *) die "unknown subcommand: $1 (expected show|check|bind)" 1 ;;
esac
