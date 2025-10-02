#!/bin/bash

# VNC用户删除脚本
# 使用方法：sudo ./delete_vnc_user.sh

# 检查是否以root运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误：此脚本需要使用 root 权限运行！"
    echo "请使用: sudo $0"
    exit 1
fi

# VNC配置文件路径
VNC_CONFIG_FILE="/etc/tigervnc/vncserver.users"

# 获取所有VNC用户列表
function get_vnc_users() {
    local VNC_USERS=()
    
    if [ ! -f "$VNC_CONFIG_FILE" ]; then
        echo "警告：VNC配置文件不存在: $VNC_CONFIG_FILE"
        return 1
    fi
    
    while IFS= read -r line; do
        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        
        # 解析格式 :PORT=USERNAME
        if [[ "$line" =~ ^:([0-9]+)=(.+)$ ]]; then
            local PORT="${BASH_REMATCH[1]}"
            local USERNAME="${BASH_REMATCH[2]}"
            VNC_USERS+=("$USERNAME:$PORT")
        fi
    done < "$VNC_CONFIG_FILE"
    
    echo "${VNC_USERS[@]}"
}

# 显示VNC用户列表
function display_vnc_users() {
    local USERS=("$@")
    
    if [ ${#USERS[@]} -eq 0 ]; then
        echo "未找到任何配置的VNC用户"
        return 1
    fi
    
    echo "======================================"
    echo "当前配置的VNC用户列表："
    echo "======================================"
    printf "%-5s %-15s %-10s %-12s %-10s\n" "序号" "用户名" "显示器" "VNC端口" "服务状态"
    echo "--------------------------------------"
    
    local index=1
    for USER_INFO in "${USERS[@]}"; do
        local USERNAME="${USER_INFO%%:*}"
        local PORT="${USER_INFO##*:}"
        local VNC_PORT=$((5900 + PORT))
        local SERVICE_NAME="vncserver@:$PORT.service"
        
        # 检查服务状态
        local STATUS="未知"
        if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
            STATUS="运行中"
        elif systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
            STATUS="已停止"
        else
            STATUS="未启用"
        fi
        
        printf "%-5s %-15s %-10s %-12s %-10s\n" "$index" "$USERNAME" ":$PORT" "$VNC_PORT" "$STATUS"
        ((index++))
    done
    echo "======================================"
    
    return 0
}

# 停止并禁用VNC服务
function stop_vnc_service() {
    local PORT=$1
    local SERVICE_NAME="vncserver@:$PORT.service"
    
    echo "  正在停止VNC服务: $SERVICE_NAME"
    
    # 停止服务
    if systemctl is-active "$SERVICE_NAME" &>/dev/null; then
        if systemctl stop "$SERVICE_NAME" &>/dev/null; then
            echo "    ✓ VNC服务已停止"
        else
            echo "    ✗ 警告：停止VNC服务失败"
            return 1
        fi
    else
        echo "    - VNC服务未运行，跳过停止"
    fi
    
    # 禁用服务
    if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
        if systemctl disable "$SERVICE_NAME" &>/dev/null; then
            echo "    ✓ VNC服务已禁用"
        else
            echo "    ✗ 警告：禁用VNC服务失败"
            return 1
        fi
    else
        echo "    - VNC服务未启用，跳过禁用"
    fi
    
    return 0
}

# 关闭防火墙端口
function close_firewall_port() {
    local PORT=$1
    local VNC_PORT=$((5900 + PORT))
    
    # 检查firewalld是否运行
    if ! command -v firewall-cmd >/dev/null 2>&1; then
        echo "    - firewall-cmd 未找到，跳过防火墙配置"
        return 0
    fi
    
    if ! systemctl is-active firewalld &>/dev/null; then
        echo "    - firewalld 未运行，跳过防火墙配置"
        return 0
    fi
    
    echo "  正在关闭防火墙端口: $VNC_PORT/tcp"
    
    # 检查端口是否开放
    if ! firewall-cmd --query-port=$VNC_PORT/tcp &>/dev/null; then
        echo "    - 端口 $VNC_PORT/tcp 未开放，跳过"
        return 0
    fi
    
    # 关闭端口
    if firewall-cmd --remove-port=$VNC_PORT/tcp --permanent &>/dev/null; then
        if firewall-cmd --reload &>/dev/null; then
            echo "    ✓ 已关闭端口: $VNC_PORT/tcp"
            return 0
        else
            echo "    ✗ 警告：防火墙重载失败"
            return 1
        fi
    else
        echo "    ✗ 警告：关闭端口失败: $VNC_PORT/tcp"
        return 1
    fi
}

# 从VNC配置文件中移除用户
function remove_vnc_config() {
    local USERNAME=$1
    local PORT=$2
    local CONFIG_LINE=":$PORT=$USERNAME"
    
    echo "  正在从VNC配置文件中移除用户..."
    
    if [ ! -f "$VNC_CONFIG_FILE" ]; then
        echo "    - VNC配置文件不存在，跳过"
        return 0
    fi
    
    if grep -q "^$CONFIG_LINE$" "$VNC_CONFIG_FILE"; then
        if sed -i "/^$CONFIG_LINE$/d" "$VNC_CONFIG_FILE"; then
            echo "    ✓ 已从VNC配置文件中移除: $CONFIG_LINE"
            return 0
        else
            echo "    ✗ 警告：从VNC配置文件移除失败"
            return 1
        fi
    else
        echo "    - 配置项不存在，跳过"
        return 0
    fi
}

# 清理用户的VNC相关文件
function cleanup_vnc_files() {
    local USERNAME=$1
    local PORT=$2
    
    echo "  正在清理VNC相关文件..."
    
    # 清理用户VNC目录
    if [ -d "/home/$USERNAME/.vnc" ]; then
        if rm -rf "/home/$USERNAME/.vnc"; then
            echo "    ✓ 已删除: /home/$USERNAME/.vnc"
        else
            echo "    ✗ 警告：删除VNC目录失败"
        fi
    else
        echo "    - VNC目录不存在，跳过"
    fi
    
    # 清理VNC锁文件和socket
    local LOCK_FILE="/tmp/.X${PORT}-lock"
    local SOCKET_FILE="/tmp/.X11-unix/X${PORT}"
    
    if [ -f "$LOCK_FILE" ]; then
        if rm -f "$LOCK_FILE"; then
            echo "    ✓ 已删除锁文件: $LOCK_FILE"
        else
            echo "    ✗ 警告：删除锁文件失败"
        fi
    fi
    
    if [ -S "$SOCKET_FILE" ]; then
        if rm -f "$SOCKET_FILE"; then
            echo "    ✓ 已删除socket文件: $SOCKET_FILE"
        else
            echo "    ✗ 警告：删除socket文件失败"
        fi
    fi
    
    # 清理用户进程
    echo "  正在终止用户的VNC相关进程..."
    if pkill -u "$USERNAME" -9 &>/dev/null; then
        echo "    ✓ 已终止用户进程"
    else
        echo "    - 没有运行中的用户进程"
    fi
}

# 删除用户账户
function delete_user_account() {
    local USERNAME=$1
    
    echo "  正在删除用户账户..."
    
    if ! id "$USERNAME" &>/dev/null; then
        echo "    ✗ 警告：用户 $USERNAME 不存在"
        return 1
    fi
    
    # 使用 -r 参数删除用户的家目录和邮件池
    if userdel -r "$USERNAME" &>/dev/null 2>&1; then
        echo "    ✓ 用户账户已删除: $USERNAME"
        echo "    ✓ 用户家目录已删除: /home/$USERNAME"
        return 0
    else
        # 如果失败，可能是因为用户有运行中的进程
        echo "    ✗ 警告：删除用户失败，尝试强制删除..."
        
        # 强制终止所有用户进程
        pkill -9 -u "$USERNAME" &>/dev/null
        sleep 1
        
        # 再次尝试删除
        if userdel -r "$USERNAME" &>/dev/null 2>&1; then
            echo "    ✓ 用户账户已强制删除: $USERNAME"
            return 0
        else
            echo "    ✗ 错误：无法删除用户账户"
            echo "    提示：请手动执行 'userdel -r $USERNAME'"
            return 1
        fi
    fi
}

# 完整删除用户
function delete_vnc_user() {
    local USERNAME=$1
    local PORT=$2
    
    echo "======================================"
    echo "开始删除用户: $USERNAME (端口: $PORT)"
    echo "======================================"
    
    local SUCCESS=true
    
    # 1. 停止并禁用VNC服务
    if ! stop_vnc_service "$PORT"; then
        SUCCESS=false
    fi
    
    # 2. 关闭防火墙端口
    if ! close_firewall_port "$PORT"; then
        SUCCESS=false
    fi
    
    # 3. 从VNC配置文件中移除
    if ! remove_vnc_config "$USERNAME" "$PORT"; then
        SUCCESS=false
    fi
    
    # 4. 清理VNC相关文件
    cleanup_vnc_files "$USERNAME" "$PORT"
    
    # 5. 删除用户账户
    if ! delete_user_account "$USERNAME"; then
        SUCCESS=false
    fi
    
    echo "======================================"
    if [ "$SUCCESS" = true ]; then
        echo "✓ 用户 $USERNAME 删除完成！"
    else
        echo "⚠ 用户 $USERNAME 删除完成，但有部分警告"
    fi
    echo "======================================"
    
    return 0
}

# 批量删除用户
function batch_delete_users() {
    local USERS=("$@")
    local DELETED_COUNT=0
    local FAILED_COUNT=0
    
    echo ""
    echo "======================================"
    echo "开始批量删除用户..."
    echo "======================================"
    
    for USER_INFO in "${USERS[@]}"; do
        local USERNAME="${USER_INFO%%:*}"
        local PORT="${USER_INFO##*:}"
        
        if delete_vnc_user "$USERNAME" "$PORT"; then
            ((DELETED_COUNT++))
        else
            ((FAILED_COUNT++))
        fi
        echo ""
    done
    
    echo "======================================"
    echo "批量删除完成！"
    echo "成功删除: $DELETED_COUNT 个用户"
    echo "删除失败: $FAILED_COUNT 个用户"
    echo "======================================"
}

# 主程序
echo "======================================"
echo "VNC用户删除工具"
echo "======================================"

# 获取VNC用户列表
VNC_USERS_ARRAY=($(get_vnc_users))

if [ ${#VNC_USERS_ARRAY[@]} -eq 0 ]; then
    echo "未找到任何配置的VNC用户"
    echo "VNC配置文件: $VNC_CONFIG_FILE"
    exit 0
fi

# 显示用户列表
if ! display_vnc_users "${VNC_USERS_ARRAY[@]}"; then
    exit 1
fi

# 交互式选择
echo ""
echo "请选择操作："
echo "1) 删除单个用户"
echo "2) 删除多个用户"
echo "3) 删除全部用户"
echo "4) 退出"
echo ""
read -p "请输入选项 (1-4): " OPERATION

case $OPERATION in
    1)
        # 删除单个用户
        read -p "请输入要删除的用户序号: " INDEX
        
        if ! [[ "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -lt 1 ] || [ "$INDEX" -gt ${#VNC_USERS_ARRAY[@]} ]; then
            echo "错误：无效的序号"
            exit 1
        fi
        
        SELECTED_USER="${VNC_USERS_ARRAY[$((INDEX-1))]}"
        USERNAME="${SELECTED_USER%%:*}"
        PORT="${SELECTED_USER##*:}"
        
        echo ""
        echo "将要删除用户: $USERNAME (端口: $PORT)"
        read -p "确认删除？(y/N): " CONFIRM
        
        if [[ $CONFIRM =~ ^[Yy]$ ]]; then
            delete_vnc_user "$USERNAME" "$PORT"
        else
            echo "操作已取消"
        fi
        ;;
        
    2)
        # 删除多个用户
        read -p "请输入要删除的用户序号（用空格或逗号分隔，例如: 1 2 3 或 1,2,3): " INDICES
        
        # 处理逗号分隔的输入
        INDICES=${INDICES//,/ }
        
        SELECTED_USERS=()
        for INDEX in $INDICES; do
            if ! [[ "$INDEX" =~ ^[0-9]+$ ]] || [ "$INDEX" -lt 1 ] || [ "$INDEX" -gt ${#VNC_USERS_ARRAY[@]} ]; then
                echo "警告：忽略无效序号: $INDEX"
                continue
            fi
            SELECTED_USERS+=("${VNC_USERS_ARRAY[$((INDEX-1))]}")
        done
        
        if [ ${#SELECTED_USERS[@]} -eq 0 ]; then
            echo "错误：没有选择有效的用户"
            exit 1
        fi
        
        echo ""
        echo "将要删除以下用户："
        for USER_INFO in "${SELECTED_USERS[@]}"; do
            USERNAME="${USER_INFO%%:*}"
            PORT="${USER_INFO##*:}"
            echo "  - $USERNAME (端口: $PORT)"
        done
        
        read -p "确认删除这些用户？(y/N): " CONFIRM
        
        if [[ $CONFIRM =~ ^[Yy]$ ]]; then
            batch_delete_users "${SELECTED_USERS[@]}"
        else
            echo "操作已取消"
        fi
        ;;
        
    3)
        # 删除全部用户
        echo ""
        echo "警告：即将删除所有VNC用户 (共 ${#VNC_USERS_ARRAY[@]} 个)"
        read -p "确认删除全部用户？(y/N): " CONFIRM
        
        if [[ $CONFIRM =~ ^[Yy]$ ]]; then
            read -p "再次确认：这将删除所有VNC用户及其数据，是否继续？(yes/NO): " FINAL_CONFIRM
            if [[ "$FINAL_CONFIRM" == "yes" ]]; then
                batch_delete_users "${VNC_USERS_ARRAY[@]}"
            else
                echo "操作已取消"
            fi
        else
            echo "操作已取消"
        fi
        ;;
        
    4)
        echo "操作已取消"
        exit 0
        ;;
        
    *)
        echo "错误：无效的选项"
        exit 1
        ;;
esac

echo ""
echo "======================================"
echo "清理完成！"
echo ""
echo "提示："
echo "- 如需查看剩余VNC用户: cat $VNC_CONFIG_FILE"
echo "- 如需查看剩余服务: systemctl list-units --type=service | grep vnc"
echo "- 如需查看防火墙端口: firewall-cmd --list-ports"
echo "======================================"

