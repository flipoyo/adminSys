#!/usr/bin/env bash
# common/update.sh — "apt update && apt upgrade && apt autoremove", on any family.
#
#   sudo bin/sys update            system packages only
#   sudo bin/sys update --all      + pixi itself, system-wide pixi tools, flatpaks
#   sudo bin/sys update --reboot   reboot by itself when needed (60 s grace)
#
# Project environments (pixi.lock) are NEVER touched: reproducibility first.
set -euo pipefail
ADMINSYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ADMINSYS_ROOT/lib/common.sh"

ALL=0; REBOOT=0
for a in "$@"; do
  case "$a" in
    --all) ALL=1 ;;
    --reboot) REBOOT=1 ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

require_root "$@"
load_os
start_log update
info "Start: $(date -Is) — $OS_LABEL"

info "Available updates"
os_list_updates
info "Upgrading"
os_upgrade
info "Removing unused dependencies"
os_autoremove

if [[ $ALL -eq 1 ]]; then
  if [[ -x /usr/local/bin/pixi ]]; then
    info "Updating pixi"
    /usr/local/bin/pixi self-update || warn "pixi self-update failed"
  fi
  if [[ -d /opt/pixi ]]; then
    info "Updating system-wide pixi tools (/opt/pixi)"
    PIXI_HOME=/opt/pixi /usr/local/bin/pixi global update || warn "pixi global update failed"
    chmod -R a+rX /opt/pixi
  fi
  if command -v flatpak >/dev/null 2>&1; then
    info "Updating flatpaks"
    flatpak update -y --system || warn "flatpak update failed"
  fi
fi

echo
info "Done: $(date -Is)"
if os_needs_reboot; then
  warn "Reboot required (kernel or core libraries updated)."
  if [[ $REBOOT -eq 1 ]]; then
    warn "Rebooting in 60 s — Ctrl+C to cancel"
    sleep 60
    systemctl reboot
  else
    echo "  -> check nobody is running a job (who; ps -eo user,etime,cmd --sort=-etime | head), then: sudo systemctl reboot"
  fi
else
  info "No reboot needed"
fi
