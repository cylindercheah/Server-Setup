# User and VNC Management Interactive Script (CentOS 7)

A powerful interactive Shell script purpose-built for CentOS 7, enabling system administrators to perform batch user provisioning of Linux accounts and automated configuration of TigerVNC remote desktop access.

## ✨ Features

- 🚀 **Batch User Creation** — Create multiple user accounts in a single operation
- 👤 **Single User Mode** — Interactively provision one account at a time with individual passwords
- 👥 **User Role Management** — Assign `admin` (wheel) or `standard` roles at creation time
- 🖥️ **VNC Configuration** — Automatically configure TigerVNC password and `.vnc` directory for each user
- 🔁 **systemd Integration (Recommended)** — Generate CentOS 7-compatible per-display unit files and enable auto-start on boot
- ⚡ **VNC Auto-start Only Mode** — Enable systemd auto-start for existing users without modifying their VNC password
- 🗑️ **Delete User (with VNC Cleanup)** — Remove an account and fully reclaim its VNC services, display locks, and firewall rules in one operation
- 🎨 **Colorful Interactive Interface** — Clear color-coded visual feedback (info, success, warning, error)
- 🔒 **Secure Password Input** — Passwords are never echoed to the terminal during input
- 🏠 **Private Home Permissions** — New user home directories are automatically tightened to `700`
- ⚙️ **Custom Shell Selection** — Reads available shells from `/etc/shells` and lets you choose interactively
- 🔍 **Smart Duplicate Detection** — Detects pre-existing users and skips creation without aborting the batch
- 📋 **Operation Summary** — Displays a consolidated result report after each operation
- 🛡️ **Display Conflict Resolution** — Detects display number conflicts at runtime and offers forced reclaim, auto-assign, or cancellation

## 📋 System Requirements

- **Operating System:** CentOS 7 (designed and tested specifically for CentOS 7)
- **Privileges:** Root or `sudo` access is mandatory
- **Shell:** Bash
- **For VNC functionality:** TigerVNC Server (`tigervnc-server`)
- **For VNC sessions:** A desktop environment (e.g., GNOME) and `xorg-x11-xauth`

### Install Required Packages

```bash
# Install TigerVNC server
sudo yum install -y tigervnc tigervnc-server

# Install xauth (required for VNC to start)
sudo yum install -y xorg-x11-xauth
```

> **Note:** CentOS 7 uses `yum`, not `dnf`. The script includes inline installation hints for relevant packages where applicable.

## 🚀 Quick Start

### 1. Make the Script Executable

```bash
chmod +x user_manager_centos7.sh
```

### 2. Run as Root

```bash
sudo ./user_manager_centos7.sh
```

## 📖 Usage Guide

After launching, the script displays the main menu:

```
==========================================
      用户和VNC管理交互式脚本
==========================================

请选择操作模式：

  1) 批量创建用户和配置VNC
  2) 创建单个用户和配置VNC
  3) 仅为现有用户配置VNC
  4) 仅为现有用户启用VNC开机自启
  5) 删除用户（含VNC清理）
  6) 退出

==========================================
```

> The interactive prompts are displayed in Chinese. This README provides an English description of all available modes.

---

### Mode 1: Batch Create Users and Configure VNC

Creates multiple user accounts in a single pass, all sharing the same login password and shell.

**Steps:**

1. Select option `1`
2. Enter a space-separated list of usernames, e.g. `alice bob charlie`
3. Enter the unified password (applied to all users)
4. Select default shell from the detected system shell list
5. (Optional) Enter a comment/display name for all users
6. Choose whether to configure VNC (`y/n`)
7. If yes, enter VNC password and optionally configure systemd auto-start with display number, resolution, and desktop session

**Example:**
```
请输入用户名列表（用空格分隔）：
alice bob charlie

请输入统一的用户密码：
********

系统中可用的Shell列表：
  1) /bin/bash
  2) /bin/zsh

请选择默认shell (输入序号) [默认: 1]:
1

是否为用户配置VNC？(y/n) [默认: n]:
y

请输入VNC密码：
********
```

In batch mode, display numbers are automatically incremented per user (e.g., `:2`, `:3`, `:4`, …).

---

### Mode 2: Create Single User and Configure VNC

Suitable for onboarding individual users with a unique password and personalised shell.

**Steps:**

1. Select option `2`
2. Enter username
3. Enter user password
4. Select default shell
5. (Optional) Enter a comment
6. Choose whether to configure VNC, and if yes provide VNC password and systemd settings

