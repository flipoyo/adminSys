#!/usr/bin/env bash
# common/check-public.sh — scan this repository for things that must not be published.
#
#   bin/sys check-public            exit 1 on a private key, 0 otherwise (warnings printed)
#   bin/sys check-public --strict   exit 1 on any finding
#
# Scans the files git tracks (or all files when this is not a git repo yet).
# secrets/ is skipped: git-crypt encrypts it. Heuristics, not a guarantee.
set -euo pipefail
ADMINSYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ADMINSYS_ROOT/lib/common.sh"

STRICT=0
[[ "${1:-}" == "--strict" ]] && STRICT=1
cd "$ADMINSYS_ROOT"

if git rev-parse --git-dir >/dev/null 2>&1; then
  mapfile -t FILES < <(git ls-files)
else
  mapfile -t FILES < <(find . -type f -not -path './.git/*' -not -path './.pixi/*' | sed 's|^\./||')
fi
FILTERED=()
for f in "${FILES[@]}"; do
  case "$f" in secrets/*|common/check-public.sh|pixi.lock) continue ;; esac
  [[ -f "$f" ]] && FILTERED+=("$f")
done

[[ ${#FILTERED[@]} -gt 0 ]] || { ok "no file to scan"; exit 0; }

HARD=0; SOFT=0
# stdin: "file:line:match" lines. $1 = hard|soft, $2 = label.
report() {
  local out; out="$(cat)"
  [[ -n "$out" ]] || return 0
  if [[ "$1" == hard ]]; then HARD=$((HARD + 1)); printf '%s[HARD]%s %s\n' "$_R" "$_0" "$2" >&2
  else SOFT=$((SOFT + 1)); printf '%s[WARN]%s %s\n' "$_Y" "$_0" "$2" >&2; fi
  printf '%s\n' "$out" | sed 's/^/    /' >&2
}
# -e: a pattern may start with "-". -o: print the match only. Never prints a whole line.
matches() { grep -InoE "$@" "${FILTERED[@]}" 2>/dev/null || true; }

# report runs in this shell (input by process substitution, not a pipe) so that
# HARD/SOFT survive; a pipe would count in a subshell and lose them.
report hard "private key material" < <(matches -e '-----BEGIN [A-Z ]*PRIVATE KEY-----')
report hard "git-crypt key file"   < <(matches -e 'GITCRYPTKEY')

# value hidden: the report must not leak the very secret it found
report soft "possible secret assigned (password / token / secret = value)" < <(
  matches -i -e '(password|passwd|secret|token|api[_-]?key)[[:space:]]*[=:][[:space:]]*["'"'"']?[A-Za-z0-9/+_.-]{8,}' \
    | sed -E 's/^([^:]+:[0-9]+:)[^=:]*[=:].*/\1<assignment, value hidden>/')

# public IPv4 only: not private, loopback, link-local, CGNAT or documentation ranges
report soft "public-looking IPv4 address" < <(
  matches -e '[0-9]{1,3}(\.[0-9]{1,3}){3}' | awk -F: '{
    n = split($NF, o, "."); if (n != 4) next
    for (i = 1; i <= 4; i++) if (o[i] + 0 > 255) next
    a = o[1] + 0; b = o[2] + 0; c = o[3] + 0
    if (a == 0 || a == 10 || a == 127 || a >= 224) next
    if (a == 169 && b == 254) next
    if (a == 172 && b >= 16 && b <= 31) next
    if (a == 192 && b == 168) next
    if (a == 100 && b >= 64 && b <= 127) next
    if (a == 192 && b == 0 && c == 2) next
    if (a == 198 && b == 51 && c == 100) next
    if (a == 203 && b == 0 && c == 113) next
    print }')

# e-mail addresses, except ssh/git URLs (git@host) and the example.* placeholder domains
report soft "e-mail address" < <(
  matches -e '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' \
    | grep -vE ':(git|ssh)@|@(example\.(org|com|net)|users\.noreply\.github\.com)$' || true)

echo
if [[ $HARD -gt 0 ]]; then die "$HARD blocking finding(s): do NOT publish"; fi
if [[ $SOFT -gt 0 ]]; then
  warn "$SOFT kind(s) of finding to review (placeholders such as <ip> are fine)"
  if [[ $STRICT -eq 1 ]]; then exit 1; fi
else
  ok "nothing suspicious in ${#FILTERED[@]} file(s)"
fi
