#!/usr/bin/env bash
# common/base.sh — install the base administration tooling (any supported family).
#
#   sudo bin/sys base                       default groups
#   sudo bin/sys base --with build          + compilers (gcc, gfortran, flex, bison, make)
#   sudo bin/sys base --with autotools      + cmake, autoconf, automake, libtool
#   sudo bin/sys base --no-services         packages only: no firewall/fail2ban/auto-updates
#
# Package names come from os/<family>/packages.ini; the package manager and the
# services come from os/<family>/os.sh. Re-runnable.
set -euo pipefail
ADMINSYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ADMINSYS_ROOT/lib/common.sh"

GROUPS_DEFAULT=(core editors git monitor network ssh crypt security containers)
EXTRA=(); SERVICES=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with) [[ $# -ge 2 ]] || die "--with needs a group name"; EXTRA+=("$2"); shift 2 ;;
    --no-services) SERVICES=0; shift ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_root "$@"
load_os
start_log base
info "adminSys $ADMINSYS_VERSION — $OS_LABEL — $(date -Is)"

for g in "${EXTRA[@]+"${EXTRA[@]}"}"; do
  [[ -n "$(pkg_group "$g")" ]] || die "unknown or empty package group '$g' (see os/$FAMILY/packages.ini)"
done

info "Upgrading the system"
os_upgrade
os_extra_repos

for g in "${GROUPS_DEFAULT[@]}" "${EXTRA[@]+"${EXTRA[@]}"}"; do install_group "$g"; done

info "Installing pixi"
bash "$ADMINSYS_ROOT/common/pixi-install.sh" || { warn "pixi install failed"; MISSING+=("pixi"); }

if [[ $SERVICES -eq 1 ]]; then
  info "Enabling services (firewall, time sync, fail2ban, automatic security updates)"
  os_services
fi

echo
info "Done — $(date -Is)"
for t in git git-crypt gpg ssh ssh-agent ssh-keygen pixi podman; do
  printf '  %-11s: %s\n' "$t" "$(command -v "$t" >/dev/null 2>&1 && "$t" --version 2>&1 | head -1 || echo missing)"
done
if [[ ${#MISSING[@]} -gt 0 ]]; then warn "Not installed: ${MISSING[*]}"; else ok "everything installed"; fi
