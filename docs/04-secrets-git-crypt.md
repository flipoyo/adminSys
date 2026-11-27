# 04 — Private details in a public repository (git-crypt)

*Created: 2026-11-27*

This repository is public. Some administration knowledge is not: real IP addresses, host
names, who has access, provider notes. [git-crypt](https://github.com/AGWA/git-crypt)
encrypts the files under `secrets/` when you commit and decrypts them when you check out,
so they live in the same repository as the scripts but are unreadable to everyone else.

## 1. Set up (once, before the first secret)

```bash
git init -b main                       # if not already a repository
bin/sys crypt-init --export-key ~/safe/adminsys.key
```

`crypt-init` runs `git-crypt init` and saves the symmetric key **outside** the repository
(it refuses a path inside it). Back that file up somewhere independent: a password
manager, an encrypted USB stick. It is the only way to read `secrets/` on another machine.

To let colleagues unlock with their own GPG key, no key file to pass around:

```bash
bin/sys crypt-init --gpg-user colleague@example.org
```

(or later, by hand: `git-crypt add-gpg-user <KEYID>`.)

## 2. Daily use

```bash
cp my-inventory.md secrets/            # any file under secrets/ is encrypted
git add secrets
git-crypt status -e                    # MUST list your file as encrypted: check before every push
git commit -m "inventory" && git push
```

On a new machine: `git clone`, then `git-crypt unlock /path/to/adminsys.key`
(or just `git-crypt unlock` with a GPG identity added as above). Before unlocking, the
files are opaque binary blobs.

## 3. What git-crypt does *not* protect

| Visible to everyone | Why |
|---|---|
| file **names** and folder layout under `secrets/` | only contents are encrypted |
| commit messages, dates, authors | git metadata is not encrypted |
| file **sizes**, and that a file changed | ciphertext length follows the plaintext |
| anything **outside** `secrets/` | no rule covers it |

So: neutral file names, no secrets in commit messages, and run
`bin/sys check-public` before publishing anything.

## 4. Rules that keep it safe

1. **Initialise before the first commit of a secret.** A file committed in clear text, even
   once, stays in history forever; deleting it later does not help. `crypt-init` refuses if
   something is already tracked under `secrets/`.
2. **The key is the secret.** Anyone with the key can read *every version ever committed*
   under `secrets/`, including future clones of the public repository. If the key leaks,
   change the real secrets (passwords, keys, addresses), not just the git-crypt key.
3. **Lose the key and have no GPG user, and the content is gone.** Keep two copies.
4. **`.gitattributes` itself must stay readable** (it is, by the last rule in that file);
   do not put it under `secrets/`.
5. **Use it for small text files.** It is not meant for large binaries or for private
   keys you could simply not commit (a private SSH key never belongs in any repository).

## 5. When not to use git-crypt

If nobody else needs the secret and you do not want it in a public repository at all, keep
it in a password manager. git-crypt fits *shared, low-volume, text* knowledge that should
travel with the scripts.
