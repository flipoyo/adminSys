# 03 — Declaring an SSH public key for a user

*Created: 2026-11-27*

SSH ties a key to a user through one file on the server: `/home/<user>/.ssh/authorized_keys`,
one public key per line. Whoever holds the matching **private** key logs in as that user.
Never copy a private key to the server; one key per computer.

## A. Your own key, from your computer (easiest)

```bash
ssh-copy-id -i ~/.ssh/<key>.pub <user>@<server-ip>   # asks the account password once
ssh -i ~/.ssh/<key> <user>@<server-ip>               # test: no password asked
```

## B. By hand, on the server, logged in as that user

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
echo "ssh-ed25519 AAAA...  me@laptop" >> ~/.ssh/authorized_keys   # the .pub line
chmod 600 ~/.ssh/authorized_keys
```

## C. An admin adds a key for another user

```bash
U=alice
sudo mkdir -p /home/$U/.ssh
echo "ssh-ed25519 AAAA...  alice@laptop" | sudo tee -a /home/$U/.ssh/authorized_keys
sudo chown -R $U:$U /home/$U/.ssh
sudo chmod 700 /home/$U/.ssh && sudo chmod 600 /home/$U/.ssh/authorized_keys
sudo restorecon -R /home/$U/.ssh          # SELinux systems only (rhel family); skip on Debian/Ubuntu
```

## Check, revoke

```bash
cat ~/.ssh/authorized_keys                # declared keys
nano ~/.ssh/authorized_keys               # delete a line = revoke that computer
```

## A key from the agent, from an SSH config alias

On your computer, `~/.ssh/config`:

```
Host myserver
    HostName <server-ip>
    User <user>
    IdentityFile ~/.ssh/<key>
    IdentitiesOnly yes
    ServerAliveInterval 60
```

Then `ssh myserver`, `scp f myserver:~/`, VS Code Remote-SSH and `rsync` all use the alias.
`bin/sys ssh-agent` (on the server) or your desktop's agent (on the laptop) means the key
passphrase is asked once per session.

## If it still asks for a password

- Rights: `~/.ssh` is 700, `authorized_keys` is 600, both owned by the user.
- The pasted key is **one** line starting with `ssh-ed25519`.
- Server side: `sudo journalctl -u sshd -n 20` (the unit is `ssh` on Debian/Ubuntu).
- Client side: `ssh -v <user>@<server-ip>`.
