#!/bin/bash

# 批量创建自定义用户并设置VNC密码脚本
# 使用方法：sudo ./create_with_vnc_custom.sh

# 配置文件（保存到脚本所在目录而不是 /root）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASSWORD_FILE="$SCRIPT_DIR/vnc_users_passwords.txt"  # 密码保存文件
CSV_FILE="$SCRIPT_DIR/vnc_users_passwords.csv"      # CSV格式密码文件

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要使用 root 权限运行！"
    echo "请使用: sudo $0"
    exit 1
fi

# 检查必要的命令和软件
echo "正在检查系统环境..."

# 检查并安装TigerVNC Server
if ! rpm -q tigervnc-server &>/dev/null; then
    echo "✗ TigerVNC Server 未安装，正在自动安装..."
    if yum install -y tigervnc-server; then
        echo "✓ TigerVNC Server 安装成功"
    else
        echo "✗ 错误：TigerVNC Server 安装失败"
        echo "  请检查网络连接或手动安装: yum install -y tigervnc-server"
        exit 1
    fi
else
    echo "✓ TigerVNC Server 已安装"
fi

# 检查并安装zsh
if ! command -v zsh &> /dev/null; then
    echo "✗ zsh 未安装，正在自动安装..."
    if yum install -y zsh; then
        echo "✓ zsh 安装成功"
    else
        echo "✗ 错误：zsh 安装失败"
        echo "  请检查网络连接或手动安装: yum install -y zsh"
        exit 1
    fi
else
    echo "✓ zsh 已安装"
fi

# 检查是否安装了桌面环境
DESKTOP_FOUND=false
if command -v gnome-session &>/dev/null; then
    echo "✓ GNOME 桌面环境已安装"
    DESKTOP_FOUND=true
elif command -v startxfce4 &>/dev/null; then
    echo "✓ Xfce 桌面环境已安装"
    DESKTOP_FOUND=true
elif command -v mate-session &>/dev/null; then
    echo "✓ MATE 桌面环境已安装"
    DESKTOP_FOUND=true
fi

if [ "$DESKTOP_FOUND" = false ]; then
    echo "✗ 警告：未检测到桌面环境"
    echo "  VNC需要图形桌面环境才能正常工作"
    echo "  推荐安装: yum groupinstall -y \"Server with GUI\""
    read -p "  是否继续？(y/N): " CONTINUE
    if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
        echo "操作已取消"
        exit 1
    fi
fi

# 检查systemd是否可用
if ! command -v systemctl &>/dev/null; then
    echo "✗ 错误：systemctl 命令未找到，此脚本需要 systemd 支持"
    exit 1
else
    echo "✓ systemd 已就绪"
fi

echo "环境检查完成！"
echo "======================================"

