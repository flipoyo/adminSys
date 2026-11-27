# 01 — Choosing an OS, partitioning the disks

*Created: 2026-11-27*

## 1. Choosing a distribution

Ask four questions, in this order:

1. **Is the support period longer than you will keep the machine?** A distribution that
   ends support before your rental or project does is out (a short-lived Fedora release,
   for example).
2. **Does your main software have official packages for it?** (GitLab, Podman, your
   scientific stack.) Check the vendor's "supported operating systems" page.
3. **Does it match where the work will run later?** Most HPC clusters run the RHEL
   family (RHEL, Rocky, Alma). Testing on that family early finds portability problems.
4. **Do you want to test reproducibility?** If your environments are pinned with pixi
   lockfiles, a host from a *different* family than your workstation is the honest test: a
   hidden dependency on the host fails immediately instead of years later.

AlmaLinux and Rocky Linux are interchangeable binary clones of RHEL. A newer major
release brings a newer glibc and kernel (more room for recent conda-forge packages) but a
younger EPEL; check that the extra packages you need exist for it.

## 2. Partitioning

Separate partitions limit the damage one runaway process can do: if logs, container images
or run outputs fill a disk, only that partition is full and the system stays usable.

| Mount | Size (example, ~5.5 TiB usable) | Holds |
|---|---|---|
| `/boot` | 2 GiB | kernels and initramfs images |
| `/` | 100 GiB | the operating system only |
| `/var` | 800 GiB | service data: databases, container images, git hosting, logs |
| `/home` | 1 TiB | users' code, pixi environments and caches |
| `/data` | the rest | shared datasets and run outputs |
| swap | 2 × 8 GiB (with 64 GB RAM) | safety net, not a working area |

Rules worth knowing:

- **XFS grows but never shrinks.** Err on the small side; add the remainder to the last
  partition (`/data`).
- **RAID1 mirrors**: the usable size is half the raw size. Disk failure then costs nothing
  but the disk. Swap is usually *not* mirrored (one per disk).
- **Provider installers** (OVH and others) often default to one `/` taking all the space and
  then refuse to add partitions ("not enough space available"). Shrink `/` first, then add
  the others, and enter the **usable** size. Check the unit drop-down: MiB is often the
  default, and `150` in MiB is a tiny partition. If the web form misbehaves, reload it, try
  a private window, or use the provider's API.
- **Hard links and reflinks cannot cross filesystems.** Keep data-heavy working copies on
  the same partition as their cache (`/data`).
- **Rootless containers store images under `~/.local/share/containers`**, so under `/home`.
  Move `graphroot` (in `~/.config/containers/storage.conf`) if `/home` is small.

Check the result on the machine: `lsblk` and `df -h`.
