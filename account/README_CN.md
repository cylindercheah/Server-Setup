# 用户和VNC管理交互式脚本

一个功能强大的交互式Shell脚本，用于批量创建Linux用户并配置VNC远程桌面访问。

## ✨ 功能特性

- 🚀 **批量创建用户** - 一次性创建多个用户账户
- 👤 **单用户模式** - 快速创建单个用户
- 🖥️ **VNC配置** - 自动为用户配置VNC远程桌面
- 🔁 **systemd集成（推荐）** - 可自动写入显示号映射并启用开机自启服务
- 🗑️ **删除用户（含VNC清理）** - 一键删除账号并回收对应VNC资源
- 🎨 **彩色交互界面** - 清晰的视觉反馈（信息、成功、警告、错误）
- 🔒 **安全密码输入** - 密码输入时不显示在屏幕上
- ⚙️ **自定义Shell** - 自动读取系统可用shell（bash、zsh、fish等）供用户选择
- 🔍 **智能检查** - 自动检查用户是否存在，避免重复创建
- 📋 **操作总结** - 完成后显示详细的处理结果

## 📋 系统要求

- Linux操作系统（Ubuntu、Debian、CentOS等）
- Root权限（需使用sudo运行）
- bash或zsh shell
- 如需VNC功能：TigerVNC或TightVNC

### 安装VNC（可选）

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install tigervnc-common
```

**CentOS/RHEL:**
```bash
sudo yum install tigervnc-server
```

## 🚀 快速开始

### 1. 下载脚本

```bash
wget https://your-repo/user_manager.sh
# 或
curl -O https://your-repo/user_manager.sh
```

### 2. 添加执行权限

```bash
chmod +x user_manager.sh
```

### 3. 运行脚本

```bash
sudo ./user_manager.sh
```

## 📖 使用指南

运行脚本后，您会看到主菜单：

```
==========================================
      用户和VNC管理交互式脚本
==========================================

请选择操作模式：

  1) 批量创建用户和配置VNC
  2) 创建单个用户和配置VNC
  3) 仅为现有用户配置VNC
  4) 删除用户（含VNC清理）
  5) 退出

==========================================
```

### 模式1：批量创建用户和配置VNC

适合一次性创建多个用户账户。

**操作步骤：**

1. 选择选项 `1`
2. 输入用户名列表（空格分隔），例如：`alice bob charlie`
3. 输入统一密码（所有用户使用相同密码）
4. 从系统可用shell列表中选择默认Shell（如bash、zsh、fish等）
5. 选择是否配置VNC（y/n）
6. 如果配置VNC，输入VNC密码

**示例：**
```
请输入用户名列表（用空格分隔）：
alice bob charlie

请输入统一的用户密码：
********

系统中可用的Shell列表：
  1) /bin/bash
  2) /bin/zsh
  3) /bin/sh
  4) /usr/bin/fish

请选择默认shell (输入序号) [默认: 1]:
2

是否为用户配置VNC？(y/n) [默认: n]:
y

请输入VNC密码：
********
```

### 模式2：创建单个用户和配置VNC

适合创建单个用户账户，可为每个用户设置不同的密码。

**操作步骤：**

1. 选择选项 `2`
2. 输入用户名
3. 输入用户密码
4. 从系统可用shell列表中选择默认Shell
5. 选择是否配置VNC
6. 如果配置VNC，输入VNC密码

**示例：**
```
请输入用户名：
david

请输入用户密码：
********

系统中可用的Shell列表：
  1) /bin/bash
  2) /bin/zsh
  3) /bin/sh
  4) /usr/bin/fish

请选择默认shell (输入序号) [默认: 1]:
2

是否为用户 david 配置VNC？(y/n) [默认: n]:
y

请输入VNC密码：
********
```

### 模式3：仅为现有用户配置VNC

适合为已存在的用户批量配置VNC访问。

**操作步骤：**

1. 选择选项 `3`
2. 输入用户名列表（空格分隔）
3. 输入VNC密码

**示例：**
```
请输入用户名列表（用空格分隔）：
alice bob charlie

请输入VNC密码：
********
```

### 模式4：删除用户（含VNC清理）

适合下线账号时，自动清理该用户占用的VNC资源。

**操作步骤：**

1. 选择选项 `4`
2. 输入要删除的用户名列表（空格分隔）
3. 按提示确认删除（`y` 才会执行）

**示例：**
```
请输入要删除的用户名列表（用空格分隔）：
alice bob

