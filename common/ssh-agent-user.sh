#!/usr/bin/env bash
# common/ssh-agent-user.sh — one shared ssh-agent per user.
#
# Run as the USER who needs the agent (not with sudo):
#   bin/sys ssh-agent              install + enable
#   bin/sys ssh-agent --linger     also keep the agent after logout
#   bin/sys ssh-agent --uninstall  remove everything this added
#
# Result: SSH_AUTH_SOCK points at a running agent in every terminal, so git,
# dvc and ssh ask for a key passphrase ONCE, then reuse it.
# A per-user systemd service when `systemctl --user` works, otherwise a
# ~/.bashrc fallback with one shared socket. Re-runnable.
# Portable across distros: only the ssh client package name differs (os/*/os.sh).
set -euo pipefail
ADMINSYS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$ADMINSYS_ROOT/lib/common.sh"

LINGER=0; UNINSTALL=0
for a in "$@"; do
  case "$a" in
    --linger) LINGER=1 ;;
    --uninstall) UNINSTALL=1 ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown option: $a" ;;
  esac
done

refuse_root
load_os

UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/ssh-agent.service"
BASHRC="$HOME/.bashrc"
SSH_CFG="$HOME/.ssh/config"
MARK_BEGIN="# >>> ssh-agent (adminSys) >>>"
MARK_END="# <<< ssh-agent (adminSys) <<<"

strip_block() { [[ -f "$1" ]] && sed -i "\|$MARK_BEGIN|,\|$MARK_END|d" "$1"; return 0; }
has_systemd_user() { systemctl --user show-environment >/dev/null 2>&1; }

if [[ $UNINSTALL -eq 1 ]]; then
  has_systemd_user && systemctl --user disable --now ssh-agent 2>/dev/null || true
  rm -f "$UNIT"
  has_systemd_user && systemctl --user daemon-reload || true
  strip_block "$BASHRC"; strip_block "$SSH_CFG"
  ok "removed (open a new terminal; keys held by the agent are forgotten)"
  exit 0
fi

if ! command -v ssh-agent >/dev/null || ! command -v ssh-add >/dev/null; then
  info "Installing $OS_SSH_CLIENT_PKG (sudo)"
  case "$OS_PKG_MANAGER" in
    dnf) sudo dnf install -y "$OS_SSH_CLIENT_PKG" ;;
    apt) sudo apt-get install -y "$OS_SSH_CLIENT_PKG" ;;
    *)   die "install $OS_SSH_CLIENT_PKG with your package manager, then rerun" ;;
  esac
fi
SSH_AGENT_BIN="$(command -v ssh-agent)"
ok "ssh-agent: $SSH_AGENT_BIN"

strip_block "$BASHRC"; touch "$BASHRC"

if has_systemd_user; then
  info "Using a per-user systemd service"
  mkdir -p "$UNIT_DIR"
  cat > "$UNIT" <<EOF
[Unit]
Description=SSH key agent

[Service]
Type=simple
Environment=SSH_AUTH_SOCK=%t/ssh-agent.socket
ExecStart=${SSH_AGENT_BIN} -D -a \$SSH_AUTH_SOCK

[Install]
WantedBy=default.target
EOF
  systemctl --user daemon-reload
  systemctl --user enable --now ssh-agent
  systemctl --user is-active --quiet ssh-agent || die "agent did not start: systemctl --user status ssh-agent"
  { echo "$MARK_BEGIN"
    echo 'export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket"'
    echo "$MARK_END"; } >> "$BASHRC"
  SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ssh-agent.socket"
else
  warn "systemctl --user not available in this session — using the ~/.bashrc fallback"
  { echo "$MARK_BEGIN"
    cat <<'EOF'
export SSH_AUTH_SOCK="$HOME/.ssh/agent.sock"
ssh-add -l >/dev/null 2>&1
if [ $? -eq 2 ]; then
  rm -f "$SSH_AUTH_SOCK"
  eval "$(ssh-agent -a "$SSH_AUTH_SOCK" -s)" >/dev/null
fi
EOF
    echo "$MARK_END"; } >> "$BASHRC"
  SOCK="$HOME/.ssh/agent.sock"
fi

mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
touch "$SSH_CFG"; chmod 600 "$SSH_CFG"
strip_block "$SSH_CFG"
{ echo; echo "$MARK_BEGIN"; echo "Host *"; echo "    AddKeysToAgent yes"; echo "$MARK_END"; } >> "$SSH_CFG"
ok "AddKeysToAgent yes in $SSH_CFG"

if [[ $LINGER -eq 1 ]]; then
  if has_systemd_user; then
    loginctl enable-linger "$USER"
    ok "linger on: the agent (and unlocked keys) survive logout"
    warn "Safer default is OFF: with linger a stolen session keeps an unlocked key."
  else
    warn "--linger ignored: needs the systemd user service"
  fi
fi

export SSH_AUTH_SOCK="$SOCK"
rc=0; ssh-add -l >/dev/null 2>&1 || rc=$?
case $rc in
  0) ok "agent reachable, keys loaded" ;;
  1) ok "agent reachable, no key yet (expected)" ;;
  *) warn "agent not reachable from this shell yet — open a NEW terminal and run: ssh-add -l" ;;
esac

cat <<'EOF'

Done. In a NEW terminal (or: source ~/.bashrc):
  ssh-add -l                   # "no identities" now, your key after first use
  ssh-add -t 8h ~/.ssh/<key>   # or load now and forget after 8 h
  ssh -T git@github.com        # asks the passphrase once, never again
Remove everything this added:  bin/sys ssh-agent --uninstall
EOF
