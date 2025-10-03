#!/bin/bash

# 批量创建用户并设置VNC密码脚本
# 使用方法：sudo ./create_with_vnc.sh

# 统一密码（账户密码和VNC密码保持一致）
PASSWORD="12345678"

# 保存文件（使用脚本所在目录，与 create_with_vnc_custom.sh 统一）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PASSWORD_FILE="$SCRIPT_DIR/vnc_users_passwords.txt"
CSV_FILE="$SCRIPT_DIR/vnc_users_passwords.csv"

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

# 输入验证函数
function validate_number() {
    local input=$1
    if [[ $input =~ ^[0-9]+$ ]] && [ "$input" -ge 1 ] && [ "$input" -le 999 ]; then
        return 0
    else
        return 1
    fi
}

# 交互式获取用户范围
function get_user_range() {
    while true; do
        echo "请输入要创建的用户范围："
        read -p "起始编号 (1-999): " START_NUM
        
        if ! validate_number "$START_NUM"; then
            echo "错误：起始编号必须是1-999之间的数字"
            continue
        fi
        
        read -p "结束编号 (1-999): " END_NUM
        
        if ! validate_number "$END_NUM"; then
            echo "错误：结束编号必须是1-999之间的数字"
            continue
        fi
        
        if [ "$START_NUM" -gt "$END_NUM" ]; then
            echo "错误：起始编号不能大于结束编号"
            continue
        fi
        
        # 确认信息
        echo "======================================"
        printf "将创建用户: user%03d 到 user%03d\n" "$START_NUM" "$END_NUM"
        echo "用户数量: $((END_NUM - START_NUM + 1))"
        echo "统一密码: $PASSWORD"
        echo "默认Shell: /bin/zsh"
        echo "======================================"
        
        read -p "确认创建这些用户吗？(y/N): " CONFIRM
        if [[ $CONFIRM =~ ^[Yy]$ ]]; then
            break
        else
            echo "操作已取消，请重新输入范围。"
        fi
    done
}

# VNC设置函数
function setup_vnc_for_user() {
    local USERNAME=$1
    local VNC_PASSWORD=$2
    local PORT=$3
    
    echo "  正在为 $USERNAME 设置VNC..."
    
    # 创建.vnc目录（如果不存在）
    if [ ! -d "/home/$USERNAME/.vnc" ]; then
        mkdir -p "/home/$USERNAME/.vnc"
        chown "$USERNAME:$USERNAME" "/home/$USERNAME/.vnc"
        chmod 700 "/home/$USERNAME/.vnc"
        echo "    已创建 /home/$USERNAME/.vnc 目录"
    fi
    
    # 设置VNC密码
    echo "$VNC_PASSWORD" | sudo -u "$USERNAME" vncpasswd -f > "/home/$USERNAME/.vnc/passwd"
    
    # 设置权限
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.vnc/passwd"
    chmod 600 "/home/$USERNAME/.vnc/passwd"
    
    echo "    用户 $USERNAME 的VNC密码已设置完成"
    
    # 创建xstartup文件以启动桌面会话
    cat > "/home/$USERNAME/.vnc/xstartup" <<'XSTARTUP_EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export GNOME_SHELL_SESSION_MODE=classic

# 清理可能残留的会话文件
[ -r $HOME/.Xresources ] && xrdb $HOME/.Xresources

# 尝试启动桌面环境（按优先级）
if command -v gnome-session >/dev/null 2>&1; then
    # 使用GNOME Classic X11模式（VNC兼容）
    # 移除 --exit-with-session 以保持VNC服务器运行
    exec dbus-launch gnome-session --session=gnome-classic
elif command -v startxfce4 >/dev/null 2>&1; then
    exec dbus-launch startxfce4
elif command -v mate-session >/dev/null 2>&1; then
    exec dbus-launch mate-session
else
    # 如果没有完整桌面，启动基本窗口管理器
    [ -x /usr/bin/xterm ] && xterm -geometry 80x24+10+10 -ls -title "$VNCDESKTOP Desktop" &
    [ -x /usr/bin/twm ] && exec /usr/bin/twm
fi
XSTARTUP_EOF
    
    chown "$USERNAME:$USERNAME" "/home/$USERNAME/.vnc/xstartup"
    chmod 755 "/home/$USERNAME/.vnc/xstartup"
    echo "    已创建 /home/$USERNAME/.vnc/xstartup 文件"
    
    # 恢复SELinux上下文（如果启用）
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -Rv "/home/$USERNAME/.vnc" &>/dev/null || true
    fi
    
    # 配置VNC服务端口
    if setup_vnc_port "$USERNAME" "$PORT"; then
        echo "    用户 $USERNAME 的VNC端口($PORT)配置完成"
        
        # 启用和启动VNC系统服务
        if setup_vnc_service "$PORT"; then
            echo "    用户 $USERNAME 的VNC系统服务已启用并启动"
            
            # 配置防火墙（如果使用firewalld）
            setup_firewall_port "$PORT"
            
            return 0
        else
            echo "    警告：用户 $USERNAME 的VNC系统服务配置失败"
            return 1
        fi
    else
        echo "    警告：用户 $USERNAME 的VNC端口配置失败"
        return 1
    fi
}