# 检查显示器是否被占用的函数
function is_display_occupied() {
    local DISPLAY_NUM=$1
    local VNC_CONFIG_FILE="/etc/tigervnc/vncserver.users"
    
    # 检查X11 socket
    if [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
        return 0
    fi
    
    # 检查X lock文件
    if [ -f "/tmp/.X${DISPLAY_NUM}-lock" ]; then
        return 0
    fi
    
    # 检查VNC端口是否被监听
    local VNC_PORT=$((5900 + DISPLAY_NUM))
    if ss -ltn 2>/dev/null | grep -q ":${VNC_PORT} "; then
        return 0
    fi

    # 检查是否在vncserver.users中被配置
    if [ -f "$VNC_CONFIG_FILE" ] && grep -q "^:${DISPLAY_NUM}=" "$VNC_CONFIG_FILE"; then
        return 0
    fi
    
    return 1
}

# 获取下一个可用的VNC端口号
function get_next_available_vnc_port() {
    local port=1
    while true; do
        if ! is_display_occupied "$port"; then
            echo "$port"
            return
        fi
        ((port++))
    done
}

# 交互式获取用户信息
function get_custom_users() {
    while true; do
        read -p "请输入要创建的用户数量 (1-99): " NUM_USERS
        if [[ $NUM_USERS =~ ^[0-9]+$ ]] && [ "$NUM_USERS" -ge 1 ] && [ "$NUM_USERS" -le 99 ]; then
            break
        else
            echo "错误：请输入1-99之间的数字。"
        fi
    done

    USERNAMES=()
    PASSWORDS=()
    for (( i=1; i<=NUM_USERS; i++ )); do
        echo "--- 用户 $i / $NUM_USERS ---"
        while true; do
            read -p "请输入用户名: " username
            if [[ -z "$username" ]]; then
                echo "错误：用户名不能为空。"
            elif [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                echo "错误：用户名格式无效。请使用小写字母、数字、下划线或连字符，并以字母开头。"
            elif id "$username" &>/dev/null; then
                echo "错误：用户 '$username' 已存在，请输入另一个用户名。"
            else
                break
            fi
        done

        while true; do
            read -s -p "请输入密码: " password
            echo
            read -s -p "请再次输入密码确认: " password2
            echo
            if [ "$password" = "$password2" ]; then
                break
            else
                echo "错误：两次输入的密码不匹配。"
            fi
        done
        USERNAMES+=("$username")
        PASSWORDS+=("$password")
    done

    echo "======================================"
    echo "将要创建以下用户："
    for username in "${USERNAMES[@]}"; do
        echo "  - $username"
    done
    echo "======================================"
    read -p "确认操作吗？(y/N): " CONFIRM
    if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
        echo "操作已取消。"
        exit 0
    fi
}

# VNC设置函数
function setup_vnc_for_user() {
    local USERNAME=$1
    local VNC_PASSWORD=$2
    local PORT=$3
    
    echo "  正在为 $USERNAME 设置VNC..."
    
    # 创建.vnc目录
    mkdir -p "/home/$USERNAME/.vnc"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.vnc"
    chmod 700 "/home/$USERNAME/.vnc"
    
    # 设置VNC密码
    echo "$VNC_PASSWORD" | sudo -u "$USERNAME" vncpasswd -f > "/home/$USERNAME/.vnc/passwd"
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.vnc/passwd"
    chmod 600 "/home/$USERNAME/.vnc/passwd"
    echo "    用户 $USERNAME 的VNC密码已设置"
    
    # 创建xstartup文件
    cat > "/home/$USERNAME/.vnc/xstartup" <<'XSTARTUP_EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export GNOME_SHELL_SESSION_MODE=classic
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources
if command -v gnome-session >/dev/null 2>&1; then
    exec dbus-launch gnome-session --session=gnome-classic
elif command -v startxfce4 >/dev/null 2>&1; then
    exec dbus-launch startxfce4
elif command -v mate-session >/dev/null 2>&1; then
    exec dbus-launch mate-session
else
    [ -x /usr/bin/xterm ] && xterm -geometry 80x24+10+10 -ls -title "$VNCDESKTOP Desktop" &
    [ -x /usr/bin/twm ] && exec /usr/bin/twm
fi
XSTARTUP_EOF
    
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.vnc/xstartup"
    chmod 755 "/home/$USERNAME/.vnc/xstartup"
    echo "    已创建 /home/$USERNAME/.vnc/xstartup 文件"
    
    # 恢复SELinux上下文
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -Rv "/home/$USERNAME/.vnc" &>/dev/null || true
    fi
    
    # 配置VNC服务
    if setup_vnc_port "$USERNAME" "$PORT" && setup_vnc_service "$PORT"; then
        setup_firewall_port "$PORT"
        return 0
    else
        return 1
    fi
}

# VNC端口配置函数
function setup_vnc_port() {
    local USERNAME=$1
    local PORT=$2
    local VNC_CONFIG_FILE="/etc/tigervnc/vncserver.users"
    local CONFIG_LINE=":$PORT=$USERNAME"
    
    mkdir -p "/etc/tigervnc"
    touch "$VNC_CONFIG_FILE"
    
    # 移除该用户旧的配置
    sed -i "/=$USERNAME$/d" "$VNC_CONFIG_FILE"
    
    echo "$CONFIG_LINE" >> "$VNC_CONFIG_FILE"
    echo "    已添加端口配置：$CONFIG_LINE"
    return 0
}

# 防火墙配置函数
function setup_firewall_port() {
    local PORT=$1
    local VNC_PORT=$((5900 + PORT))
    
    if ! command -v firewall-cmd >/dev/null 2>&1 || ! systemctl is-active firewalld &>/dev/null; then
        echo "    firewalld 未运行，跳过防火墙配置"
        return
    fi
    
    if firewall-cmd --query-port=$VNC_PORT/tcp &>/dev/null; then
        echo "    防火墙端口 $VNC_PORT/tcp 已开放"
    else
        echo "    正在开放防火墙端口: $VNC_PORT/tcp"
        firewall-cmd --add-port=$VNC_PORT/tcp --permanent &>/dev/null
        firewall-cmd --reload &>/dev/null
    fi
}

# VNC系统服务配置函数
function setup_vnc_service() {
    local PORT=$1
    local SERVICE_NAME="vncserver@:$PORT.service"
    
    echo "    正在配置VNC系统服务: $SERVICE_NAME"
    
    systemctl enable "$SERVICE_NAME" &>/dev/null
    # 如果服务已在运行，则重启以应用新配置
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        systemctl restart "$SERVICE_NAME" &>/dev/null
    else
        systemctl start "$SERVICE_NAME" &>/dev/null
    fi
    
    sleep 1 # 等待服务启动
    
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        echo "      VNC服务运行正常: $SERVICE_NAME"
        return 0
    else
        echo "      警告：VNC服务启动失败: $SERVICE_NAME"
        journalctl -n 5 -u "$SERVICE_NAME" --no-pager
        return 1
    fi
}

# 获取用户列表
get_custom_users

echo "开始批量创建用户并设置VNC..."
echo "======================================"

# 记录结果
CREATED_USERS=()
FAILED_USERS=()

# 初始化密码文件
if [ ! -f "$PASSWORD_FILE" ]; then
    {
        echo "# VNC用户密码列表"
        echo "# 创建时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# ===================================="
        echo "# 字段: Username,Password,VNC_TCP_Port,Display,Created_At"
        echo "Username,Password,VNC_TCP_Port,Display,Created_At"
    } > "$PASSWORD_FILE"
    chmod 644 "$PASSWORD_FILE"
else
    # 如果旧格式没有列标题，则补充一行列标题（检测是否已有 Username,Password 开头行）
    if ! grep -q '^Username,Password,VNC_TCP_Port,Display,Created_At$' "$PASSWORD_FILE"; then
        echo "Username,Password,VNC_TCP_Port,Display,Created_At" >> "$PASSWORD_FILE"
    fi
    chmod 644 "$PASSWORD_FILE"
fi

# 初始化CSV文件
if [ ! -f "$CSV_FILE" ]; then
    echo "username,password,vnc_port,display_port,created_at" > "$CSV_FILE"
    chmod 644 "$CSV_FILE"
else
    # 如果缺少新字段 created_at，则不改动旧文件结构，只追加旧格式；新行将包含 created_at 但旧文件仍可读
    chmod 644 "$CSV_FILE"
fi

# 循环处理用户
for i in "${!USERNAMES[@]}"; do
    USERNAME=${USERNAMES[$i]}
    PASSWORD=${PASSWORDS[$i]}
    
    echo "处理用户: $USERNAME"
    
    # 再次防御性检查（正常情况下不会出现已存在用户，因为前面已阻止）
    if id "$USERNAME" &>/dev/null; then
        echo "  警告：用户 $USERNAME 在创建阶段被检测为已存在（跳过且不修改）。"
        FAILED_USERS+=("$USERNAME:已存在-跳过")
        echo "--------------------------------------"
        continue
    fi

    echo "  正在创建用户账户..."
    if ! useradd -m -s /bin/zsh -c "User $USERNAME" "$USERNAME"; then
        echo "    错误：创建用户账户失败"
        FAILED_USERS+=("$USERNAME:账户创建失败")
        echo "--------------------------------------"
        continue
    fi

    if ! echo "$USERNAME:$PASSWORD" | sudo chpasswd; then
        echo "    错误：设置用户密码失败"
        FAILED_USERS+=("$USERNAME:密码设置失败")
        echo "--------------------------------------"
        continue
    fi
    echo "    用户密码设置成功"

    # 分配VNC端口并设置
    PORT=$(get_next_available_vnc_port)
    if [ -z "$PORT" ]; then
        echo "  错误：无法找到可用的VNC端口"
        FAILED_USERS+=("$USERNAME:无可用VNC端口")
        continue
    fi
    echo "  分配到VNC显示器端口: :$PORT"

    if setup_vnc_for_user "$USERNAME" "$PASSWORD" "$PORT"; then
        VNC_PORT=$((5900 + PORT))
        CREATED_USERS+=("$USERNAME:$PASSWORD:$PORT:$VNC_PORT")
        
        # 保存密码
        NOW_TS="$(date '+%Y-%m-%d %H:%M:%S')"
        printf "%s,%s,%s,%s,%s\n" "$USERNAME" "$PASSWORD" "$VNC_PORT" "$PORT" "$NOW_TS" >> "$PASSWORD_FILE"
        # 兼容：如果 CSV 第一行包含 created_at 就写五列，否则写四列（向后兼容旧文件）
        if head -1 "$CSV_FILE" | grep -q 'created_at'; then
            printf "%s,%s,%s,%s,%s\n" "$USERNAME" "$PASSWORD" "$VNC_PORT" "$PORT" "$NOW_TS" >> "$CSV_FILE"
        else
            printf "%s,%s,%s,%s\n" "$USERNAME" "$PASSWORD" "$VNC_PORT" "$PORT" >> "$CSV_FILE"
        fi
        
        echo "  用户 $USERNAME 配置完成！"
    else
        FAILED_USERS+=("$USERNAME:VNC设置失败")
        echo "  警告：用户 $USERNAME 的VNC设置失败"
    fi
    
    echo "--------------------------------------"
done

echo "======================================"
echo "操作完成！以下是处理结果："
echo "======================================"

# 统计信息
TOTAL_REQUESTED=${#USERNAMES[@]}
SUCCESSFUL_COUNT=${#CREATED_USERS[@]}
FAILED_COUNT=${#FAILED_USERS[@]}

echo "总共请求处理用户数: $TOTAL_REQUESTED"
echo "成功处理用户数: $SUCCESSFUL_COUNT"
echo "失败用户数: $FAILED_COUNT"
echo ""

if [ $SUCCESSFUL_COUNT -gt 0 ]; then
    echo "╔═══════════════╦══════════╦══════════════╦═════════════════╦═════════════════╗"
    echo "║   用户名      ║  显示器  ║   TCP端口    ║      密码       ║  VNC连接地址    ║"
    echo "╠═══════════════╬══════════╬══════════════╬═════════════════╬═════════════════╣"
    for user_info in "${CREATED_USERS[@]}"; do
        IFS=':' read -r USERNAME PASSWORD PORT VNC_PORT <<< "$user_info"
        printf "║ %-13s ║   :%-6s ║   %-10s ║  %-14s ║  <IP>:%-9s ║\n" "$USERNAME" "$PORT" "$VNC_PORT" "$PASSWORD" "$PORT"
    done
    echo "╚═══════════════╩══════════╩══════════════╩═════════════════╩═════════════════╝"
    echo ""
fi

if [ $FAILED_COUNT -gt 0 ]; then
    echo "失败的用户列表："
    for failed_info in "${FAILED_USERS[@]}"; do
        USERNAME="${failed_info%%:*}"
        REASON="${failed_info##*:}"
        echo "  ✗ 用户名: $USERNAME - 失败原因: $REASON"
    done
    echo ""
fi

echo "======================================"
echo "重要提示："
echo "1. 所有密码已保存到文件:"
echo "   - 文本格式: $PASSWORD_FILE"
echo "   - CSV格式:  $CSV_FILE"
echo "2. 请妥善保管密码文件，建议备份到安全位置。"
echo "3. VNC端口是自动分配的。"
echo "4. 如需删除用户，请使用配套的删除脚本。"
echo "======================================"
