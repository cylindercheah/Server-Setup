# 用户和VNC管理交互式脚本

一个功能强大的交互式Shell脚本，用于批量创建Linux用户并配置VNC远程桌面访问。

## ✨ 功能特性

- 🚀 **批量创建用户** - 一次性创建多个用户账户
- 👤 **单用户模式** - 快速创建单个用户
- 🖥️ **VNC配置** - 自动为用户配置VNC远程桌面
- 🎨 **彩色交互界面** - 清晰的视觉反馈（信息、成功、警告、错误）
- 🔒 **安全密码输入** - 密码输入时不显示在屏幕上
- ⚙️ **自定义Shell** - 自动读取系统可用shell（bash、zsh、fish等）供用户选择
- 🔍 **智能检查** - 自动检查用户是否存在，避免重复创建
- 📋 **操作总结** - 完成后显示详细的处理结果

## 📋 系统要求

- Linux操作系统（Ubuntu、Debian、RHEL/AlmaLinux等）
- Root权限（需使用sudo运行）
- `bash`
- 如需VNC功能：TigerVNC服务端工具
- 如需完整VNC桌面：至少安装一种桌面会话，例如 `XFCE`、`GNOME`、`MATE` 或 `LXQt`

### 安装VNC / 桌面组件（可选）

脚本会检测缺失的TigerVNC组件，并在需要时提示自动安装。

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install tigervnc-standalone-server tigervnc-tools xauth xfonts-base
```

**RHEL / AlmaLinux / Rocky:**
```bash
sudo dnf install tigervnc-server xauth xorg-x11-fonts-Type1 xorg-x11-fonts-misc
```

**在 AlmaLinux / RHEL 系主机上安装 XFCE（推荐用于VNC）：**
```bash
sudo dnf install epel-release
sudo dnf group install Xfce
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
  4) 退出

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
7. 选择是否允许VNC客户端直连，或仅监听本地回环地址
8. 选择VNC桌面模式

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

是否允许VNC客户端直接连接？(y/n) [默认: n]:
n

请选择VNC桌面模式：
  1) 自动选择（推荐；当前主机将使用 XFCE）
  2) Minimal X11
  3) XFCE
  4) GNOME Classic
  5) GNOME

请输入序号 [默认: 1]:
1
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
7. 选择是否允许直连，或仅本地监听
8. 选择VNC桌面模式

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

是否允许VNC客户端直接连接？(y/n) [默认: n]:
n

请选择VNC桌面模式：
  1) 自动选择（推荐；安装了XFCE时会优先使用XFCE）
  2) Minimal X11
  3) XFCE
  4) GNOME Classic
  5) GNOME

请输入序号 [默认: 1]:
1
```

### 模式3：仅为现有用户配置VNC

适合为已存在的用户批量配置VNC访问。

**操作步骤：**

1. 选择选项 `3`
2. 输入用户名列表（空格分隔）
3. 输入VNC密码
4. 选择是否允许直连，或仅本地监听
5. 选择VNC桌面模式

**示例：**
```
请输入用户名列表（用空格分隔）：
alice bob charlie

请输入VNC密码：
********

是否允许VNC客户端直接连接？(y/n) [默认: n]:
n

请选择VNC桌面模式：
  1) 自动选择（推荐；安装了XFCE时会优先使用XFCE）
  2) Minimal X11
  3) XFCE
  4) GNOME Classic
  5) GNOME

请输入序号 [默认: 1]:
1
```

## 🖥️ VNC桌面模式说明

- **自动选择（Auto）** - 推荐。优先选择稳定的完整桌面；在当前这类环境中，如果已安装 `XFCE`，通常会优先使用它。
- **XFCE** - 推荐的完整VNC桌面模式，包含面板、桌面背景、文件管理器和正常窗口管理。
- **Minimal X11** - 回退模式。仅启动一个非常小的X11图形会话，适合排障或低资源场景。
- **GNOME Classic / GNOME** - 安装后可选，但在TigerVNC中通常没有 `XFCE` 稳定。

脚本现在会优先使用 `XFCE`。如果系统中没有可用的轻量完整桌面，`Auto` 才会回退到 `Minimal X11`。

## 🔌 VNC连接方式

- **推荐** - 仅监听 `localhost`，通过SSH隧道连接。
- **VNC直连** - 可选，但需要开放防火墙端口，并且在共享网络中安全性较低。

### 推荐的SSH隧道连接方式

如果脚本输出类似 `display :11 (port 5911)`，请在您的笔记本或工作站上运行：

```bash
ssh -N -L 25911:localhost:5911 username@server-ip
```

然后在VNC客户端中连接：

```text
localhost:25911
```

本地端口可以自行选择任意空闲端口；`-L` 右侧的端口必须与服务器上的VNC端口一致。

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
- Ubuntu/Debian: `sudo apt install tigervnc-standalone-server tigervnc-tools`
- CentOS/RHEL: `sudo dnf install tigervnc-server`

### Q: VNC桌面模式应该选哪个？
**A:** 优先选择 `Auto` 或 `XFCE`。在当前这套配置里，`XFCE` 是最推荐的完整桌面模式。

### Q: 为什么不默认使用GNOME？
**A:** GNOME通常更依赖完整的会话/系统集成，在TigerVNC里更容易出现黑屏或启动失败；`XFCE` 通常更稳定。

### Q: 用户已存在时会怎样？
**A:** 脚本会检测到并跳过创建，但仍可以为该用户配置VNC。

### Q: 可以为不同用户设置不同密码吗？
**A:** 使用"单用户模式"（选项2）可以为每个用户设置不同密码。批量模式使用统一密码。

### Q: VNC密码必须和用户密码相同吗？
**A:** 不需要，VNC密码可以与用户密码不同。

### Q: 现在还需要手动执行 `vncserver :1` 吗？
**A:** 一般不需要。脚本现在会自动写入VNC配置、选择空闲display、启动VNC会话，并输出可用的display和端口。

### Q: 如何连接VNC？
**A:** 推荐使用SSH隧道。如果脚本提示 `display :10 (port 5910)`，请运行：
```bash
ssh -N -L 25910:localhost:5910 username@server-ip
```
然后在VNC客户端里连接 `localhost:25910`。

## 🛠️ 技术细节

### 创建的用户特性
- 自动创建home目录（`/home/username`）
- 可从系统可用shell中选择默认shell（读取自`/etc/shells`）
- 自动设置用户密码

### VNC配置
- TigerVNC用户配置：`/home/username/.config/tigervnc/config`
- 兼容 direct vncserver 启动的配置：`/home/username/.vnc/legacy-xdg/tigervnc/config`
- VNC密码文件：`/home/username/.config/tigervnc/passwd` 和 `/home/username/.vnc/passwd`
- 启动文件：`/home/username/.vnc/xstartup` 和 `/home/username/.Xclients`
- 当前推荐的完整桌面模式：`XFCE`

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