# VNC端口配置函数
function setup_vnc_port() {
    local USERNAME=$1
    local PORT=$2
    local VNC_CONFIG_FILE="/etc/tigervnc/vncserver.users"
    local CONFIG_LINE=":$PORT=$USERNAME"
    
    # 确保配置目录存在
    if [ ! -d "/etc/tigervnc" ]; then
        mkdir -p "/etc/tigervnc"
        echo "    已创建 /etc/tigervnc 目录"
    fi
    
    # 检查配置文件是否存在，不存在则创建
    if [ ! -f "$VNC_CONFIG_FILE" ]; then
        touch "$VNC_CONFIG_FILE"
        echo "    已创建 $VNC_CONFIG_FILE 文件"
    fi
    
    # 检查配置行是否已存在
    if grep -q "^$CONFIG_LINE$" "$VNC_CONFIG_FILE"; then
        echo "    端口配置 $CONFIG_LINE 已存在，跳过"
        return 0
    fi
    
    # 检查端口是否被其他用户占用
    if grep -q "^:$PORT=" "$VNC_CONFIG_FILE"; then
        local EXISTING_USER=$(grep "^:$PORT=" "$VNC_CONFIG_FILE" | cut -d'=' -f2)
        echo "    警告：端口 $PORT 已被用户 $EXISTING_USER 占用"
        return 1
    fi
    
    # 添加配置行
    echo "$CONFIG_LINE" >> "$VNC_CONFIG_FILE"
    echo "    已添加端口配置：$CONFIG_LINE"
    
    return 0
}

# 防火墙配置函数
function setup_firewall_port() {
    local PORT=$1
    local VNC_PORT=$((5900 + PORT))
    
    # 检查firewalld是否运行
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        echo "    firewall-cmd 未找到，跳过防火墙配置"
        return 0
    fi
    
    if ! systemctl is-active firewalld &>/dev/null; then
        echo "    firewalld 未运行，跳过防火墙配置"
        return 0
    fi
    
    echo "    正在配置防火墙端口: $VNC_PORT/tcp"
    
    # 检查端口是否已开放
    if firewall-cmd --query-port=$VNC_PORT/tcp &>/dev/null; then
        echo "      端口 $VNC_PORT/tcp 已开放"
        return 0
    fi
    
    # 开放端口
    if firewall-cmd --add-port=$VNC_PORT/tcp --permanent &>/dev/null; then
        if firewall-cmd --reload &>/dev/null; then
            echo "      已开放端口: $VNC_PORT/tcp"
            return 0
        else
            echo "      警告：防火墙重载失败"
            return 1
        fi
    else
        echo "      警告：开放端口失败: $VNC_PORT/tcp"
        return 1
    fi
}

