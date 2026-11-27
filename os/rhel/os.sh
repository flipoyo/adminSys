#!/usr/bin/env bash
# os/rhel/os.sh — RHEL family: AlmaLinux, Rocky, RHEL, CentOS Stream, Fedora.
# Sourced by lib/common.sh load_os. Implements the os_* interface with dnf.
# Tested target: AlmaLinux 10.

OS_LABEL="RHEL family (AlmaLinux, Rocky, RHEL, CentOS Stream, Fedora)"
OS_PKG_MANAGER="dnf"
OS_ADMIN_GROUP="wheel"             # members may use sudo
OS_SSH_SERVICE="sshd"              # systemd unit name
OS_SSH_CLIENT_PKG="openssh-clients"
OS_MAC="SELinux"

os_pkg_installed() { rpm -q "$1" >/dev/null 2>&1; }
os_pkg_install()   { dnf -y install "$1" >/dev/null 2>&1; }
os_pkg_refresh()   { dnf -y makecache; }
os_upgrade()       { dnf -y upgrade --refresh; }
os_autoremove()    { dnf -y autoremove; }

# Print the pending updates. dnf check-update exits 100 when there are some.
os_list_updates() {
  local rc=0
  dnf check-update --refresh || rc=$?
  [[ $rc -eq 0 || $rc -eq 100 ]] || warn "dnf check-update returned $rc"
}

# Exit status 0 = a reboot is needed.
os_needs_reboot() {
  if command -v needs-restarting >/dev/null 2>&1; then
    ! needs-restarting -r >/dev/null 2>&1
  else
    local running latest
    running="$(uname -r)"
    latest="$(rpm -q --last kernel-core 2>/dev/null | head -1 | awk '{print $1}' | sed 's/^kernel-core-//')"
    [[ -n "$latest" && "$latest" != "$running" ]]
  fi
}

# Repositories needed before the package groups (EPEL + CRB on EL clones).
os_extra_repos() {
  # shellcheck disable=SC1091
  local id; id="$( . /etc/os-release && echo "${ID:-}" )"
  [[ "$id" == "fedora" ]] && return 0
  dnf -y install dnf-plugins-core
  dnf -y install epel-release || warn "epel-release unavailable (plain RHEL needs the EPEL release RPM by URL)"
  dnf config-manager --set-enabled crb || warn "could not enable CRB"
  dnf -y makecache
}

# SELinux: give files created by hand the context the service expects.
os_fix_context() { command -v restorecon >/dev/null 2>&1 && restorecon -R "$1" || true; }

# Firewall, time sync, brute-force protection, automatic security updates.
os_services() {
  systemctl enable --now firewalld chronyd
  write_fail2ban_jail
  systemctl enable --now fail2ban || warn "fail2ban not started"
  if [[ -f /etc/dnf/automatic.conf ]]; then
    sed -i 's/^upgrade_type.*/upgrade_type = security/; s/^apply_updates.*/apply_updates = yes/' /etc/dnf/automatic.conf
    systemctl enable --now dnf-automatic.timer || warn "dnf-automatic not started"
  fi
  firewall-cmd --permanent --add-service=ssh
  firewall-cmd --reload
}
