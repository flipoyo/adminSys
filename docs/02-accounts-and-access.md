# 02 — Accounts and access

*Created: 2026-11-27 — generic (no host, no login): safe for a public repository*

First level of the install: **declare who may use the machine, and how they get in.** Do it
right after the OS install ([01](01-os-and-partitioning.md)) and before anything else is
configured. One account per person, keys instead of shared passwords, sudo only for admins,
and a documented way out for everyone who leaves.

Commands differ by family; `bin/sys detect` prints your admin group and ssh service name.

| | rhel (AlmaLinux, Rocky, RHEL, Fedora) | debian (Debian, Ubuntu) |
|---|---|---|
| Admin (sudo) group | `wheel` | `sudo` |
| SSH service unit | `sshd` | `ssh` |
| Shell given by `useradd` | `/bin/bash` | `/bin/sh` → always pass `-s /bin/bash` |

Order of work: **1** model → **2** first admin → **3** other users → **4** their keys →
**5** protect access → **6–7** shared folders and quotas. Sections 8–10 are for later.

## 1. Model

| Role | Group | Rights |
|---|---|---|
| Admin | admin group (`wheel` / `sudo`) | sudo, everything |
| Team A | `devs` | shared folder `/data/shared` |
| Team B | `ops` | `/data/shared` + `/var/ops` (see 6) |
| Everyone | own login | own `/home/<login>` |

Linux has **no nested groups**: if team B must do all that team A does, give *both* groups
rights on the folders (ACLs, section 6); do not put one group inside the other.

## 2. First hour: your own admin account

The provider gives you one account and one password (often through a link that expires: the
*link* expires, not the password). Use it once.

```bash
ssh -o PubkeyAuthentication=no <provider-user>@<server-ip>
sudo useradd -m -s /bin/bash -G <admin-group> you
sudo passwd you
id you                                    # <admin-group> must be in the list
```

`Too many authentication failures` before any password prompt: your ssh-agent offered more
keys than the server allows (`MaxAuthTries`, about 6). Nothing is wrong with the server or
the account. `-o PubkeyAuthentication=no` skips the keys and asks the password; once your
own key is installed, use `-o IdentitiesOnly=yes -i ~/.ssh/<key>` (see section 4).

Then, from a **second terminal**, keeping the first one open:

```bash
ssh you@<server-ip>
sudo -l                                   # must list (ALL) ALL
sudo whoami                               # root
```

`Sorry, user you may not run sudo` means the user is not in the admin group: the `-G`
option was forgotten, or the other family's name was used (`wheel` on Debian, `sudo` on rhel).
Repair it from the provider account, which still has sudo, then **log `you` out and in**:

```bash
sudo usermod -aG <admin-group> you        # -a: add, never replace
id you; getent group <admin-group>
```

`sudo: command not found` (minimal Debian): `apt install sudo` as root or from the provider
account first.

Only when `sudo whoami` works, retire the provider account (locking is reversible, deleting is not):

```bash
sudo usermod -L <provider-user>           # lock its password
sudo usermod -s /usr/sbin/nologin <provider-user>
```

Then install your own key (section 4) and create a **second admin** (section 3): one broken
account can then repair the other.

## 3. Create the other users

```bash
sudo useradd -m -s /bin/bash alice                 # regular user
sudo useradd -m -s /bin/bash -G <admin-group> bob  # admin: sudo rights
sudo groupadd devs; sudo groupadd ops              # once, if the groups do not exist yet
sudo usermod -aG devs alice                        # team membership: ALWAYS -a
sudo passwd alice                                  # temporary password
sudo passwd -e alice                               # must change it at first login
id alice                                           # check the groups
```