# VNC系统服务配置函数
function setup_vnc_service() {
    local PORT=$1
    local SERVICE_NAME="vncserver@:$PORT.service"
    
    echo "    正在配置VNC系统服务: $SERVICE_NAME"
    
    # 启用VNC服务
    if systemctl enable "$SERVICE_NAME" &>/dev/null; then
        echo "      VNC服务已启用: $SERVICE_NAME"
    else
        echo "      警告：启用VNC服务失败: $SERVICE_NAME"
        return 1
    fi
    
    # 启动VNC服务
    if systemctl start "$SERVICE_NAME" &>/dev/null; then
        echo "      VNC服务已启动: $SERVICE_NAME"
        
        # 检查服务状态
        if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
            echo "      VNC服务运行正常: $SERVICE_NAME"
            return 0
        else
            echo "      警告：VNC服务启动后状态异常: $SERVICE_NAME"
            # 获取服务状态信息
            local STATUS=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "unknown")
            echo "      服务状态: $STATUS"
            return 1
        fi
    else
        echo "      警告：启动VNC服务失败: $SERVICE_NAME"
        return 1
    fi
}

# 检查显示器是否被占用的函数（更全面的检查）
function is_display_occupied() {
    local DISPLAY_NUM=$1
    
    # 方法1: 检查X11 socket是否存在
    if [ -S "/tmp/.X11-unix/X${DISPLAY_NUM}" ]; then
        return 0  # socket存在，被占用
    fi
    
    # 方法2: 检查X lock文件是否存在
    if [ -f "/tmp/.X${DISPLAY_NUM}-lock" ]; then
        return 0  # lock文件存在，被占用
    fi
    
    # 方法3: 检查是否有进程监听该VNC端口
    local VNC_PORT=$((5900 + DISPLAY_NUM))
    if ss -ltn 2>/dev/null | grep -q ":${VNC_PORT} "; then
        return 0  # 端口被监听，被占用
    fi
    
    return 1  # 空闲
}

# 获取用户输入的范围
get_user_range

echo "开始批量创建用户并设置VNC..."
echo "======================================"

# 初始化（如不存在则创建写入表头；存在则保持并追加）
if [ ! -f "$PASSWORD_FILE" ]; then
    {
        echo "# VNC用户密码列表"
        echo "# 创建时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "# ===================================="
        echo "# 字段: Username,Password,VNC_TCP_Port,Display,Created_At"
        echo "Username,Password,VNC_TCP_Port,Display,Created_At"
    } > "$PASSWORD_FILE"
fi
if [ ! -f "$CSV_FILE" ]; then
    echo "username,password,vnc_port,display_port,created_at" > "$CSV_FILE"
fi
chmod 644 "$PASSWORD_FILE" "$CSV_FILE"

# 记录成功创建的用户
CREATED_USERS=()
FAILED_USERS=()
SKIPPED_DISPLAYS=()