---

### Mode 3: Configure VNC for Existing Users Only

Set or reset the VNC password and optionally enable systemd auto-start for users that already exist on the system.

**Steps:**

1. Select option `3`
2. Review the list of selectable regular users displayed (UID ≥ 1000, excluding `nobody`)
3. Enter the space-separated list of usernames
4. Enter VNC password
5. Optionally enable systemd-managed VNC with display and resolution settings

---

### Mode 4: Enable VNC Auto-start for Existing Users (CentOS 7)

Enables systemd-managed VNC service for users who have already configured their own `~/.vnc/passwd`. This mode does **not** change any existing VNC passwords.

**Steps:**

1. Select option `4`
2. Review the displayed user list
3. Enter space-separated list of usernames
4. Enter starting display number
5. Enter VNC resolution
6. Choose whether to restrict to localhost
7. (Optional) Overwrite `~/.vnc/xstartup` — only prompted if you choose yes

> **Important:** Users must have a valid `/home/<username>/.vnc/passwd` before this mode will process them. The script will warn and skip any user who does not.

---

### Mode 5: Delete User (with VNC Cleanup)

Deprovisioning workflow that stops and removes all VNC resources for a user before deleting the account.

**Steps:**

1. Select option `5`
2. Review the displayed user list
3. Enter space-separated list of usernames
4. Review the pre-delete checklist displayed by the script
5. Confirm the overall deletion flow (`y` to continue)
6. Confirm deletion for each individual user (`y` required per user)

**What "VNC cleanup" removes (exact scope):**

| Resource | Action |
|---|---|
| `vncserver@:N.service` | Stopped, disabled, and the per-display unit file deleted |
| Display lock files | `/tmp/.X<N>-lock` and `/tmp/.X11-unix/X<N>` removed |
| Firewall port | `5900+N/tcp` removed from active zone (only if that exact rule exists) |
| VNC mapping | User's entry removed from `/etc/tigervnc/vncserver.users` |
| User account | `userdel -r <username>` removes the account and home directory |

**What it does NOT remove:**

- Other users' VNC mappings, services, or firewall rules
- Range-based firewall rules you added manually (e.g. `5900-5999/tcp`)
- If the user account does not exist, VNC cleanup still runs and the script continues normally

**Pre-delete checklist (recommended):**

- Verify the user has no active remote sessions or unsaved work
- Back up `/home/<username>` if data retention is required
- Confirm VNC access for that user is no longer needed
- Note that port range firewall rules will not be removed by this script

---

## 🔐 Security Notes

| Control | Implementation |
|---|---|
| **Root enforcement** | `check_root()` verifies `uid=0` before any operation; exits immediately if not met |
| **Password masking** | `read -rs` suppresses terminal echo for all password prompts |
| **Home directory isolation** | `chmod 700 /home/<username>` is applied to every newly created user; prevents other non-root users from browsing home directories |
| **VNC directory permissions** | `~/.vnc/` is created with `chmod 700`; only the owning user may read or traverse it |
| **VNC password file permissions** | `~/.vnc/passwd` is set to `chmod 600`; only the owning user may read or write the hashed password |
| **`xstartup` permissions** | `~/.vnc/xstartup` is set to `chmod 700`; executable by the owning user only |
| **Admin role via `wheel`** | `admin` users are added with `usermod -aG wheel <username>`. Privilege escalation still requires the user to authenticate via sudo — no passwordless root is granted by the script |
| **Display conflict resolution** | Before binding a display number, the script checks for existing `Xvnc` processes, mapping files, and legacy unit files, preventing silent port collisions |

> ⚠️ **Recommendations:**
> - Use strong, unique passwords for both the user account and VNC.
> - Rotate VNC passwords periodically, especially for long-running sessions.
> - Prefer the `localhost`-only VNC option when SSH tunneling is available, to avoid exposing VNC ports directly to the network.

## 📝 FAQ

### Q: Script shows "requires root privileges"?
**A:** Run the script with `sudo ./user_manager_centos7.sh`.

### Q: "vncpasswd command not found"?
**A:** Install TigerVNC first:
```bash
sudo yum install -y tigervnc tigervnc-server
```

### Q: "缺少 xauth，TigerVNC 无法启动" (missing xauth)?
**A:** Install the xauth package:
```bash
sudo yum install -y xorg-x11-xauth
```

### Q: What happens if a username already exists?
**A:** The script detects it, prints a warning, and skips account creation. VNC configuration can still be applied to the existing user.

