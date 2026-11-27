#!/usr/bin/env bash
# common/ssh-harden.sh — key-only SSH, no root login. Run ON the server, as root.
#
#   sudo bin/sys ssh-harden          explain and ask
#   sudo bin/sys ssh-harden --yes    do it
#   sudo bin/sys ssh-harden --undo   remove the drop-in
#
# Do it once EVERY user has a key in ~/.ssh/authorized_keys. Refuses to run if
# the invoking sudo user has none, so you cannot lock yourself out.
# Portable: a sshd drop-in works the same on every distro; only the service
# name (sshd | ssh) comes from os/<family>/os.sh.
set -euo pipefail
ADMINSYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ADMINSYS_ROOT/lib/common.sh"

YES=0; UNDO=0
for a in "$@"; do
  case "$a" in
    --yes) YES=1 ;;
    --undo) UNDO=1 ;;
    -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

require_root "$@"
load_os
start_log ssh-harden

DROPIN=/etc/ssh/sshd_config.d/01-adminsys-hardening.conf   # 01-: sshd keeps the FIRST value it reads

if [[ $UNDO -eq 1 ]]; then
  rm -f "$DROPIN"
  sshd -t && systemctl reload "$OS_SSH_SERVICE"
  ok "hardening removed"
  exit 0
fi

grep -Eqi '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config \
  || die "/etc/ssh/sshd_config does not Include sshd_config.d/ — add the settings by hand"

WHO="${SUDO_USER:-}"
[[ -n "$WHO" && "$WHO" != root ]] || die "run it with sudo from your own account (needed to check your key first)"
HOME_DIR="$(getent passwd "$WHO" | cut -d: -f6)"
[[ -s "$HOME_DIR/.ssh/authorized_keys" ]] \
  || die "$WHO has no $HOME_DIR/.ssh/authorized_keys — add your key first (docs/03-ssh-authorized-keys.md)"

echo "This will set on this server:  PasswordAuthentication no, PermitRootLogin no."
echo "Users without a key in authorized_keys lose SSH access (provider console / rescue mode still work)."
if [[ $YES -ne 1 ]]; then
  read -r -p "Every user has added their key? Type 'yes': " ans
  [[ "$ans" == "yes" ]] || { echo "aborted"; exit 0; }
fi

cat > "$DROPIN" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF
if ! sshd -t; then rm -f "$DROPIN"; die "sshd rejected the configuration — change reverted"; fi
systemctl reload "$OS_SSH_SERVICE"

ok "SSH hardened. KEEP this session open and test from a NEW terminal: ssh $WHO@<server>"
info "Undo: sudo bin/sys ssh-harden --undo   (or delete $DROPIN and reload $OS_SSH_SERVICE)"
