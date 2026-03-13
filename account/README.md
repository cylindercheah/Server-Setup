# User and VNC Management Interactive Script

A powerful interactive Shell script for batch creating Linux users and configuring VNC remote desktop access.

## ✨ Features

- 🚀 **Batch User Creation** - Create multiple user accounts at once
- 👤 **Single User Mode** - Quickly create individual users
- 🖥️ **VNC Configuration** - Automatically configure VNC remote desktop for users
- 🎨 **Colorful Interactive Interface** - Clear visual feedback (info, success, warning, error)
- 🔒 **Secure Password Input** - Passwords are hidden during input
- ⚙️ **Custom Shell** - Automatically read available shells (bash, zsh, fish, etc.) from system for user selection
- 🔍 **Smart Checks** - Automatically detect existing users to avoid duplicates
- 📋 **Operation Summary** - Detailed results displayed after completion

## 📋 System Requirements

- Linux operating system (Ubuntu, Debian, RHEL/AlmaLinux, etc.)
- Root privileges (must run with sudo)
- `bash`
- For VNC functionality: TigerVNC server utilities
- For a full VNC desktop: at least one desktop session such as `XFCE`, `GNOME`, `MATE`, or `LXQt`

### Install VNC / Desktop Packages (Optional)

The script can detect missing TigerVNC packages and prompt to install them.

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install tigervnc-standalone-server tigervnc-tools xauth xfonts-base
```

**RHEL / AlmaLinux / Rocky:**
```bash
sudo dnf install tigervnc-server xauth xorg-x11-fonts-Type1 xorg-x11-fonts-misc
```

**Install XFCE on AlmaLinux / RHEL-like hosts (recommended for VNC):**
```bash
sudo dnf install epel-release
sudo dnf group install Xfce
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
  4) Exit

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
7. Choose whether to allow direct VNC client connections or keep VNC bound to localhost only
8. Choose the VNC desktop mode

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

Allow direct VNC client connections? (y/n) [default: n]:
n

Please select VNC desktop mode:
  1) Auto select (recommended; will use XFCE on this host)
  2) Minimal X11
  3) XFCE
  4) GNOME Classic
  5) GNOME

Please enter number [default: 1]:
1
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
7. Choose direct access or localhost-only mode
8. Choose the VNC desktop mode

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

Allow direct VNC client connections? (y/n) [default: n]:
n

Please select VNC desktop mode:
  1) Auto select (recommended; will use XFCE when available)
  2) Minimal X11
  3) XFCE
  4) GNOME Classic
  5) GNOME

Please enter number [default: 1]:
1
```

### Mode 3: Configure VNC for Existing Users Only

Suitable for batch configuring VNC access for existing users.

**Steps:**

1. Select option `3`
2. Enter username list (space-separated)
3. Enter VNC password
4. Choose direct access or localhost-only mode
5. Choose the VNC desktop mode

**Example:**
```
Please enter username list (space-separated):
alice bob charlie

Please enter VNC password:
********

Allow direct VNC client connections? (y/n) [default: n]:
n

Please select VNC desktop mode:
  1) Auto select (recommended; will use XFCE when available)
  2) Minimal X11
  3) XFCE
  4) GNOME Classic
  5) GNOME

Please enter number [default: 1]:
1
```

## 🖥️ VNC Desktop Modes

- **Auto** - Recommended. Prefer a stable full desktop, currently `XFCE` if installed.
- **XFCE** - Recommended full desktop mode for VNC. Includes panel, desktop background, file manager, and normal window management.
- **Minimal X11** - Fallback mode. Starts a very small X11 session for troubleshooting or very low-resource usage.
- **GNOME Classic / GNOME** - Available when installed, but usually less stable than `XFCE` over TigerVNC.

The script now favors `XFCE` when it is available. If no lightweight full desktop is installed, `auto` may fall back to `Minimal X11`.

## 🔌 VNC Connection Model

- **Recommended** - Keep VNC on `localhost` and connect through an SSH tunnel.
- **Direct VNC** - Optional, but requires opening firewall ports and is less secure on shared networks.

### Recommended SSH Tunnel Workflow

If the script reports a session such as `display :11 (port 5911)`, connect from your laptop or workstation with:

```bash
ssh -N -L 25911:localhost:5911 username@server-ip
```

Then connect your VNC client to:

```text
localhost:25911
```

You can choose any free local port on your client machine. Only the right side of `-L` must match the server's VNC port.

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
- Ubuntu/Debian: `sudo apt install tigervnc-standalone-server tigervnc-tools`
- CentOS/RHEL: `sudo dnf install tigervnc-server`

### Q: Which VNC desktop mode should I choose?
**A:** Choose `Auto` or `XFCE`. `XFCE` is the recommended full desktop for TigerVNC on this setup.

### Q: Why not use GNOME by default?
**A:** GNOME often needs more session/system integration and is more likely to show black screens or startup issues under TigerVNC. `XFCE` is usually much more reliable.

### Q: What happens if user already exists?
**A:** Script will detect and skip creation, but can still configure VNC for that user.

### Q: Can I set different passwords for different users?
**A:** Use "Single User Mode" (option 2) to set different passwords for each user. Batch mode uses unified password.

### Q: Must VNC password be the same as user password?
**A:** No, VNC password can be different from user password.

### Q: Do I still need to manually run `vncserver :1`?
**A:** Usually no. The script now writes the VNC config, selects a free display automatically, starts the VNC session, and prints the display/port to use.

### Q: How to connect to VNC?
**A:** Prefer SSH tunneling. If the script says `display :10 (port 5910)`, run:
```bash
ssh -N -L 25910:localhost:5910 username@server-ip
```
Then point your VNC client to `localhost:25910`.

## 🛠️ Technical Details

### Created User Features
- Home directory automatically created (`/home/username`)
- Select default shell from system available shells (read from `/etc/shells`)
- User password automatically set

### VNC Configuration
- TigerVNC user config: `/home/username/.config/tigervnc/config`
- Legacy/direct-launch config: `/home/username/.vnc/legacy-xdg/tigervnc/config`
- VNC password files: `/home/username/.config/tigervnc/passwd` and `/home/username/.vnc/passwd`
- Startup files: `/home/username/.vnc/xstartup` and `/home/username/.Xclients`
- Typical full desktop mode on this setup: `XFCE`

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