`-G` without `-a` **replaces** all supplementary groups (and can remove an admin's sudo).
Group changes apply after the user logs out and in again. Give sudo only to people who
administer the machine.

## 4. First login: the user installs their own key

From the user's computer (a key never leaves the computer it was made on):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/<key>                # once per computer, with a passphrase
ssh-copy-id -o PubkeyAuthentication=no -i ~/.ssh/<key>.pub alice@<server-ip>   # asks the password once
ssh -o IdentitiesOnly=yes -i ~/.ssh/<key> alice@<server-ip>   # must NOT ask the account password
```

`PubkeyAuthentication=no` is only for the **password step**: it stops the agent from
offering every key and hitting `Too many authentication failures` (section 2). It is not a
setting to keep. Once the key works, **remove the option**: log in with `IdentitiesOnly=yes`
and the one key. A key-only login must never need `PubkeyAuthentication=no`; if it does, the
key is not installed (check `~/.ssh/authorized_keys`, see [03](03-ssh-authorized-keys.md)).

**Making the key and the client config (later).** The `ssh-keygen` line above is the minimum.
To generate keys with a clear name (host, platform, e-mail) and have the matching
`~/.ssh/config` written for you, use
[flipoyo/sshKeyGen](https://github.com/flipoyo/sshKeyGen) on the user's computer:

```bash
pixi run genkey --email you@example.org --server <name> --user alice --host <laptop>
```

It writes the `Host` block (`IdentitiesOnly yes`, `IdentityFile`) that you would otherwise
type by hand, then prints the public key to install. Do not edit `~/.ssh/config` by hand
once genkey manages it.

The first connection asks to trust the server fingerprint: compare it with the one in the
provider's console when you can, then answer `yes`.

Admin alternative (the user sends the `.pub` line): see [03](03-ssh-authorized-keys.md),
case C. One key per computer: a lost laptop means deleting one line, not changing everything.

## 5. Protect the access

**Timeline.** Password login stays on only while users add their key.
1. Install `fail2ban` first (`sudo bin/sys base` does): it bans IPs that guess passwords.
2. Each user adds their key (section 4) and tests it from a second terminal.
3. When **everyone** has a key: `sudo bin/sys ssh-harden` → `PasswordAuthentication no`,
   `PermitRootLogin no`. Keep your session open and test a new login before closing it.
   Undo: `sudo bin/sys ssh-harden --undo`.

**Who may open an SSH session at all (optional).** Allow only some groups, so a service
account or a forgotten user cannot log in:

```bash
sudo groupadd ssh-users
sudo usermod -aG ssh-users alice                   # and every other allowed user
printf 'AllowGroups ssh-users <admin-group>\n' | sudo tee /etc/ssh/sshd_config.d/02-allowgroups.conf
sudo sshd -t && sudo systemctl reload <ssh-service>
```

Mistyped, this locks you out: keep a session open and test from a new terminal first.

**sudo.** Admin = member of the admin group; grant sudo through the group rather than
custom rules. Never edit `/etc/sudoers` directly: `sudo visudo` refuses a broken file. To
let someone run one command only:

```bash
sudo visudo -f /etc/sudoers.d/alice     # one line:  alice ALL=(root) /usr/bin/systemctl restart myservice
```

Never give a user a shell through sudo.

**Diagnose sudo.** As the user: `sudo -l` lists what is allowed; `id` shows the groups
(a group added in this session is not visible until a new login). As an admin:
`getent group <admin-group>` and `ls /etc/sudoers.d/`. Failure → cause: `may not run sudo`
→ not in the group; `command not found` → package missing; `is not in the sudoers file` →
the admin group has no sudoers rule (`sudo visudo`, line `%<admin-group> ALL=(ALL:ALL) ALL`).

## 6. Shared folders (groups + ACL)

```bash
sudo mkdir -p /data/shared
sudo chgrp -R devs /data/shared
sudo chmod 2770 /data/shared                                      # 2 = new files inherit the group
sudo setfacl -R    -m g:ops:rwX /data/shared                      # existing files
sudo setfacl -R -d -m g:devs:rwX -m g:ops:rwX /data/shared        # future files
getfacl /data/shared
sudo -u alice bash -c 'touch /data/shared/t && rm /data/shared/t' && echo "alice can write"
```

With a default ACL the **umask is ignored**, so group members can write each other's files
without any umask setting. Never open all of `/var` to a group (system files, private data
of services): create `/var/ops` the same way. `setfacl` comes from the `acl` package
(`sys base` installs it).

## 7. Disk quotas (XFS, on `/home`)

A separate `/home` lets you cap each user so one person cannot fill it. Quotas must be
switched on at mount time:

```bash
findmnt -no OPTIONS /home                     # note the current options
sudo nano /etc/fstab                          # add usrquota to the /home line: defaults,usrquota
sudo systemctl daemon-reload
sudo umount /home && sudo mount /home         # "busy": reboot instead
sudo xfs_quota -x -c 'state' /home            # accounting must be ON for users
```

```bash
sudo xfs_quota -x -c 'limit bsoft=140g bhard=150g alice' /home   # soft warns, hard blocks
sudo xfs_quota -x -c 'report -h' /home                           # usage per user
```

`man xfs_quota` explains default limits for all users (`-d`). `xfs_quota` is in `xfsprogs`.
Quotas do not exist on a partition without the option: decide before you need them.

## 8. When someone leaves

Locking the password is **not enough**: SSH key login ignores a locked password. Do all of:

```bash
U=alice
sudo chage -E 0 $U                                 # expire the account: sshd refuses it, keys included
sudo usermod -s /usr/sbin/nologin $U               # no shell
sudo truncate -s 0 /home/$U/.ssh/authorized_keys   # drop their keys
sudo loginctl terminate-user $U                    # end running sessions
sudo find /data /var /home -xdev -user $U          # what they own: hand over or delete
sudo tar czf /root/$U-home.tgz /home/$U            # archive the home outside /home
```

Hand the files to someone (`sudo chown -R newowner /data/shared/project`), keep the archive
for the retention period you decide, then `sudo userdel -r $U`. Also revoke their key on
every other place they used it: git hosting, other servers, deploy keys.

## 9. Audit: who has access today

```bash
getent group <admin-group>                         # who can sudo
getent passwd | awk -F: '$3>=1000 && $7!~/nologin|false/ {print $1, $6}'   # human accounts
sudo awk -F: '$2=="" {print $1}' /etc/shadow       # accounts with an EMPTY password: must be none
sudo sh -c 'for f in /home/*/.ssh/authorized_keys; do echo "== $f"; awk "{print \$1, \$NF}" "$f"; done'
last -n 20                                         # recent logins
sudo journalctl -u <ssh-service> --since yesterday | grep -i 'failed\|invalid'
sudo fail2ban-client status sshd                   # banned IPs
sudo fail2ban-client set sshd unbanip <ip>         # unban a colleague who mistyped
```

Run it after each arrival or departure, and every few months.

## 10. Locked out of sudo? Ways back in

`PermitRootLogin no` only blocks root over SSH; the root account still exists.

1. **Give root a password** (`sudo passwd root`), keep it in a password manager. It works
   with `su -` from your account and on the provider's remote console (IPMI/KVM).
2. **Provider rescue mode**: reboot into it, mount `/`, fix `/etc/sudoers` or the group
   membership by hand. Works even if every password and key is lost.
3. **A second admin account** in the admin group (section 2).
4. **`PermitRootLogin prohibit-password`** instead of `no`: root may log in over SSH, with
   a key only. A common compromise.

## Checklist: new user

1. `useradd -m -s /bin/bash` (`-G <admin-group>` for an admin), temporary `passwd` + `passwd -e`, `id` to check
2. `usermod -aG` team group (and `ssh-users` if you use `AllowGroups`)
3. They run `ssh-copy-id` and test key login (`IdentitiesOnly=yes`); admins also test `sudo whoami`
4. Quota set on `/home`
5. Access to shared folders tested: `sudo -u <user> touch ...`
6. When every user has a key: `ssh-harden`

## Checklist: departure

`chage -E 0` → nologin → empty `authorized_keys` → end sessions → `find -user` → archive →
revoke keys elsewhere → `userdel -r` after retention.
