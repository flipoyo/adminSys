# What is system-dependent, and what is not

The starting material was five files from a real AlmaLinux 10 server: three scripts
(`install_orx_base.sh`, `update.sh`, `install-ssh-agent.sh`) and two howtos. Each was split
along one question: *would this line change if the distribution changed?*

Three kinds of content came out:

- **Portable**: same on any systemd Linux. Lives in `lib/`, `common/`, `docs/`.
- **System-dependent**: changes with the family. Lives in `os/<family>/` only.
- **Specific to one server or project**: not published here (see the last section).

## Script by script

| Original | Portable (now in) | System-dependent (now in `os/`) | Dropped |
|---|---|---|---|
| `install_orx_base.sh` | install flow, group logic, log, summary → `common/base.sh`; pixi install → `common/pixi-install.sh`; fail2ban jail → `lib/common.sh` | `dnf`, EPEL + CRB, every package name → `os/rhel/packages.ini`; `firewalld`, `chronyd`, `dnf-automatic` → `os/rhel/os.sh` | the server's host name; the `git clone` lines for three research projects; the GUI/Flatpak option (a server needs no browser: use VS Code Remote-SSH) |
| `update.sh` | flow, `--all`, `--reboot`, log → `common/update.sh` | `dnf check-update / upgrade / autoremove`, `needs-restarting` → `os/rhel/os.sh` | — |
| `install-ssh-agent.sh` | everything (systemd user unit, `~/.bashrc`, `AddKeysToAgent`) → `common/ssh-agent-user.sh` | only the client package name: `openssh-clients` (rhel) vs `openssh-client` (debian) | wording tied to one host |
| `20261127_howto-ssh-authorized-keys.md` | `authorized_keys`, permissions → `docs/03-ssh-authorized-keys.md` | `restorecon` (SELinux only) | host name |
| `20261127_admin-install-user-folder.md` | partitioning rules, accounts, sudo, groups + ACL, recovery → `docs/01`, `docs/02` | `wheel` vs `sudo`, `dnf` vs `apt`, `acl` package | the whole log of one machine: host, user name, project, OVH steps |

## The system-dependent surface, in full

Everything below is behind an `os_*` function or a `packages.ini` entry:

| Concern | `os/rhel` (AlmaLinux, Rocky, RHEL, Fedora) | `os/debian` (Debian, Ubuntu) |
|---|---|---|
| Package manager | `dnf` / `rpm` | `apt-get` / `dpkg` |
| Extra repositories | EPEL + CRB | none |
| Package names | `gcc-gfortran`, `bind-utils`, `vim-enhanced`… | `gfortran`, `bind9-dnsutils`, `vim`… |
| Firewall | `firewalld` | `ufw` |
| Mandatory access control | SELinux (`restorecon`) | AppArmor |
| Automatic updates | `dnf-automatic` | `unattended-upgrades` |
| Sudo group | `wheel` | `sudo` |
| SSH service unit | `sshd` | `ssh` |
| Time sync unit | `chronyd` | `chrony` |
| Reboot-needed test | `needs-restarting -r` | `/var/run/reboot-required` |

## Portable on purpose

`pixi` (a static binary), `ssh-agent` as a systemd user service, sshd drop-ins in
`sshd_config.d/`, `authorized_keys`, `useradd`, POSIX ACLs (`setfacl`), `git-crypt`, XFS/ext4
partitioning rules.

## What is *not* in this repository

The log of the original server (its host name, its administrator's login, which research
projects it serves, how its provider's installer behaved) is private to that machine. If you
want to keep such a log next to these scripts, put it under `secrets/`: it will be
encrypted. See [docs/04-secrets-git-crypt.md](docs/04-secrets-git-crypt.md).
