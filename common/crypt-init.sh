#!/usr/bin/env bash
# common/crypt-init.sh — switch on git-crypt for secrets/ in this repository.
#
#   bin/sys crypt-init                                  generate the repo key
#   bin/sys crypt-init --export-key ~/safe/adminsys.key also save it OUTSIDE the repo
#   bin/sys crypt-init --gpg-user <KEYID|email> ...     also let these GPG identities unlock
#
# Do this BEFORE the first commit of anything under secrets/ (the repo is public).
# The rule that selects what gets encrypted is in .gitattributes.
set -euo pipefail
ADMINSYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ADMINSYS_ROOT/lib/common.sh"

GPG_USERS=(); KEYOUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gpg-user)   [[ $# -ge 2 ]] || die "--gpg-user needs a key id"; GPG_USERS+=("$2"); shift 2 ;;
    --export-key) [[ $# -ge 2 ]] || die "--export-key needs a path"; KEYOUT="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

command -v git >/dev/null       || die "git is missing (sys base, or: pixi install)"
command -v git-crypt >/dev/null || die "git-crypt is missing (sys base, or: pixi install)"
cd "$ADMINSYS_ROOT"
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository yet — run: git init -b main"
grep -q 'secrets/\*\* filter=git-crypt' .gitattributes || die ".gitattributes has no 'secrets/** filter=git-crypt' rule"
[[ -d "$(git rev-parse --git-dir)/git-crypt" ]] && die "git-crypt is already initialised in this repository"

if git ls-files --error-unmatch secrets/ >/dev/null 2>&1; then
  tracked="$(git ls-files secrets | grep -v '^secrets/README.md$' || true)"
  [[ -z "$tracked" ]] || die "files under secrets/ are already committed in clear text — rewrite history first:"$'\n'"$tracked"
fi

# Refuse an export path inside the repository (it would end up in git).
if [[ -n "$KEYOUT" ]]; then
  out_dir="$(cd "$(dirname "$KEYOUT")" 2>/dev/null && pwd)" || die "directory of $KEYOUT does not exist"
  case "$out_dir/" in "$ADMINSYS_ROOT"/*) die "export the key OUTSIDE the repository" ;; esac
  [[ ! -e "$KEYOUT" ]] || die "$KEYOUT already exists"
fi

git-crypt init
ok "git-crypt initialised"

if [[ -n "$KEYOUT" ]]; then
  ( umask 077; git-crypt export-key "$KEYOUT" )
  ok "key saved to $KEYOUT (mode 600) — back it up somewhere safe, NOT in this repo"
fi
for k in "${GPG_USERS[@]+"${GPG_USERS[@]}"}"; do
  git-crypt add-gpg-user "$k" && ok "GPG user added: $k"
done

cat <<'EOF'

Next:
  1. Put sensitive files under secrets/ (inventories, IPs, runbooks with real hosts...).
  2. git add secrets && git-crypt status -e     # must list them as ENCRYPTED
  3. git commit, then push.
Unlock on another machine:  git-crypt unlock /path/to/adminsys.key   (or: git-crypt unlock, with a GPG key)
Lose the key and no GPG user = secrets/ is gone for good. Read docs/04-secrets-git-crypt.md.
EOF
