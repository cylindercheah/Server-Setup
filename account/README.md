# User and VNC Management Interactive Script

A powerful interactive Shell script for batch creating Linux users and configuring VNC remote desktop access.

## ✨ Features

- 🚀 **Batch User Creation** - Create multiple user accounts at once
- 👤 **Single User Mode** - Quickly create individual users
- 🖥️ **VNC Configuration** - Automatically configure VNC remote desktop for users
- 🔁 **systemd Integration (Recommended)** - Auto-write display mapping and enable auto-start VNC service
- 🗑️ **Delete User (with VNC Cleanup)** - Remove account and reclaim related VNC resources in one flow
- 🎨 **Colorful Interactive Interface** - Clear visual feedback (info, success, warning, error)
- 🔒 **Secure Password Input** - Passwords are hidden during input
- ⚙️ **Custom Shell** - Automatically read available shells (bash, zsh, fish, etc.) from system for user selection
- 🔍 **Smart Checks** - Automatically detect existing users to avoid duplicates
- 📋 **Operation Summary** - Detailed results displayed after completion

## 📋 System Requirements

- Linux operating system (Ubuntu, Debian, CentOS, etc.)
- Root privileges (must run with sudo)
- bash or zsh shell
- For VNC functionality: TigerVNC or TightVNC

### Install VNC (Optional)

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install tigervnc-common
```

**CentOS/RHEL:**
```bash
sudo yum install tigervnc-server
```

## 🚀 Quick Start

### 1. Download Script

```bash
wget https://your-repo/user_manager.sh
# or
curl -O https://your-repo/user_manager.sh
```

### 2. Add Execute Permission

```bash
chmod +x user_manager.sh
```

### 3. Run Script

```bash
sudo ./user_manager.sh
```

## 📖 Usage Guide

After running the script, you'll see the main menu:

```
==========================================
   User and VNC Management Script
==========================================

Please select operation mode:

  1) Batch create users and configure VNC
  2) Create single user and configure VNC
  3) Configure VNC for existing users only
  4) Delete user (with VNC cleanup)
  5) Exit

==========================================
```

### Mode 1: Batch Create Users and Configure VNC

Suitable for creating multiple user accounts at once.

**Steps:**

1. Select option `1`
2. Enter username list (space-separated), e.g., `alice bob charlie`
3. Enter unified password (same password for all users)
4. Select default shell from system available shells (such as bash, zsh, fish, etc.)
5. Choose whether to configure VNC (y/n)
6. If configuring VNC, enter VNC password

**Example:**
```
Please enter username list (space-separated):
alice bob charlie

Please enter unified user password:
********

Available shells in system:
  1) /bin/bash
  2) /bin/zsh
  3) /bin/sh
  4) /usr/bin/fish

Please select default shell (enter number) [default: 1]:
2

Configure VNC for users? (y/n) [default: n]:
y

Please enter VNC password:
********
```

### Mode 2: Create Single User and Configure VNC

Suitable for creating individual user accounts with different passwords.

**Steps:**

1. Select option `2`
2. Enter username
3. Enter user password
4. Select default shell from system available shells
5. Choose whether to configure VNC
6. If configuring VNC, enter VNC password

**Example:**
```
Please enter username:
david

Please enter user password:
********

Available shells in system:
  1) /bin/bash
  2) /bin/zsh
  3) /bin/sh
  4) /usr/bin/fish

Please select default shell (enter number) [default: 1]:
2

Configure VNC for user david? (y/n) [default: n]:
y

Please enter VNC password:
********
```

### Mode 3: Configure VNC for Existing Users Only

Suitable for batch configuring VNC access for existing users.

**Steps:**

1. Select option `3`
2. Enter username list (space-separated)
3. Enter VNC password

**Example:**
```
Please enter username list (space-separated):
alice bob charlie

Please enter VNC password:
********
```

### Mode 4: Delete User (with VNC Cleanup)

Suitable for account deprovisioning while reclaiming that user's VNC resources.

**Steps:**

1. Select option `4`
2. Enter username list to delete (space-separated)
3. Confirm deletion when prompted (`y` required)

**Example:**
```
Please enter usernames to delete (space-separated):
alice bob

