#!/usr/bin/env bash
# lib/common.sh — helpers shared by every adminSys script. Sourced, never run.
#
# The split that matters (see CLASSIFICATION.md):
#   lib/ and common/  = portable: no distro name, no package manager
#   os/<family>/      = system-dependent: package names, package manager,
#                       firewall, MAC (SELinux/AppArmor), service names
# Everything system-dependent is reached through the os_* functions that each
# os/<family>/os.sh defines. Nothing outside os/ may call dnf, apt, ufw...

ADMINSYS_ROOT="${ADMINSYS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ADMINSYS_VERSION="0.1.0"

if [[ -t 1 ]]; then
  _B=$'\e[1;34m'; _G=$'\e[1;32m'; _Y=$'\e[1;33m'; _R=$'\e[1;31m'; _0=$'\e[0m'
else
  _B=""; _G=""; _Y=""; _R=""; _0=""
fi
info() { printf '%s[INFO]%s %s\n' "$_B" "$_0" "$*"; }
ok()   { printf '%s[ OK ]%s %s\n' "$_G" "$_0" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$_Y" "$_0" "$*" >&2; }
die()  { printf '%s[FAIL]%s %s\n' "$_R" "$_0" "$*" >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || die "run as root: sudo $0 $*"; }
refuse_root()  { [[ $EUID -ne 0 ]] || die "run as your normal user, not root/sudo"; }

# Tee everything to /var/log/adminsys-<name>.log (root only; silent otherwise).
start_log() {
  local log="/var/log/adminsys-$1.log"
  if [[ $EUID -eq 0 ]]; then
    exec > >(tee -a "$log") 2>&1
    info "log: $log"
  fi
}

# --- OS detection ----------------------------------------------------------------
# Prints: rhel | debian | macos | unknown. Override with ADMINSYS_FAMILY.
detect_family() {
  if [[ -n "${ADMINSYS_FAMILY:-}" ]]; then echo "$ADMINSYS_FAMILY"; return; fi
  if [[ "$(uname -s)" == "Darwin" ]]; then echo macos; return; fi
  local ids
  ids="$( . /etc/os-release 2>/dev/null && echo "${ID:-} ${ID_LIKE:-}" )" || ids=""
  case " $ids " in
    *" rhel "*|*" fedora "*|*" centos "*|*" almalinux "*|*" rocky "*) echo rhel ;;
    *" debian "*|*" ubuntu "*) echo debian ;;
    *) echo unknown ;;
  esac
}

# Sets FAMILY and defines the os_* functions for this system.
load_os() {
  FAMILY="$(detect_family)"
  local f="$ADMINSYS_ROOT/os/$FAMILY/os.sh"
  [[ -f "$f" ]] || die "unsupported system family '$FAMILY' (available: $(find "$ADMINSYS_ROOT/os" -mindepth 1 -maxdepth 1 -type d -printf '%f ')). Override: ADMINSYS_FAMILY=rhel|debian"
  # shellcheck disable=SC1090
  source "$f"
}

# --- package groups (data lives in os/<family>/packages.ini) -------------------------
pkg_group() {
  awk -v g="$1" '
    /^[[:space:]]*(#|$)/ { next }
    /^\[.*\]$/ { cur = substr($0, 2, length($0) - 2); next }
    cur == g { print }
  ' "$ADMINSYS_ROOT/os/$FAMILY/packages.ini" | tr -s ' \t' '\n\n' | sed '/^$/d'
}

MISSING=()
# One package at a time: a name absent from this release must not stop the run.
install_group() {
  local g="$1" p
  info "group [$g]"
  for p in $(pkg_group "$g"); do
    if os_pkg_installed "$p"; then continue; fi
    if os_pkg_install "$p"; then ok "$p"; else warn "$p not available"; MISSING+=("$p"); fi
  done
}

# --- shared service snippets ---------------------------------------------------------
write_fail2ban_jail() {
  [[ -d /etc/fail2ban ]] || return 0
  mkdir -p /etc/fail2ban/jail.d
  cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled  = true
backend  = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
EOF
}