# 循环创建用户
for (( i=START_NUM; i<=END_NUM; i++ )); do
    # 生成用户名，格式为user001, user002等
    USERNAME=$(printf "user%03d" $i)
    # 端口号与用户编号一致
    PORT=$i
    
    # 检查显示器是否被占用（非VNC会话占用，如物理桌面）
    if is_display_occupied "$PORT"; then
        # 检查是否是当前VNC用户占用的（允许重新配置现有用户）
        EXISTING_VNC_USER=$(grep "^:${PORT}=" /etc/tigervnc/vncserver.users 2>/dev/null | cut -d'=' -f2)
        if [ -n "$EXISTING_VNC_USER" ] && [ "$EXISTING_VNC_USER" = "$USERNAME" ]; then
            echo "显示器 :$PORT 已被 $USERNAME 占用，将重新配置"
        elif [ -n "$EXISTING_VNC_USER" ]; then
            echo "警告: 显示器 :$PORT 已被其他VNC用户 $EXISTING_VNC_USER 占用，跳过 $USERNAME"
            SKIPPED_DISPLAYS+=("$USERNAME:显示器:$PORT被VNC用户$EXISTING_VNC_USER占用")
            continue
        else
            echo "警告: 显示器 :$PORT 已被其他会话占用（可能是物理桌面），跳过 $USERNAME"
            SKIPPED_DISPLAYS+=("$USERNAME:显示器:$PORT被物理桌面或其他会话占用")
            continue
        fi
    fi
    
    echo "处理用户: $USERNAME (端口: $PORT)"
    
    # 检查用户是否已存在
    USER_EXISTS=false
    if id "$USERNAME" &>/dev/null; then
        echo "  用户 $USERNAME 已存在，跳过创建"
        USER_EXISTS=true
    else
        # 创建用户（使用zsh作为默认shell）
        echo "  正在创建用户账户..."
        if sudo useradd -m -s /bin/zsh -c "User $USERNAME" "$USERNAME"; then
            echo "    用户账户创建成功"
            
            # 设置密码
            if echo "$USERNAME:$PASSWORD" | sudo chpasswd; then
                echo "    用户密码设置成功"
                USER_EXISTS=true
            else
                echo "    错误：设置用户密码失败"
                FAILED_USERS+=("$USERNAME:密码设置失败")
            fi
        else
            echo "    错误：创建用户账户失败"
            FAILED_USERS+=("$USERNAME:账户创建失败")
        fi
    fi
    
    # 只有在用户账户存在且有效时才设置VNC
    if [ "$USER_EXISTS" = true ]; then
        if setup_vnc_for_user "$USERNAME" "$PASSWORD" "$PORT"; then
                        CREATED_USERS+=("$USERNAME:$PORT")
                        # 记录信息
                        NOW_TS="$(date '+%Y-%m-%d %H:%M:%S')"
                        VNC_PORT=$((5900 + PORT))
                        printf "%s,%s,%s,%s,%s\n" "$USERNAME" "$PASSWORD" "$VNC_PORT" "$PORT" "$NOW_TS" >> "$PASSWORD_FILE"
                        if head -1 "$CSV_FILE" | grep -q 'created_at'; then
                            printf "%s,%s,%s,%s,%s\n" "$USERNAME" "$PASSWORD" "$VNC_PORT" "$PORT" "$NOW_TS" >> "$CSV_FILE"
                        else
                            printf "%s,%s,%s,%s\n" "$USERNAME" "$PASSWORD" "$VNC_PORT" "$PORT" >> "$CSV_FILE"
                        fi
                        echo "  用户 $USERNAME 配置完成！"
        else
            FAILED_USERS+=("$USERNAME:VNC设置失败")
            echo "  警告：用户 $USERNAME 存在但VNC设置失败"
        fi
    fi
    
    echo "--------------------------------------"
done

echo "======================================"
echo "操作完成！以下是处理结果："
echo "======================================"

