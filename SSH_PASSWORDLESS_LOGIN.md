# SSH passwordless login

## What this is

SSH key login lets your **PC** connect to a **server** without typing the server password each time. You still type a password once when installing the key (`ssh-copy-id`). After that, `ssh user@host` uses your key instead.

Useful when you SSH often (lab machines, VMs, deploy hosts).

## How it works

1. On your **PC**: `ssh-keygen` creates a **key pair**
   - **Private key** (e.g. `~/.ssh/id_ed25519`) — stays on your PC, never share it
   - **Public key** (same name + `.pub`) — safe to copy anywhere
2. Copy the **public key** into the server account’s `~/.ssh/authorized_keys`
3. When you SSH, your PC proves it has the matching private key; the server checks `authorized_keys`

Tools like `ssh-copy-id` do step 2 for you.

## Multiple servers

- **One key per PC** (per user account) is enough.
- Use the **same** public key on every server: run `ssh-copy-id` once per `user@host` (or paste the same `.pub` line).
- **WSL and Windows** are separate PCs for SSH — each has its own `~/.ssh`. Either copy the same key to both clients, or add **both** `.pub` lines to `authorized_keys`.

---

## Normal setup

Replace `USER`, `HOST`, and `PORT` (omit `-p` if port is 22).

### WSL / Linux / macOS (run on PC)

```bash
ssh-keygen                       # once, if you have no key in ~/.ssh yet
ssh-copy-id -p PORT USER@HOST
ssh -p PORT USER@HOST            # test — should not ask for server password
```

### Windows PowerShell (run on PC)

```powershell
ssh-keygen
ssh-copy-id -p PORT USER@HOST
ssh -p PORT USER@HOST
```

If `ssh-copy-id` is missing on Windows (adjust `.pub` path if your key name differs):

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh -p PORT USER@HOST "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

No need for `-i` unless you use a non-default key path.

---

## Still asks for password?

### 1. From PC (WSL / Mac / Windows)

```bash
# WSL / Mac
ssh -p PORT -vvv USER@HOST 2>&1 | grep -E 'Offering|succeeded|refused|Permission'
```

```powershell
# Windows
ssh -p PORT -vvv USER@HOST 2>&1 | Select-String "Offering|succeeded|refused|Permission"
```

- `Offering public key` then password → server **rejected** the key (permissions, wrong key, or key not in `authorized_keys`).
- `Authentication succeeded (publickey)` → key works.

Confirm PC key fingerprint:

```bash
ssh-keygen -lf ~/.ssh/id_ed25519.pub
```

```powershell
ssh-keygen -lf $env:USERPROFILE\.ssh\id_ed25519.pub
```

### 2. On the server (log in with password first)

**Auth log** (common on RHEL/Fedora):

```bash
sudo tail -30 /var/log/secure
```

Try SSH from PC once, run `tail` again. Example:

```text
Authentication refused: bad ownership or modes for directory /home/USER
```

→ fix **home directory** permissions (below).

**Key file present?**

```bash
whoami
cat ~/.ssh/authorized_keys
ssh-keygen -lf ~/.ssh/authorized_keys
```

Fingerprint must match your PC’s `.pub`.

### 3. Fix home / `.ssh` permissions (on server)

```bash
ls -ld ~ ~/.ssh ~/.ssh/authorized_keys
```

| Path | Should be |
|------|-----------|
| `~` | Owner = your user; **not** group-writable (not `drwxrwx---` / `770`) |
| `~/.ssh` | `700` (`drwx------`), owner = your user |
| `~/.ssh/authorized_keys` | `600` (`-rw-------`), owner = your user |

**Fix example** (replace `USER`):

```bash
chmod g-w ~              # or: chmod 750 ~
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
chown -R USER:USER ~/.ssh
```

SELinux (if `getenforce` → `Enforcing`):

```bash
restorecon -R -v ~/.ssh
```

Test again from PC: `ssh -p PORT USER@HOST`.

### 4. Duplicate keys in `authorized_keys`

Harmless. Remove extra identical lines:

```bash
sort -u ~/.ssh/authorized_keys -o ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

---

## Quick reference

| Step | Where |
|------|--------|
| `ssh-keygen` | PC (once per client: WSL **or** Windows **or** Mac) |
| `ssh-copy-id` | PC (each `user@host`) |
| `ssh` test | PC |
| `ssh -vvv` | PC if broken |
| `sudo tail /var/log/secure` | Server if broken |
| `ls -ld ~ ~/.ssh` | Server if log mentions bad ownership/modes |