Confirm delete user alice (with VNC service/port cleanup)? (y/n) [default: n]:
y
```

**What “VNC cleanup” removes (exact scope):**

- Stops and disables each mapped `vncserver@:N.service` for that user
- Reclaims display `:N` (terminates related Xvnc processes and removes `/tmp/.X<N>-lock` and `/tmp/.X11-unix/X<N>`)
- Removes corresponding firewall port `5900+N/tcp` from the active zone (only if that exact port rule exists)
- Removes that user’s entries from `/etc/tigervnc/vncserver.users`
- Runs `firewall-cmd --reload` once if any port rule was removed
- Finally runs `userdel -r username` to remove user account and home directory

**What it does NOT remove:**

- Other users’ VNC mappings, services, or ports
- Unrelated firewall rules (for example, manual range rule `5900-5999/tcp`)
- If the user does not exist, script still performs VNC cleanup only and continues

**Pre-delete checklist (recommended):**

- Ensure the user has no unsaved remote session/work
- Back up `/home/username` first if data retention is needed
- Confirm that VNC access for that user is no longer required (`:N` / `5900+N`)
- If you opened a firewall port range (such as `5900-5999/tcp`), note the script will not remove that range rule

## 🔐 Security Notes

- ✅ Script requires root privileges and will check automatically
- ✅ Passwords are hidden during input
- ✅ VNC password file permissions automatically set to 600 (user read/write only)
- ✅ VNC directory permissions automatically set to 700 (user access only)
- ⚠️ Strong passwords are recommended
- ⚠️ Regularly update user passwords

## 📝 FAQ

### Q: Script shows "requires root privileges"?
**A:** Run the script with `sudo ./user_manager.sh`.

### Q: Shows "vncpasswd command not found"?
**A:** Need to install VNC service first:
- Ubuntu/Debian: `sudo apt install tigervnc-common`
- CentOS/RHEL: `sudo yum install tigervnc-server`

### Q: What happens if user already exists?
**A:** Script will detect and skip creation, but can still configure VNC for that user.

### Q: Can I set different passwords for different users?
**A:** Use "Single User Mode" (option 2) to set different passwords for each user. Batch mode uses unified password.

### Q: Must VNC password be the same as user password?
**A:** No, VNC password can be different from user password.

### Q: How to start VNC service?
**A:** Use `systemd` (supported by the script). Avoid manually starting deprecated `vncserver`.

If you choose “Use systemd to manage VNC (recommended)” in the script, it will automatically:
- Write display mapping to `/etc/tigervnc/vncserver.users` (e.g. `:2=user1`)
- Write user VNC config to `/home/username/.vnc/config` (geometry/session/localhost)
- Enable and start `vncserver@:N.service`

You can verify manually:
```bash
sudo systemctl status vncserver@:2.service
sudo systemctl status vncserver@:3.service
```

### Q: In option 4, what exactly will “VNC cleanup” remove?
**A:** It cleans resources based on that user’s mappings in `/etc/tigervnc/vncserver.users`:
- stop/disable `vncserver@:N.service`
- reclaim display session and lock files
- remove firewall allow rule for `5900+N/tcp` if present
- remove mapped entries from the mapping file

Then it runs `userdel -r` to remove the user and home directory.

### Q: How to connect to VNC?
**A:** Use a VNC client to connect to: `server-ip:port`, where `port = 5900 + display number`.

Examples:
- `:2 -> 5902`
- `:3 -> 5903`
- `:4 -> 5904`

You can check display mappings in `/etc/tigervnc/vncserver.users`.

## 🔧 Recommended Workflow (AlmaLinux/RHEL)

### First-time setup (one-time)

1. Install TigerVNC:
```bash
sudo dnf install -y tigervnc tigervnc-server
```

2. Open firewall rules (based on your needs):
```bash
# Single-port example
sudo firewall-cmd --permanent --zone=public --add-port=5904/tcp

# Or open common VNC range
sudo firewall-cmd --permanent --zone=public --add-port=5900-5999/tcp

sudo firewall-cmd --reload
```

> Important: add rules in the active NIC zone (for example `public`).

2.1 Optional: configure via firewall GUI app (`firewall-config`)

If you prefer GUI setup:

1. Install and launch:
```bash
sudo dnf install -y firewall-config
sudo firewall-config
```

2. In the top-right of the app:
- enable `Permanent`
- select the correct `Zone` (usually the active one, e.g. `public`)

3. In the `Ports` tab add:
- single-port example: `5904` + `tcp`
- or range: `5900-5999` + `tcp`

4. Click `Reload Firewall` (or run):
```bash
sudo firewall-cmd --reload
```

> Tip: if rules are added to the wrong zone, or only runtime rules are added without permanent save, VNC may still fail to connect.

### Daily usage (after setup)

1. Run script:
```bash
sudo ./user_manager.sh
```

2. In the script choose:
- Configure VNC = `y`
- Use systemd VNC = `y`
- Enter display number (e.g. `2`, `3`)
- Enter resolution (e.g. `1920x1080`)

3. Connect with RealVNC directly:
- `server-ip:5902` (for `:2`)
- `server-ip:5903` (for `:3`)

## ⚠️ About Manual `vncserver`

- `vncserver` is now shown as deprecated in current TigerVNC path
- Manually started sessions may drift to another display (e.g. `:4`), causing unstable port expectations
- Manual sessions usually do not auto-recover after reboot

## 🛠️ Technical Details

### Created User Features
- Home directory automatically created (`/home/username`)
- Select default shell from system available shells (read from `/etc/shells`)
- User password automatically set

### VNC Configuration
- VNC config directory: `/home/username/.vnc/`
- Password file: `/home/username/.vnc/passwd`
- Directory permissions: 700 (drwx------)
- Password file permissions: 600 (-rw-------)

## 📄 License

MIT License

## 🤝 Contributing

Issues and Pull Requests are welcome!

## 📧 Contact

For questions or suggestions, please contact via:
- Submit an Issue
- Send an email

---

**Note:** Please use this script carefully and ensure you understand the impact of each operation. It's recommended to test in a development environment first.