是否确认删除用户 alice（含VNC服务/端口清理）？(y/n) [默认: n]:
y
```

**“VNC清理”会移除的内容（精确范围）：**

- 停止并禁用该用户映射到的每个 `vncserver@:N.service`
- 强制回收对应显示号 `:N`（终止相关Xvnc进程，并删除 `/tmp/.X<N>-lock` 与 `/tmp/.X11-unix/X<N>`）
- 从活动防火墙zone中移除对应端口 `5900+N/tcp`（仅当该端口已放行时）
- 从 `/etc/tigervnc/vncserver.users` 删除该用户的显示号映射行
- 若确实移除了端口规则，会执行一次 `firewall-cmd --reload`
- 最后执行 `userdel -r 用户名` 删除系统用户及其home目录

**不会移除的内容：**

- 不会删除其他用户的VNC映射、服务和端口
- 不会删除与该用户无关的防火墙规则（如你手动开放的端口范围 `5900-5999/tcp`）
- 若用户不存在，只执行VNC清理（映射/服务/端口），不会报错中断

**删除前检查清单（建议执行）：**

- 确认该用户当前没有正在进行的重要远程会话或未保存工作
- 如需保留数据，先备份 `home` 目录（例如 `/home/用户名`）
- 确认该用户不再需要VNC访问（对应 `:N` 与端口 `5900+N`）
- 若你是按“端口范围”放行防火墙（如 `5900-5999/tcp`），请知晓脚本不会删除该范围规则

## 🔐 安全说明

- ✅ 脚本需要root权限运行，会自动检查
- ✅ 密码输入时不会显示在屏幕上
- ✅ VNC密码文件权限自动设置为600（仅用户可读写）
- ✅ VNC目录权限自动设置为700（仅用户可访问）
- ⚠️ 建议使用强密码
- ⚠️ 定期更新用户密码

## 📝 常见问题

### Q: 脚本提示"需要root权限"？
**A:** 使用 `sudo ./user_manager.sh` 运行脚本。

### Q: 提示"vncpasswd命令未找到"？
**A:** 需要先安装VNC服务：
- Ubuntu/Debian: `sudo apt install tigervnc-common`
- CentOS/RHEL: `sudo yum install tigervnc-server`

### Q: 用户已存在时会怎样？
**A:** 脚本会检测到并跳过创建，但仍可以为该用户配置VNC。

### Q: 可以为不同用户设置不同密码吗？
**A:** 使用"单用户模式"（选项2）可以为每个用户设置不同密码。批量模式使用统一密码。

### Q: VNC密码必须和用户密码相同吗？
**A:** 不需要，VNC密码可以与用户密码不同。

### Q: 如何启动VNC服务？
**A:** 推荐使用 `systemd`（脚本已支持），不再手动运行已废弃的 `vncserver`。

如果脚本中选择了“使用 systemd 管理 VNC（推荐）”，会自动完成：
- 写入显示号映射到 `/etc/tigervnc/vncserver.users`（如 `:2=user1`）
- 写入用户VNC配置 `/home/用户名/.vnc/config`（分辨率、会话、localhost）
- 启用并启动 `vncserver@:N.service`

可手动检查：
```bash
sudo systemctl status vncserver@:2.service
sudo systemctl status vncserver@:3.service
```

### Q: 选项4里的“VNC清理”到底会删什么？
**A:** 会按用户在 `/etc/tigervnc/vncserver.users` 的映射逐个清理：
- `vncserver@:N.service` 的停止与禁用
- 对应显示号会话与锁文件回收
- 对应端口 `5900+N/tcp` 的防火墙放行规则（若存在）
- 该用户在映射文件中的条目

随后才执行 `userdel -r` 删除用户本身和home目录。

### Q: 如何连接VNC？
**A:** 使用VNC客户端连接到：`服务器IP:端口`，其中端口号 = `5900 + 显示编号`。

例如：
- `:2 -> 5902`
- `:3 -> 5903`
- `:4 -> 5904`

显示号可在 `/etc/tigervnc/vncserver.users` 查看。

## 🔧 推荐工作流（AlmaLinux/RHEL）

### 第一次（仅需做一次）

1. 安装TigerVNC：
```bash
sudo dnf install -y tigervnc tigervnc-server
```

2. 开防火墙（按实际需求）：
```bash
# 开放单端口示例
sudo firewall-cmd --permanent --zone=public --add-port=5904/tcp

# 或开放VNC常用范围
sudo firewall-cmd --permanent --zone=public --add-port=5900-5999/tcp

sudo firewall-cmd --reload
```

> 注意：务必在活动网卡所在zone（如 `public`）放行端口/服务。

2.1 可选：使用防火墙图形界面（`firewall-config`）配置

如果你更习惯图形界面，可按以下步骤：

1. 安装并启动图形工具：
```bash
sudo dnf install -y firewall-config
sudo firewall-config
```

2. 在界面右上角先确认：
- 勾选 `Permanent`（永久规则）
- 选择正确的 `Zone`（通常是活动网卡所在zone，如 `public`）

3. 在 `Ports` 标签页添加端口：
- 单端口示例：`5904` + `tcp`
- 或端口范围：`5900-5999` + `tcp`

4. 点击 `Reload Firewall` 或执行：
```bash
sudo firewall-cmd --reload
```

> 提示：若你在错误zone里添加规则，或只加了runtime未保存permanent，VNC仍可能连不上。

### 日常使用（运行脚本后）

1. 运行脚本：
```bash
sudo ./user_manager.sh
```

2. 在脚本中选择：
- 配置VNC = `y`
- 使用systemd管理VNC = `y`
- 输入显示号（如 `2`、`3`）
- 输入分辨率（如 `1920x1080`）

3. 脚本完成后直接用RealVNC连接：
- `服务器IP:5902`（对应 `:2`）
- `服务器IP:5903`（对应 `:3`）

## ⚠️ 关于手动 `vncserver`

- `vncserver` 在当前TigerVNC中已提示为弃用路径（推荐改用systemd单位）
- 手动启动可能导致显示号漂移（例如变成`:4`），端口不固定
- 服务器重启后，手动会话通常不会自动恢复

## 🛠️ 技术细节

### 创建的用户特性
- 自动创建home目录（`/home/username`）
- 可从系统可用shell中选择默认shell（读取自`/etc/shells`）
- 自动设置用户密码

### VNC配置
- VNC配置目录：`/home/username/.vnc/`
- 密码文件：`/home/username/.vnc/passwd`
- 目录权限：700（drwx------）
- 密码文件权限：600（-rw-------）

## 📄 许可证

MIT License

## 🤝 贡献

欢迎提交Issue和Pull Request！

## 📧 联系方式

如有问题或建议，请通过以下方式联系：
- 提交Issue
- 发送邮件

---

**注意：** 请谨慎使用此脚本，确保了解每个操作的影响。建议先在测试环境中使用。
