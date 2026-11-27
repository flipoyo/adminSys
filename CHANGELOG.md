# Changelog

Versions follow [Semantic Versioning](https://semver.org). The version is written in
`pixi.toml` and `lib/common.sh`.

## 0.1.0

First release, extracted from the administration notes and scripts of an AlmaLinux 10 server.

- `bin/sys`: one entry point (`detect`, `base`, `update`, `pixi`, `ssh-agent`, `ssh-harden`,
  `crypt-init`, `check-public`).
- Portable scripts in `common/`; every system-dependent line isolated in `os/<family>/`
  (`rhel` for AlmaLinux/Rocky/RHEL/Fedora, `debian` for Debian/Ubuntu).
- `pixi.toml` with git, git-crypt, gnupg, openssh and shellcheck.
- git-crypt for `secrets/`, plus `check-public` to scan the repository before publishing.
- `os/debian` is untested on a live system.
- Licensed under Apache License 2.0.
