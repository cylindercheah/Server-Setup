#!/bin/bash

# 批量设置用户 VNC 密码脚本
# 使用方法：sudo ./set_vnc_passwords.sh

# 定义需要设置的用户列表
USERS=("liutianyue")

# 统一设置的 VNC 密码
VNC_PASSWORD="ltysjtu"

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要使用 root 权限运行！"
    echo "请使用: sudo $0"
    exit 1
fi

# 检查vncpasswd命令是否可用
if ! command -v vncpasswd &> /dev/null; then
    echo "错误：vncpasswd 命令未找到，请先安装 TigerVNC 或 TightVNC"
    echo "可以尝试: sudo apt install tigervnc-common 或 sudo yum install tigervnc-server"
    exit 1
fi

echo "开始批量设置用户VNC密码..."

for USERNAME in "${USERS[@]}"; do
    # 检查用户是否存在
    if ! id "$USERNAME" &>/dev/null; then
        echo "警告：用户 $USERNAME 不存在，跳过"
        continue
    fi
    
    # 创建.vnc目录（如果不存在）
    if [ ! -d "/home/$USERNAME/.vnc" ]; then
        mkdir -p "/home/$USERNAME/.vnc"
        chown "$USERNAME:$USERNAME" "/home/$USERNAME/.vnc"
        chmod 700 "/home/$USERNAME/.vnc"
        echo "已创建 /home/$USERNAME/.vnc 目录"
    fi
    
    # 设置VNC密码
    echo "正在为 $USERNAME 设置VNC密码..."
    echo "$VNC_PASSWORD" | sudo -u "$USERNAME" vncpasswd -f > "/home/$USERNAME/.vnc/passwd"
    
    # 设置权限
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.vnc/passwd"
    chmod 600 "/home/$USERNAME/.vnc/passwd"
    
    echo "用户 $USERNAME 的VNC密码已设置为: $VNC_PASSWORD"
done

echo "所有用户VNC密码设置完成！"
echo "----------------------------------"
echo "已设置的用户列表："
for USERNAME in "${USERS[@]}"; do
    if [ -f "/home/$USERNAME/.vnc/passwd" ]; then
        echo "用户名: $USERNAME, VNC密码: $VNC_PASSWORD"
    fi
done
echo "----------------------------------"
