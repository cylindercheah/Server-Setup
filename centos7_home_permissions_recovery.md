# CentOS 7 /home Directory Permissions Recovery Guide

This document summarizes the steps taken to recover a CentOS 7 server after the recursive application of `sudo chgrp -R wheel /home/` and `sudo chmod -R 750 /home/`, which resulted in widespread user lockouts and broken services.

## 1. The Root Cause of the Lockout

The command `chmod -R 750 /home/` applied the `750` permission directly to the `/home` directory itself. In Linux, permissions break down as follows:
* **7 (Owner - `root`)**: Read, Write, Execute.
* **5 (Group - `wheel`)**: Read, Execute.
* **0 (Others - Normal Users)**: No access.

Linux relies on **Directory Traversal** rules. To access a file like `/home/austin/file.txt`, the user `austin` must have the Execute (`x`) permission on every parent directory (in this case, `/home`). Because normal users were categorized as "Others" with `0` access, they were blocked from "passing through" `/home` to reach their own files, resulting in `Permission denied` errors and broken shell environments (e.g., dropping to `-bash-4.2$`).

Furthermore, `chgrp -R wheel /home/` stripped away CentOS's "User Private Group" (UPG) system, where users normally own their directories as `user:user`. This broke strict services like SSH and VNC.

## 2. Restoring Basic User Access

To allow users to traverse the `/home` directory and restore baseline security, the "front doors" of the directories must be fixed.

**Fix the top-level `/home` directory:**
```bash
sudo chown root:root /home
sudo chmod 755 /home
```

**Lock individual user directories to prevent unauthorized cross-user access:**
```bash
sudo chmod 700 /home/*
```
*(This ensures `/home/austin` is only accessible by `austin`, while the top-level `/home` can be traversed by everyone).*

## 3. Repairing Broken Services (VNC & SSH)

Services like VNC and SSH are highly sensitive to file permissions. If a VNC password file or an SSH key is readable by anyone other than the owner, the service will refuse to run. The recursive changes previously applied broke these configurations.

**Run this script to surgically repair VNC and SSH permissions across all users:**

```bash
for dir in /home/*; do
    if [ -d "$dir" ]; then
        user=$(basename "$dir")
        
        # Verify the folder matches a real user
        if id "$user" >/dev/null 2>&1; then
            echo "Repairing permissions for user: $user"
            
            # Restore strict user:user ownership
            sudo chown -R "$user":"$user" "$dir"
            
            # Secure SSH Keys
            if [ -d "$dir/.ssh" ]; then
                sudo chmod 700 "$dir/.ssh"
                sudo find "$dir/.ssh" -type f -exec chmod 600 {} +
            fi
            
            # Secure VNC Configurations
            if [ -d "$dir/.vnc" ]; then
                sudo setfacl -R -b "$dir/.vnc" # Strip ACLs
                sudo chmod 700 "$dir/.vnc"
                if [ -f "$dir/.vnc/passwd" ]; then
                    sudo chmod 600 "$dir/.vnc/passwd"
                fi
                if [ -f "$dir/.vnc/xstartup" ]; then
                    sudo chmod 700 "$dir/.vnc/xstartup"
                fi
            fi
        fi
    fi
done
```
*Note: VNC services (e.g., `vncserver@:1.service`) must be restarted after applying these fixes.*

## 4. SELinux Considerations

CentOS 7 utilizes SELinux, which operates independently of standard file permissions. When massive recursive permission changes occur, SELinux contexts can become mismatched, causing hidden access denials.

**To restore default SELinux contexts for a user (e.g., austin):**
```bash
sudo restorecon -Rv /home/austin
```

## 5. Best Practices for Group Access

**Do NOT use `chgrp` on personal user directories (e.g., `/home/username`).** This will continually break CentOS security defaults and services. 

Depending on your goal, use one of these two correct methods:

### Scenario A: Seamless Admin Access (Using ACLs)
If administrators (the `wheel` group) need to browse personal user directories without typing `sudo` every time, use Access Control Lists (ACLs). This adds a secondary rule without destroying the user's primary ownership.

```bash
# Grant 'wheel' read/traverse access to all current items
sudo setfacl -R -m g:wheel:rX /home/

# Set a default rule to grant 'wheel' access to all future items
sudo setfacl -R -d -m g:wheel:rX /home/
```

### Scenario B: Collaborative Team Access (Using a Shared Folder)
If users need to share files (e.g., a lab research group), create a dedicated directory with a SetGID bit to enforce group ownership on all new files.

```bash
sudo mkdir /home/lab_shared
sudo chgrp -R lab_users /home/lab_shared
sudo chmod -R 2770 /home/lab_shared
```
*(The `2` ensures that any new file created in `/home/lab_shared` is automatically owned by the `lab_users` group).*

---
**Summary created:** August 6, 2026