# 统计信息
TOTAL_REQUESTED=$((END_NUM - START_NUM + 1))
SUCCESSFUL_COUNT=${#CREATED_USERS[@]}
FAILED_COUNT=${#FAILED_USERS[@]}
SKIPPED_COUNT=${#SKIPPED_DISPLAYS[@]}

echo "总共请求创建用户数: $TOTAL_REQUESTED"
echo "成功处理用户数: $SUCCESSFUL_COUNT"
echo "失败用户数: $FAILED_COUNT"
echo "跳过用户数（显示器被占用）: $SKIPPED_COUNT"
echo ""

if [ ${#CREATED_USERS[@]} -gt 0 ]; then
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            成功创建的用户快速参考表                          ║"
    echo "╠═══════════════╦══════════╦══════════════╦═══════════════════╣"
    echo "║   用户名      ║  显示器  ║   TCP端口    ║  RealVNC连接地址  ║"
    echo "╠═══════════════╬══════════╬══════════════╬═══════════════════╣"
    for USER_INFO in "${CREATED_USERS[@]}"; do
        USERNAME="${USER_INFO%%:*}"
        PORT="${USER_INFO##*:}"
        VNC_PORT=$((5900 + PORT))
        printf "║ %-13s ║   :%-6s ║   %-10s ║  <IP>:%-11s ║\n" "$USERNAME" "$PORT" "$VNC_PORT" "$PORT"
    done
    echo "╚═══════════════╩══════════╩══════════════╩═══════════════════╝"
    echo ""
    
    echo "详细配置信息："
    for USER_INFO in "${CREATED_USERS[@]}"; do
        USERNAME="${USER_INFO%%:*}"
        PORT="${USER_INFO##*:}"
        VNC_PORT=$((5900 + PORT))
        echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  ✓ 用户名: $USERNAME"
        echo "  ✓ 显示器编号: :$PORT"
        echo "  ✓ VNC端口: $VNC_PORT (TCP)"
        echo "  ✓ Shell: /bin/zsh"
        echo "  ✓ 账户密码: $PASSWORD"
        echo "  ✓ VNC密码: $PASSWORD"
        echo "  ✓ VNC连接地址: <服务器IP>:$PORT (或 <服务器IP>:$VNC_PORT)"
        echo "  ✓ VNC配置文件: /home/$USERNAME/.vnc/passwd"
        echo "  ✓ VNC系统服务: vncserver@:$PORT.service"
    done
    echo "  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

if [ ${#FAILED_USERS[@]} -gt 0 ]; then
    echo ""
    echo "失败的用户列表："
    for FAILED_INFO in "${FAILED_USERS[@]}"; do
        USERNAME="${FAILED_INFO%%:*}"
        REASON="${FAILED_INFO##*:}"
        echo "  ✗ 用户名: $USERNAME - 失败原因: $REASON"
    done
fi

if [ ${#SKIPPED_DISPLAYS[@]} -gt 0 ]; then
    echo ""
    echo "跳过的用户列表（显示器被占用）："
    for SKIPPED_INFO in "${SKIPPED_DISPLAYS[@]}"; do
        USERNAME="${SKIPPED_INFO%%:*}"
        REASON="${SKIPPED_INFO#*:}"
        echo "  ⊘ 用户名: $USERNAME - 原因: $REASON"
    done
    echo ""
    echo "提示: 如需使用这些用户，请选择其他编号范围或释放被占用的显示器"
fi

echo ""
echo "======================================"
echo "注意事项："
echo "1. 所有用户的账户密码和VNC密码均为: $PASSWORD"
echo "2. 所有用户的默认shell为: /bin/zsh"
echo "3. VNC配置文件位于各用户的 ~/.vnc/passwd"
echo "4. VNC启动脚本位于各用户的 ~/.vnc/xstartup"
echo "5. VNC端口配置文件: /etc/tigervnc/vncserver.users"
echo "6. 端口号与用户编号一致 (user001 -> 端口1 -> TCP 5901)"
echo "7. VNC系统服务已自动启用并启动 (vncserver@:<端口>.service)"
echo "8. 防火墙端口已自动开放 (如果使用firewalld)"
echo "9. VNC连接地址格式: <服务器IP>:<端口号> 或 <服务器IP>:590<端口号>"
echo "   例如: 192.168.1.100:1 或 192.168.1.100:5901"
echo ""
echo "RealVNC Viewer 连接设置："
echo "  - 服务器地址: <IP>:<端口> (例如 192.168.1.100:1)"
echo "  - 加密方式: Prefer off (TigerVNC不支持RealVNC加密)"
echo "  - 认证密码: VNC密码 ($PASSWORD)"
echo ""
echo "常用命令："
echo "  - 查看VNC服务状态: sudo systemctl status vncserver@:<端口>.service"
echo "  - 重启VNC服务: sudo systemctl restart vncserver@:<端口>.service"
echo "  - 查看VNC日志: journalctl -u vncserver@:<端口>.service -e"
echo "  - 查看当前占用的显示器: ls -la /tmp/.X11-unix/"
echo "  - 查看防火墙端口: firewall-cmd --list-ports"
echo "  - 手动开放端口: firewall-cmd --add-port=5901/tcp --permanent && firewall-cmd --reload"
echo ""
echo "如需删除用户，请执行以下步骤："
echo "  1) sudo systemctl stop vncserver@:<端口>.service"
echo "  2) sudo systemctl disable vncserver@:<端口>.service"
echo "  3) sudo userdel -r [用户名]"
echo "  4) sudo sed -i '/^:<端口>=[用户名]$/d' /etc/tigervnc/vncserver.users"
echo "  5) sudo firewall-cmd --remove-port=590<端口>/tcp --permanent && sudo firewall-cmd --reload"
echo ""
echo "前置要求："
echo "  - TigerVNC Server 和 zsh 会自动安装（如果缺失）"
echo "  - 桌面环境: yum groupinstall -y \"Server with GUI\""
echo "  - 或轻量级桌面: yum install -y epel-release && yum groupinstall -y \"Xfce\""
echo ""
echo "显示器占用说明："
echo "  - 脚本会自动检测并跳过被物理桌面占用的显示器编号"
echo "  - 检查当前占用: ls -la /tmp/.X11-unix/ 和 ps aux | grep Xorg"
echo "  - 新服务器上通常所有显示器都是空闲的，可以正常创建user001-user025"
echo "======================================"
