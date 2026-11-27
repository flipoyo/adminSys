#!/usr/bin/env bash
# os/debian/os.sh — Debian family: Debian 12/13, Ubuntu LTS.
# Sourced by lib/common.sh load_os. Implements the os_* interface with apt.
# UNTESTED on a live system: written as the counterpart of os/rhel/os.sh.

OS_LABEL="Debian family (Debian, Ubuntu)"
OS_PKG_MANAGER="apt"
OS_ADMIN_GROUP="sudo"              # members may use sudo
OS_SSH_SERVICE="ssh"               # unit name on Debian/Ubuntu (sshd is an alias)
OS_SSH_CLIENT_PKG="openssh-client"
OS_MAC="AppArmor"

export DEBIAN_FRONTEND=noninteractive

os_pkg_installed() { dpkg -s "$1" >/dev/null 2>&1; }
os_pkg_install()   { apt-get install -y "$1" >/dev/null 2>&1; }
os_pkg_refresh()   { apt-get update; }
os_upgrade()       { apt-get update && apt-get -y upgrade; }
os_autoremove()    { apt-get -y autoremove; }

os_list_updates() { apt-get update -qq && apt list --upgradable 2>/dev/null | tail -n +2; }

# Exit status 0 = a reboot is needed.
os_needs_reboot() { [[ -f /var/run/reboot-required ]]; }

# Debian ships what we need in the main archive: nothing to enable.
os_extra_repos() { :; }

# AppArmor has no per-file labels to repair after hand-made files.
os_fix_context() { :; }

# Firewall, time sync, brute-force protection, automatic security updates.
os_services() {
  local port
  port="$(sshd -T 2>/dev/null | awk '$1=="port"{print $2; exit}')"
  port="${port:-22}"
  ufw allow "${port}/tcp"            # allow SSH BEFORE enabling, or you lock yourself out
  ufw --force enable
  systemctl enable --now chrony
  write_fail2ban_jail
  systemctl enable --now fail2ban || warn "fail2ban not started"
  dpkg-reconfigure -f noninteractive unattended-upgrades   # security updates only by default
}
