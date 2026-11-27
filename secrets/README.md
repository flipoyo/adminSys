# secrets/

Everything in this folder **except this file** is encrypted by git-crypt
(rule in `../.gitattributes`). The repository is public: what you commit here
is published as unreadable bytes.

Use it for what is specific to your servers and should not be readable by
everyone: inventories, real IP addresses and host names, runbooks, provider
notes, ssh config snippets.

- Enable once, **before the first commit of a secret**: `bin/sys crypt-init`
- Check before every push: `git-crypt status -e` (files must be listed as encrypted)
- Unlock on a new machine: `git-crypt unlock /path/to/adminsys.key`

Read [docs/04-secrets-git-crypt.md](../docs/04-secrets-git-crypt.md) first: what git-crypt does **not** hide, and what happens if you lose the key.
