# 网络与设备运维要点（整理版）

## 光通信与布线

* **光纤 vs 光模块**

  * 光纤=传输介质；光模块=电↔光转换（SFP/QSFP 等）。
* **LC 型光纤跳线 vs LAN 网线**

  * LC 光纤：传光，远距/高带宽；
  * LAN 网线（双绞线）：传电，≤100m，成本低。
* 英文：LC Fiber Optic Patch Cable / Fiber Patch Cord；LAN/Ethernet/Twisted Pair Cable。

## 内网/外网与接入场景

* **内网（Intranet）**：私有地址（10/172.16–31/192.168），不可直达公网。
* **外网（Internet）**：公网地址，可被全球访问。
* **判断规则**：谁持有公网 IP，谁就是 Internet 边界 (Edge)。
* **Case 1**：路由器→交换机→服务器，本地访问不需端口转发。
* **Case 2**：SIM 路由器→企业路由器→交换机→服务器，常见双重 NAT，需要端口转发或 VPN。

## 远程访问（SSH/VNC）

* **推荐**：VPN/反向 SSH 隧道。
* **端口转发（仅公网 IP 时）**：

  * DHCP 保留静态 LAN IP。
  * SSH: `WAN:22022 → LAN:22`
  * VNC: `WAN:55900 → LAN:5900`
  * 动态公网：DDNS。IPv6：直接防火墙放行。
* **安全加固**：SSH 禁口令、仅密钥、改端口、fail2ban；VNC 走 SSH 隧道或 RealVNC Cloud。

## NAT 与 CGNAT

* **NAT**：多台私网主机共享公网 IP。
* **缺点**：外网无法主动访问 → 需端口转发/DMZ/VPN。
* **CGNAT**：运营商再做一层 NAT → 无法直接端口转发。

## BMC 与数据 NIC

* **BMC**：独立管理控制器，有独立 MAC/IP。
* **独立口**：Dedicated；**共享口**：Shared/Side-band。
* **区别**：BMC MAC ≠ OS NIC MAC，本质是不同芯片。
* **数量**：至少 1 个，若支持 Shared，可能每口都有分配。

## MAC 地址/OUI

* **MAC**：48 位硬件地址，全球唯一。
* **OUI**：前三组标识厂商（Intel/Inspur/Huawei 等）。
* **IP vs MAC**：IP 会变，MAC 固定。
* **手机随机 MAC**：iPhone/Android 默认启用“私有地址”，可关闭。

## 软件许可证绑定

* 许可证通常绑定 **OS 数据 NIC MAC**，不是 BMC。
* 应选择稳定、始终存在的网口。

## 查看 MAC 地址

* **Linux**

  ```bash
  ip link show
  cat /sys/class/net/ens35f0/address
  cat /sys/class/net/ens35f1/address
  ```
* **Windows**

  ```cmd
  ipconfig /all
  getmac /v /fo list
  ```
* **BMC (IPMI)**

  ```bash
  ipmitool lan print 1 | grep "MAC Address"
  ipmitool lan print 2 | grep "MAC Address"
  ipmitool lan print 3 | grep "MAC Address"
  ```

## 查找 BMC IP

* **路由器 DHCP 列表**：匹配 BMC MAC。
* **ARP/扫描**：

  ```bash
  arp -a
  sudo nmap -sP 192.168.1.0/24
  ```
* **OS**：`ipmitool lan print <ch>`
* **BIOS/Setup**：BMC 配置页。

## ARP 表

* 记录 IP ↔ MAC 映射。
* 企业路由器查看方式：

  * Cisco/Juniper: `show arp`
  * Huawei: `display arp`
  * Mikrotik: `ip arp print`
  * Fortigate: `get system arp`

## 网络测试（以 Bing 为例）

* **Ping**

  ```bash
  ping -c 4 8.8.8.8
  ping -c 4 www.bing.com
  ```
* **Traceroute**

  ```bash
  traceroute www.bing.com   # Linux/macOS
  tracert www.bing.com      # Windows
  ```
* **HTTP/HTTPS**

  ```bash
  curl -I https://www.bing.com
  ```
* **DNS**

  ```bash
  nslookup www.bing.com
  dig www.bing.com
  ```

## 示例表（Markdown）

```markdown
| Server | MAC address (ens35f0) | MAC address (ens35f1) | MAC address (BMC0) | MAC address (BMC1) |
|--------|------------------------|------------------------|---------------------|---------------------|
| Node A2 | 98:03:9B:A2:63:6E | 98:03:9B:A2:63:6F | 6C:92:BF:9F:A1:84 | 6C:92:BF:9F:A1:85 |
| Node B2 | 98:03:9B:A2:12:62 | 98:03:9B:A2:12:63 | 6C:92:BF:9F:90:98 | 6C:92:BF:9F:90:99 |
| Node C2 | 98:03:9B:A2:02:52 | 98:03:9B:A2:02:53 | 6C:92:BF:9F:93:7A | 6C:92:BF:9F:93:7B |
| Node D2 | 98:03:9B:A1:88:BE | 98:03:9B:A1:88:BF | 6C:92:BF:9F:90:7A | 6C:92:BF:9F:90:7B |
```

---