### Q: What is the difference between `admin` and `standard`?
**A:** `admin` users are added to the `wheel` group via `usermod -aG wheel <username>`, enabling them to use `sudo`. `standard` users are not in `wheel` and have no elevated privilege pathway. Home directory permissions (700) are enforced regardless of role.

### Q: How do I change a user's role after creation?
**A:** The CentOS 7 variant does not include an interactive role-modify mode. Use the standard system tools directly:
```bash
# Promote to admin
sudo usermod -aG wheel <username>

# Demote to standard
sudo gpasswd -d <username> wheel
```

### Q: How do I connect to a VNC session?
**A:** Use any VNC client and connect to `<server-ip>:<port>`, where `port = 5900 + display number`.

| Display | Port |
|---|---|
| `:2` | `5902` |
| `:3` | `5903` |
| `:4` | `5904` |

Check active display mappings in `/etc/tigervnc/vncserver.users`.

### Q: Must the VNC password be the same as the login password?
**A:** No. VNC and Linux system passwords are entirely independent.

### Q: What is a "legacy unit file" in CentOS 7 context?
**A:** CentOS 7's TigerVNC does not support the template-plus-mapping approach used in newer RHEL/AlmaLinux. Instead, this script generates a standalone systemd unit file at `/etc/systemd/system/vncserver@:<N>.service` for each display number, with the username hard-coded inside. This is the standard CentOS 7 method.

---

## 🔧 Recommended Workflow (CentOS 7)

### First-time Setup (one-time)

1. Install TigerVNC and required dependencies:
```bash
sudo yum install -y tigervnc tigervnc-server xorg-x11-xauth
```

2. Open firewall ports for the display numbers you plan to use:
```bash
# Single port example (for display :2)
sudo firewall-cmd --permanent --zone=public --add-port=5902/tcp

# Or open the common VNC range
sudo firewall-cmd --permanent --zone=public --add-port=5900-5999/tcp

sudo firewall-cmd --reload
```

> Ensure the rule is added to the active zone (typically `public`). Run `firewall-cmd --get-active-zones` to confirm.

### Daily Usage

1. Run the script:
```bash
sudo ./user_manager_centos7.sh
```

2. Select the appropriate mode and follow the prompts.

3. Verify the VNC service is running:
```bash
sudo systemctl status vncserver@:2.service
```

4. Connect via a VNC client:
```
<server-ip>:5902   (for display :2)
<server-ip>:5903   (for display :3)
```

---

## 🛠️ Technical Details

### Created User Properties

| Property | Value |
|---|---|
| Home directory | `/home/<username>` (auto-created) |
| Home permissions | `700` (`drwx------`) |
| Default shell | Selected interactively from `/etc/shells` |
| Password | Set via `chpasswd` |
| Admin role | `wheel` group membership via `usermod -aG wheel` |

### VNC Configuration Layout

| Path | Permissions | Purpose |
|---|---|---|
| `/home/<username>/.vnc/` | `700` (`drwx------`) | VNC configuration directory |
| `/home/<username>/.vnc/passwd` | `600` (`-rw-------`) | Hashed VNC password |
| `/home/<username>/.vnc/xstartup` | `700` (`-rwx------`) | Desktop session startup script |
| `/etc/systemd/system/vncserver@:<N>.service` | `644` | Per-display systemd unit (CentOS 7 compatible) |
| `/etc/tigervnc/vncserver.users` | `644` | Display-to-user mapping |

### CentOS 7 systemd Unit Behaviour

The script generates a dedicated unit file for each display number rather than relying on the template-based approach. Key behaviours:

- `ExecStartPre` kills any stale Xvnc process and removes lock files before starting
- `Type=forking` is used for compatibility with the CentOS 7 TigerVNC `vncserver` wrapper
- The unit is tied to a specific username via `User=` and `Group=`

---

## ⚠️ About Manual `vncserver`

- Manually invoking `vncserver` from the command line is **not recommended** for persistent sessions
- Manual sessions may acquire an unexpected display number (e.g. `:4` instead of `:2`), resulting in mismatched firewall ports
- Manual sessions are not recovered automatically after a server reboot
- Always prefer the systemd-managed path provided by this script

---

## 📄 License

MIT License

## 🤝 Contributing

Issues and Pull Requests are welcome!

---

**Note:** Always test in a non-production environment first. Each destructive operation (user deletion, VNC cleanup, display reclaim) requires explicit confirmation. Back up `/home/<username>` before removing any account if data retention may be needed.
