# Small LAN + Server — Fastest Path

## 1) Cable it
- Router **WAN** → ISP/modem
- Router **LAN** (any LAN port) → **Switch** (any access port)
- **Server NIC** → **Switch** (access port)

## 2) Pick LAN plan
- Subnet: `192.168.10.0/24`
- Router LAN IP: `192.168.10.1`
- DHCP on router: `192.168.10.100–200` (enable NAT/firewall = default)

## 3) Configure router (LAN)
- Set LAN IP `192.168.10.1/24`
- Enable DHCP pool `100–200`, DNS = router or `1.1.1.1`
- Ensure NAT from LAN→WAN is ON

## 4) Switch
- **Unmanaged:** nothing.
- **Managed:** make ports to server + router **access VLAN 1** (or your chosen VLAN). No trunks needed for a single LAN.

## 5) Server IP
- **Easiest (DHCP):** plug in → it gets `192.168.10.x`, GW `192.168.10.1`.
- **Static (Linux example):**
```bash
ip addr add 192.168.10.10/24 dev eth0
ip route add default via 192.168.10.1
echo "nameserver 1.1.1.1" | tee /etc/resolv.conf

# Fix “Operation not permitted” (you’re not root)

# 1) become root
sudo -v || echo "no sudo rights"; sudo -i
# or, if sudo isn’t set up:
# su -    # enter root password

# 2) confirm the interface name (expect to see ens35f1)
ip -br link

# 3) bring it up and set IP (as root)
IF=ens35f1
ip link set dev "$IF" up
ip addr flush dev "$IF"
ip addr add 192.168.1.10/24 dev "$IF"
ip route replace default via 192.168.1.1
printf "nameserver 1.1.1.1\n" > /etc/resolv.conf

# 4) test
ping -c2 192.168.1.1
ping -c2 8.8.8.8
curl -I https://example.com

# If you still get “Operation not permitted” as root:
# - You’re inside a restricted container/namespace. Configure networking on the host/VM instead.
# - Or you mistyped the NIC name. Recheck step 2.

# From laptop:
ssh mini_bicasl@192.168.1.10

# Change hostname

# show current
hostnamectl

# set new static hostname (e.g., "mini-bicasl")
sudo hostnamectl set-hostname mini-bicasl

# map it locally (optional but recommended)
sudo sh -c 'printf "127.0.1.1 mini-bicasl\n" >> /etc/hosts'

# re-login (or: exec bash) to refresh your prompt
# exec bash
