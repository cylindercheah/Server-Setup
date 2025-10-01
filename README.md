# Server-Setup

A practical guide and scripts to bring an Inspur i24 server online on a small LAN and enable multi-user remote desktop access via VNC.

## Contents
- Network bring-up walkthrough: `docs/establish-network-connection.md`
- LAN planning and quick commands: `server-setup.md`
- Batch user + VNC provisioning script: `create_with_vnc.sh`
- Hardware reference: `Inspur Server i24&NS5162M5 User Manual V1.2.pdf`

## Prerequisites
- A router, a switch, and the server NIC cabled per the docs
- Linux server with systemd (for VNC services)
- RHEL/CentOS-compatible package manager (`yum`) for the provided script

## 1) Bring the server online
Follow the step-by-step wiring and console access guide:

- Physical cabling, BMC/IPMI console, and OS network verification → see [`docs/establish-network-connection.md`](docs/establish-network-connection.md)

## 2) Small LAN plan (example)
See the quick reference in [`server-setup.md`](server-setup.md). Suggested defaults:

- Subnet: `192.168.10.0/24`
- Router LAN IP: `192.168.10.1`
- DHCP pool: `192.168.10.100–200`
- NAT/firewall: enabled on the router

### Router
- Set LAN IP `192.168.10.1/24`
- Enable DHCP pool `100–200`, DNS = router or `1.1.1.1`
- Ensure NAT from LAN→WAN is ON

### Switch
- Unmanaged: no changes
- Managed: make ports to server + router Access on VLAN 1 (or your chosen LAN VLAN). No trunks needed for a single LAN

### Server IP
- DHCP (easiest): connect and receive `192.168.10.x` with gateway `192.168.10.1`
- Static (example): adjust interface name and addresses to match your LAN plan

```bash
# Replace eth0 with your interface (see: ip -br link)
sudo ip link set dev eth0 up
sudo ip addr flush dev eth0
sudo ip addr add 192.168.10.10/24 dev eth0
sudo ip route replace default via 192.168.10.1
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf

# Verify
ping -c2 192.168.10.1
ping -c2 8.8.8.8
curl -I https://example.com
```

If you encounter “Operation not permitted”, become root or ensure you are not in a restricted container/namespace. Confirm the NIC name with `ip -br link`.

### Optional: Set a hostname
```bash
hostnamectl           # show current
sudo hostnamectl set-hostname mini-bicasl
sudo sh -c 'printf "127.0.1.1 mini-bicasl\n" >> /etc/hosts'
```

## 3) Batch-create desktop users with VNC
Use the script at [`create_with_vnc.sh`](create_with_vnc.sh) to provision users with matching account and VNC passwords and per-user VNC services.

- Installs dependencies if missing: TigerVNC Server, zsh
- Works with GNOME/Xfce/MATE desktops (X11)
- Uses systemd units `vncserver@:<display>.service`
- Optionally opens firewall ports if `firewalld` is running

### Run
```bash
sudo ./create_with_vnc.sh
```
The script is interactive:
- Prompts for a numeric range, creating users like `user001..user025`
- Uses a unified password (default in the script: `12345678`)
- Maps user N to display `:N` and TCP port `5900+N` (e.g., user001 → display :1 → TCP 5901)

### Connect (RealVNC/TigerVNC)
- Address: `<server-ip>:<display>` or `<server-ip>:590<display>` (e.g., `192.168.1.100:1` or `192.168.1.100:5901`)
- Encryption: set to “Prefer off” in RealVNC (TigerVNC does not support RealVNC encryption)
- Auth: VNC password equals the user’s account password by default

### Common management commands
```bash
# Check VNC service status
sudo systemctl status vncserver@:<display>.service

# Restart a VNC service
sudo systemctl restart vncserver@:<display>.service

# Tail logs
journalctl -u vncserver@:<display>.service -e

# List open firewall ports
firewall-cmd --list-ports
```

### Notes
- Script assumes systemd is available
- If a display `:N` is already taken (X11 socket/lock or another VNC user), that user will be skipped/handled as indicated by the script

## Files
- Network bring-up guide: [`docs/establish-network-connection.md`](docs/establish-network-connection.md)
- LAN quick reference: [`server-setup.md`](server-setup.md)
- VNC provisioning script: [`create_with_vnc.sh`](create_with_vnc.sh)
- Hardware manual: [`Inspur Server i24&NS5162M5 User Manual V1.2.pdf`](Inspur%20Server%20i24%26NS5162M5%20User%20Manual%20V1.2.pdf)

## Security
- Change default passwords immediately (script default is `12345678`)
- Restrict VNC access on the network or use a VPN/IP allow-list; consider SSH tunneling for VNC

***
