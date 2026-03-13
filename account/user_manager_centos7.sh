#!/bin/bash

# 用户和VNC管理交互式脚本
# 功能：批量创建用户、设置密码、配置VNC

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

prompt_info() {
    print_info "$1" >&2
}

prompt_warning() {
    print_warning "$1" >&2
}

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "此脚本需要使用 root 权限运行！"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 使用指定用户执行命令（兼容无sudo环境）
run_as_user() {
    local username=$1
    shift

    if command -v runuser >/dev/null 2>&1; then
        runuser -u "$username" -- "$@"
        return $?
    fi

    su -s /bin/bash "$username" -c "$(printf '%q ' "$@")"
}

# 检查 firewalld 命令是否可用
has_firewall_cmd() {
    command -v firewall-cmd >/dev/null 2>&1
}

# 获取 runuser 可执行路径
get_runuser_bin() {
    if command -v runuser >/dev/null 2>&1; then
        command -v runuser
        return 0
    fi

    if [ -x "/sbin/runuser" ]; then
        echo "/sbin/runuser"
        return 0
    fi

    if [ -x "/usr/sbin/runuser" ]; then
        echo "/usr/sbin/runuser"
        return 0
    fi

    return 1
}

# 获取会话启动命令
get_session_start_command() {
    local session=$1

    case "$session" in
        gnome|gnome-session)
            echo "/usr/bin/gnome-session"
            ;;
        mate|mate-session)
            echo "/usr/bin/mate-session"
            ;;
        kde|plasma|plasma-x11)
            echo "/usr/bin/startplasma-x11"
            ;;
        *)
            echo "$session"
            ;;
    esac
}

# 为指定显示号创建 CentOS 7 兼容的 TigerVNC 单元文件
ensure_legacy_vnc_unit_file() {
    local username=$1
    local display_no=$2
    local geometry=$3
    local localhost_mode=$4
    local unit_file="/etc/systemd/system/vncserver@:${display_no}.service"
    local localhost_arg=""

    if [ "$localhost_mode" = "yes" ]; then
        localhost_arg="-localhost"
    fi

    cat > "$unit_file" <<EOF
[Unit]
Description=Remote desktop service (TigerVNC) for ${username} on :${display_no}
After=syslog.target network.target

[Service]
Type=forking
PermissionsStartOnly=true
User=${username}
Group=${username}
WorkingDirectory=/home/${username}
PIDFile=/home/${username}/.vnc/%H:${display_no}.pid
ExecStartPre=-/usr/bin/bash -c '/usr/bin/vncserver -kill :${display_no} >/dev/null 2>&1 || true'
ExecStartPre=-/usr/bin/bash -c '/usr/bin/rm -f /tmp/.X${display_no}-lock /tmp/.X11-unix/X${display_no} /home/${username}/.vnc/*:${display_no}.pid >/dev/null 2>&1 || true'
ExecStart=/usr/bin/vncserver :${display_no} -geometry ${geometry} ${localhost_arg}
ExecStop=/usr/bin/vncserver -kill :${display_no}

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$unit_file"
    print_success "已生成CentOS7 VNC服务单元: $unit_file"
    return 0
}

# 删除指定显示号的自定义 VNC 单元文件
remove_legacy_vnc_unit_file() {
    local display_no=$1
    local unit_file="/etc/systemd/system/vncserver@:${display_no}.service"

    if [ -f "$unit_file" ]; then
        rm -f "$unit_file"
        print_success "已删除自定义VNC单元: $unit_file"
    fi
}

# 获取系统可用的shell并让用户选择
select_shell() {
    # 读取系统中可用的shell
    if [ ! -f "/etc/shells" ]; then
        print_error "/etc/shells 文件不存在，使用默认shell /bin/bash" >&2
        echo "/bin/bash"
        return
    fi
    
    # 获取有效的shell列表（排除注释和空行）
    local shells=()
    while IFS= read -r line; do
        # 跳过注释和空行
        if [[ ! "$line" =~ ^[[:space:]]*# ]] && [ -n "$line" ] && [ -x "$line" ]; then
            shells+=("$line")
        fi
    done < /etc/shells
    
    if [ ${#shells[@]} -eq 0 ]; then
        print_error "未找到可用的shell，使用默认shell /bin/bash" >&2
        echo "/bin/bash"
        return
    fi
    
    # 显示可用的shell列表
    echo "" >&2
    prompt_info "系统中可用的Shell列表："
    for i in "${!shells[@]}"; do
        echo "  $((i+1))) ${shells[$i]}" >&2
    done
    echo "" >&2
    prompt_info "请选择默认shell (输入序号) [默认: 1]:"
    read -r shell_choice
    
    # 验证输入
    if [ -z "$shell_choice" ]; then
        shell_choice=1
    fi
    
    # 检查输入是否为有效数字
    if ! [[ "$shell_choice" =~ ^[0-9]+$ ]] || [ "$shell_choice" -lt 1 ] || [ "$shell_choice" -gt ${#shells[@]} ]; then
        prompt_warning "无效的选择，使用第一个shell: ${shells[0]}"
        echo "${shells[0]}"
        return
    fi
    
    # 返回选择的shell（数组索引从0开始）
    echo "${shells[$((shell_choice-1))]}"
}



# 创建用户函数
create_user() {
    local username=$1
    local password=$2
    local shell=$3
    local comment=$4
    
    if [ -z "$username" ]; then
        print_error "用户名不能为空"
        return 1
    fi
    
    # 检查用户是否已存在
    if id "$username" &>/dev/null; then
        print_warning "用户 $username 已存在，跳过创建"
        return 2
    fi
    
    # 创建用户
    print_info "正在创建用户: $username"
    if [ -n "$comment" ]; then
        if ! useradd -m -s "$shell" -c "$comment" "$username" 2>&1; then
            print_error "创建用户 $username 失败"
            return 1
        fi
    else
        if ! useradd -m -s "$shell" "$username" 2>&1; then
            print_error "创建用户 $username 失败"
            return 1
        fi
    fi
    
    # 设置密码
    if ! echo "$username:$password" | chpasswd 2>&1; then
        print_error "为用户 $username 设置密码失败"
        return 1
    fi
    
    print_success "已创建用户 $username, shell: $shell, 密码: $password"
    return 0
}

# 设置VNC密码函数
setup_vnc() {
    local username=$1
    local vnc_password=$2
    
    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        print_warning "用户 $username 不存在，跳过VNC配置"
        return 1
    fi
    
    # 检查vncpasswd命令是否可用
    if ! command -v vncpasswd &> /dev/null; then
        print_error "vncpasswd 命令未找到，请先安装 TigerVNC 或 TightVNC"
        echo "CentOS 7 可尝试: yum install -y tigervnc-server"
        return 1
    fi
    
    # 创建.vnc目录（如果不存在）
    if [ ! -d "/home/$username/.vnc" ]; then
        mkdir -p "/home/$username/.vnc"
        chown "$username:$username" "/home/$username/.vnc"
        chmod 700 "/home/$username/.vnc"
        print_info "已创建 /home/$username/.vnc 目录"
    fi
    
    # 设置VNC密码
    print_info "正在为 $username 设置VNC密码..."
    if ! printf '%s\n' "$vnc_password" | run_as_user "$username" vncpasswd -f > "/home/$username/.vnc/passwd"; then
        print_error "为用户 $username 生成VNC密码文件失败"
        return 1
    fi
    
    # 设置权限
    chown "$username:$username" "/home/$username/.vnc/passwd"
    chmod 600 "/home/$username/.vnc/passwd"
    
    print_success "用户 $username 的VNC密码已设置为: $vnc_password"
    return 0
}

# 询问是否使用 systemd 管理 TigerVNC
ask_systemd_vnc_mode() {
    prompt_info "是否使用 systemd 管理 VNC（推荐，支持开机自启）？(y/n) [默认: y]:"
    read -r systemd_choice

    if [ -z "$systemd_choice" ] || [[ "$systemd_choice" =~ ^[Yy]$ ]]; then
        echo "y"
    else
        echo "n"
    fi
}

# 读取并校验显示号（不带冒号）
ask_start_display() {
    local prompt="$1"
    local default_display="$2"
    local display_no

    prompt_info "$prompt [默认: $default_display]:"
    read -r display_no

    if [ -z "$display_no" ]; then
        display_no="$default_display"
    fi

    if ! [[ "$display_no" =~ ^[0-9]+$ ]]; then
        prompt_warning "显示号无效，使用默认值: $default_display"
        display_no="$default_display"
    fi

    echo "$display_no"
}

# 询问并获取VNC桌面配置
ask_vnc_desktop_config() {
    local default_geometry="1920x1080"
    local default_session="gnome"
    local geometry
    local session
    local localhost_choice
    local localhost_value="no"

    prompt_info "请输入VNC分辨率 [默认: $default_geometry]:"
    read -r geometry
    if [ -z "$geometry" ]; then
        geometry="$default_geometry"
    fi

    prompt_info "请输入桌面会话（如 gnome）[默认: $default_session]:"
    read -r session
    if [ -z "$session" ]; then
        session="$default_session"
    fi

    prompt_info "是否仅允许本机访问（localhost）？(y/n) [默认: n]:"
    read -r localhost_choice
    if [[ "$localhost_choice" =~ ^[Yy]$ ]]; then
        localhost_value="yes"
    fi

    echo "$geometry|$session|$localhost_value"
}

# 获取映射文件中指定显示号的用户
get_mapped_display_owner() {
    local display_no=$1
    local map_file="/etc/tigervnc/vncserver.users"

    if [ ! -f "$map_file" ]; then
        return 0
    fi

    awk -F'=' -v target=":${display_no}" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        $1 == target { print $2; exit }
    ' "$map_file"
}

# 获取旧版自定义单元中指定显示号的用户
get_legacy_unit_display_owner() {
    local display_no=$1
    local unit_file="/etc/systemd/system/vncserver@:${display_no}.service"

    if [ ! -f "$unit_file" ]; then
        return 0
    fi

    awk -F'=' '
        /^User=/ { print $2; exit }
    ' "$unit_file"
}

# 检查会话可用性与关键依赖
check_vnc_runtime_requirements() {
    local session=$1
    local session_cmd
    local has_fallback=0

    if ! command -v xauth >/dev/null 2>&1; then
        print_error "缺少 xauth，TigerVNC 无法启动"
        echo "请安装: yum install -y xorg-x11-xauth"
        return 1
    fi

    session_cmd=$(get_session_start_command "$session")
    if command -v "$session_cmd" >/dev/null 2>&1; then
        return 0
    fi

    if [ -x /etc/X11/xinit/xinitrc ]; then
        has_fallback=1
    fi

    if command -v xterm >/dev/null 2>&1; then
        has_fallback=1
    fi

    if [ "$has_fallback" -eq 1 ]; then
        print_warning "会话 '$session' 不可用，将使用 xstartup 回退会话"
        return 0
    fi

    print_error "找不到可用桌面会话（$session/xinitrc/xterm）"
    echo "可尝试安装GNOME或安装 xterm 作为回退终端"
    return 1
}

# 将用户映射到 /etc/tigervnc/vncserver.users
set_vnc_display_mapping() {
    local username=$1
    local display_no=$2
    local map_file="/etc/tigervnc/vncserver.users"
    local map_dir
    local tmp_file

    map_dir=$(dirname "$map_file")
    mkdir -p "$map_dir"

    if [ ! -f "$map_file" ]; then
        if ! touch "$map_file"; then
            print_error "无法创建 $map_file"
            return 1
        fi
    fi

    tmp_file=$(mktemp)

    awk -v display=":${display_no}" -v user="$username" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
        {
            if ($0 ~ ("=" user "$") || $0 ~ ("^" display "=")) {
                next
            }
            print
        }
        END {
            print display "=" user
        }
    ' "$map_file" > "$tmp_file"

    cp "$tmp_file" "$map_file"
    rm -f "$tmp_file"
    chmod 644 "$map_file"

    print_success "已设置VNC显示映射: :$display_no=$username"
}

# 生成 CentOS 7 兼容的 ~/.vnc/xstartup
write_vnc_xstartup() {
    local username=$1
    local session=$2
    local home_dir="/home/$username"
    local vnc_dir="$home_dir/.vnc"
    local startup_file="$vnc_dir/xstartup"
    local session_cmd

    mkdir -p "$vnc_dir"
    session_cmd=$(get_session_start_command "$session")

    cat > "$startup_file" <<EOF
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

if command -v ${session_cmd} >/dev/null 2>&1; then
    exec ${session_cmd}
fi

if [ -x /etc/X11/xinit/xinitrc ]; then
    exec /etc/X11/xinit/xinitrc
fi

if command -v xterm >/dev/null 2>&1; then
    exec xterm
fi

exit 1
EOF

    chown "$username:$username" "$vnc_dir" "$startup_file"
    chmod 700 "$vnc_dir"
    chmod 700 "$startup_file"

    print_success "已写入 $startup_file（会话: $session）"
}

# 获取当前占用指定显示号的Xvnc用户（若无则为空）
get_display_owner() {
    local display_no=$1
    local owner

    owner=$(ps -eo user,args | awk -v d=":${display_no}" '
        index($0, "/usr/bin/Xvnc " d " ") { print $1; exit }
        $0 ~ ("/usr/bin/Xvnc " d "$") { print $1; exit }
    ')

    if [ -n "$owner" ]; then
        echo "$owner"
        return 0
    fi

    owner=$(get_mapped_display_owner "$display_no")
    if [ -n "$owner" ]; then
        echo "$owner"
        return 0
    fi

    owner=$(get_legacy_unit_display_owner "$display_no")
    if [ -n "$owner" ]; then
        echo "$owner"
    fi
}

# 强制回收显示号（停止旧会话并清理锁文件）
force_reclaim_display() {
    local display_no=$1

    # 优先尝试通过vncserver wrapper终止，失败时回退到pkill
    vncserver -kill ":$display_no" >/dev/null 2>&1 || true
    pkill -f "^/usr/bin/Xvnc :${display_no} " >/dev/null 2>&1 || true

    rm -f "/tmp/.X${display_no}-lock" "/tmp/.X11-unix/X${display_no}"
}

# 获取用户在旧版CentOS7自定义VNC单元中的显示号列表（不带冒号）
get_user_vnc_displays_from_legacy_units() {
    local username=$1
    local unit_file
    local display_no

    for unit_file in /etc/systemd/system/vncserver@:*.service; do
        [ -e "$unit_file" ] || continue

        if ! grep -Eq "^User=${username}$|ExecStart=.*-l[[:space:]]+${username}([[:space:]]|$)" "$unit_file"; then
            continue
        fi

        display_no=$(basename "$unit_file" | sed -E 's/^vncserver@:(.+)\.service$/\1/')
        if [[ "$display_no" =~ ^[0-9]+$ ]]; then
            echo "$display_no"
        fi
    done
}

# 获取用户当前运行中的Xvnc显示号列表（不带冒号）
get_user_vnc_displays_from_processes() {
    local username=$1

    ps -eo user,args | awk -v user="$username" '
        $1 != user { next }
        match($0, /\/usr\/bin\/Xvnc :([0-9]+)/, m) { print m[1] }
    '
}

# 获取用户在 /etc/tigervnc/vncserver.users 或旧版自定义VNC单元中的显示号列表（不带冒号）
get_user_vnc_displays() {
    local username=$1
    local map_file="/etc/tigervnc/vncserver.users"
    local mapping_displays=""
    local legacy_displays=""
    local process_displays=""

    if [ -f "$map_file" ]; then
        mapping_displays=$(awk -F'=' -v user="$username" '
            /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
            $2 == user {
                gsub(/^:/, "", $1)
                print $1
            }
        ' "$map_file")
    fi

    legacy_displays=$(get_user_vnc_displays_from_legacy_units "$username")
    process_displays=$(get_user_vnc_displays_from_processes "$username")

    printf '%s\n%s\n%s\n' "$mapping_displays" "$legacy_displays" "$process_displays" \
        | awk 'NF && $0 ~ /^[0-9]+$/ && !seen[$0]++ { print }' \
        | sort -n
}

# 删除用户在 /etc/tigervnc/vncserver.users 的映射
remove_user_vnc_mappings() {
    local username=$1
    local map_file="/etc/tigervnc/vncserver.users"
    local tmp_file

    if [ ! -f "$map_file" ]; then
        return 0
    fi

    tmp_file=$(mktemp)
    awk -F'=' -v user="$username" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
        $2 == user { next }
        { print }
    ' "$map_file" > "$tmp_file"

    cp "$tmp_file" "$map_file"
    rm -f "$tmp_file"
    chmod 644 "$map_file"
}

# 获取活动防火墙zone（默认取第一个活动zone；取不到则回退public）
get_active_firewalld_zone() {
    local zone

    if ! has_firewall_cmd; then
        return 1
    fi

    zone=$(firewall-cmd --get-active-zones 2>/dev/null | awk 'NF{print $1; exit}')
    if [ -z "$zone" ]; then
        zone="public"
    fi
    echo "$zone"
}

# 清理用户的VNC资源（映射、service、进程、端口）
cleanup_vnc_for_user() {
    local username=$1
    local displays
    local zone
    local firewall_changed=0
    local manage_firewall=0
    local unit_file_removed=0

    displays=$(get_user_vnc_displays "$username")

    if [ -z "$displays" ]; then
        remove_user_vnc_mappings "$username"
        print_warning "未发现用户 $username 的VNC显示号（已尝试清理映射）"
        return 0
    fi

    if has_firewall_cmd; then
        zone=$(get_active_firewalld_zone)
        if [ -n "$zone" ]; then
            manage_firewall=1
        fi
    else
        print_warning "未检测到 firewall-cmd，跳过防火墙端口清理"
    fi

    for d in $displays; do
        local unit_name="vncserver@:${d}.service"
        local port=$((5900 + d))

        systemctl stop "$unit_name" >/dev/null 2>&1 || true
        systemctl disable "$unit_name" >/dev/null 2>&1 || true
        remove_legacy_vnc_unit_file "$d"
        unit_file_removed=1
        force_reclaim_display "$d"
        print_success "已停止并禁用 $unit_name"

        if [ "$manage_firewall" -eq 1 ] && firewall-cmd --zone="$zone" --query-port="${port}/tcp" >/dev/null 2>&1; then
            firewall-cmd --permanent --zone="$zone" --remove-port="${port}/tcp" >/dev/null 2>&1 || true
            firewall_changed=1
            print_success "已从防火墙zone($zone)移除端口 ${port}/tcp"
        fi
    done

    remove_user_vnc_mappings "$username"
    print_success "已清理用户 $username 的VNC显示号映射"

    if [ "$unit_file_removed" -eq 1 ]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi

    if [ "$manage_firewall" -eq 1 ] && [ "$firewall_changed" -eq 1 ]; then
        firewall-cmd --reload >/dev/null 2>&1 || true
        print_success "防火墙规则已重载"
    fi

    return 0
}

# 终止用户会话与残留进程，避免 userdel 因“正在使用”失败
terminate_user_runtime() {
    local username=$1

    if [ -z "$username" ]; then
        return 0
    fi

    loginctl terminate-user "$username" >/dev/null 2>&1 || true
    pkill -TERM -u "$username" >/dev/null 2>&1 || true
    sleep 1

    if pgrep -u "$username" >/dev/null 2>&1; then
        pkill -KILL -u "$username" >/dev/null 2>&1 || true
        sleep 1
    fi

    return 0
}

# 删除用户（含VNC清理）
delete_user_with_vnc_cleanup() {
    local username=$1
    local delete_err
    local delete_rc

    if [ -z "$username" ]; then
        print_error "用户名不能为空"
        return 1
    fi

    prompt_info "是否确认删除用户 $username（含VNC服务/端口清理）？(y/n) [默认: n]:"
    read -r confirm_delete
    if ! [[ "$confirm_delete" =~ ^[Yy]$ ]]; then
        prompt_warning "已取消删除用户 $username"
        return 1
    fi

    cleanup_vnc_for_user "$username"
    terminate_user_runtime "$username"

    if id "$username" &>/dev/null; then
        delete_err=$(userdel -r "$username" 2>&1)
        delete_rc=$?

        if [ "$delete_rc" -ne 0 ]; then
            print_warning "首次删除用户 $username 失败，正在重试并强制清理残留会话..."
            terminate_user_runtime "$username"
            delete_err=$(userdel -r "$username" 2>&1)
            delete_rc=$?
        fi

        if [ "$delete_rc" -eq 0 ]; then
            print_success "用户 $username 已删除（含home目录）"
        else
            print_warning "删除用户 $username 失败（退出码: $delete_rc）"
            if [ -n "$delete_err" ]; then
                echo "  userdel错误: $delete_err"
            fi
            return 1
        fi
    else
        print_warning "用户 $username 不存在，已仅执行VNC清理"
    fi

    return 0
}

# 从指定显示号开始查找下一个空闲显示号
find_next_free_display() {
    local start_display=$1
    local probe_display="$start_display"

    while [ "$probe_display" -lt 100 ]; do
        if [ -z "$(get_display_owner "$probe_display")" ]; then
            echo "$probe_display"
            return 0
        fi
        probe_display=$((probe_display + 1))
    done

    return 1
}

# 统一处理显示号冲突（回收/自动分配/取消），返回最终显示号
resolve_display_for_user() {
    local username=$1
    local requested_display=$2
    local owner

    owner=$(get_display_owner "$requested_display")
    if [ -z "$owner" ]; then
        echo "$requested_display"
        return 0
    fi

    if [ "$owner" = "$username" ]; then
        prompt_info "显示号 :$requested_display 当前已由用户 $username 占用，将重启会话以应用新配置"
        force_reclaim_display "$requested_display"
        echo "$requested_display"
        return 0
    fi

    prompt_warning "显示号 :$requested_display 当前被用户 $owner 占用"
    prompt_info "请选择处理方式："
    echo "  1) 强制回收 :$requested_display 并切换给 $username" >&2
    echo "  2) 自动分配下一个空闲显示号（推荐）" >&2
    echo "  3) 取消本次用户VNC配置" >&2
    prompt_info "请输入选项 (1-3) [默认: 2]:"
    read -r conflict_choice

    if [ -z "$conflict_choice" ]; then
        conflict_choice="2"
    fi

    case "$conflict_choice" in
        1)
            force_reclaim_display "$requested_display"
            print_success "已回收显示号 :$requested_display" >&2
            echo "$requested_display"
            return 0
            ;;
        2)
            local next_display
            next_display=$(find_next_free_display $((requested_display + 1))) || {
                print_error "未找到可用的空闲显示号（2-99）" >&2
                return 1
            }
            print_success "已自动分配空闲显示号 :$next_display 给用户 $username" >&2
            echo "$next_display"
            return 0
            ;;
        *)
            prompt_warning "已取消为用户 $username 配置VNC"
            return 1
            ;;
    esac
}

# 启用并启动指定显示号的systemd VNC服务
enable_start_vnc_service() {
    local username=$1
    local display_no=$2
    local geometry=$3
    local localhost_mode=$4
    local unit_name="vncserver@:${display_no}.service"
    local unit_file="/etc/systemd/system/${unit_name}"

    if ! command -v vncserver >/dev/null 2>&1; then
        print_error "未找到 vncserver 命令，请先安装 tigervnc-server"
        return 1
    fi

    if ! ensure_legacy_vnc_unit_file "$username" "$display_no" "$geometry" "$localhost_mode"; then
        return 1
    fi

    if ! systemctl daemon-reload; then
        print_error "systemd daemon-reload 失败"
        return 1
    fi

    if [ ! -f "$unit_file" ]; then
        print_error "未找到自定义VNC单元: $unit_file"
        print_error "已拒绝回退到系统默认 vncserver@.service（可能触发旧版 wrapper 参数问题）"
        return 1
    fi

    if grep -q -- "-localhost no" "$unit_file"; then
        print_warning "检测到旧参数 '-localhost no'，正在自动修复..."
        sed -i 's/ -localhost no//g' "$unit_file"
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi

    if grep -q "vncserver_wrapper" "$unit_file"; then
        print_error "检测到 wrapper 形式单元，已拒绝启动: $unit_file"
        print_error "请删除该单元后重新执行脚本生成自定义单元"
        return 1
    fi

    if ! systemctl enable "$unit_name" >/dev/null 2>&1; then
        print_error "启用 $unit_name 失败"
        return 1
    fi

    if ! systemctl restart "$unit_name"; then
        print_error "重启 $unit_name 失败"
        systemctl status "$unit_name" --no-pager -l 2>/dev/null | tail -n 20 || true
        journalctl -u "$unit_name" -n 20 --no-pager 2>/dev/null || true
        return 1
    fi

    print_success "已启用并启动 $unit_name（端口: $((5900 + display_no))）"
    return 0
}

# 执行完整的 systemd VNC 配置流程
setup_vnc_systemd() {
    local username=$1
    local display_no=$2
    local geometry=$3
    local session=$4
    local localhost_mode=$5
    local resolved_display_no

    if ! id "$username" &>/dev/null; then
        print_warning "用户 $username 不存在，跳过 systemd VNC 配置"
        return 1
    fi

    if ! check_vnc_runtime_requirements "$session"; then
        print_error "用户 $username 的VNC运行环境检查失败，已跳过 systemd 启动"
        return 1
    fi

    print_info "正在检查显示号 :$display_no 的占用情况..."
    resolved_display_no=$(resolve_display_for_user "$username" "$display_no") || {
        return 1
    }

    if [ "$resolved_display_no" != "$display_no" ]; then
        print_info "用户 $username 将使用显示号 :$resolved_display_no（原请求 :$display_no）"
    fi

    set_vnc_display_mapping "$username" "$resolved_display_no"
    write_vnc_xstartup "$username" "$session"

    if enable_start_vnc_service "$username" "$resolved_display_no" "$geometry" "$localhost_mode"; then
        print_success "用户 $username 的 systemd VNC 配置完成，连接地址端口: $((5900 + resolved_display_no))"
        return 0
    fi

    return 1
}

# 批量处理模式
batch_mode() {
    echo ""
    echo "=========================================="
    echo "         批量用户创建和VNC配置"
    echo "=========================================="
    echo ""
    
    # 输入用户列表
    prompt_info "请输入用户名列表（用空格分隔）："
    read -r user_list
    
    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi
    
    # 输入统一密码
    prompt_info "请输入统一的用户密码："
    read -rs password
    echo ""
    
    if [ -z "$password" ]; then
        print_error "密码不能为空！"
        return
    fi
    
    # 选择shell
    shell=$(select_shell)
    
    # 询问是否添加用户备注
    echo ""
    prompt_info "是否为所有用户添加备注（如真实姓名）？(y/n) [默认: n]:"
    read -r add_comment_choice
    
    local comment=""
    if [[ "$add_comment_choice" =~ ^[Yy]$ ]]; then
        prompt_info "请输入用户备注（所有用户使用相同备注）："
        read -r comment
    fi
    
    # 询问是否配置VNC
    prompt_info "是否为用户配置VNC？(y/n) [默认: n]:"
    read -r setup_vnc_choice
    
    local vnc_password=""
    local use_systemd_vnc="n"
    local start_display_no="2"
    local vnc_geometry="1920x1080"
    local vnc_session="gnome"
    local vnc_localhost="no"

    if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
        prompt_info "请输入VNC密码（可以与用户密码相同或不同）："
        read -rs vnc_password
        echo ""
        
        if [ -z "$vnc_password" ]; then
            print_warning "VNC密码为空，将跳过VNC配置"
            setup_vnc_choice="n"
        else
            use_systemd_vnc=$(ask_systemd_vnc_mode)
            if [[ "$use_systemd_vnc" =~ ^[Yy]$ ]]; then
                start_display_no=$(ask_start_display "请输入起始显示号（第一个用户将使用该显示号）" "2")
                local desktop_conf
                desktop_conf=$(ask_vnc_desktop_config)
                vnc_geometry=$(echo "$desktop_conf" | cut -d'|' -f1)
                vnc_session=$(echo "$desktop_conf" | cut -d'|' -f2)
                vnc_localhost=$(echo "$desktop_conf" | cut -d'|' -f3)
            fi
        fi
    fi
    
    echo ""
    print_info "开始批量处理..."
    echo ""
    
    # 处理每个用户
    local created_users=()
    local current_display_no="$start_display_no"
    for username in $user_list; do
        create_user "$username" "$password" "$shell" "$comment"
        local result=$?
        
        if [ $result -eq 0 ] || [ $result -eq 2 ]; then
            created_users+=("$username")
            
            # 如果需要配置VNC
            if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
                setup_vnc "$username" "$vnc_password"

                if [[ "$use_systemd_vnc" =~ ^[Yy]$ ]]; then
                    setup_vnc_systemd "$username" "$current_display_no" "$vnc_geometry" "$vnc_session" "$vnc_localhost"
                    current_display_no=$((current_display_no + 1))
                fi
            fi
        fi
        echo ""
    done
    
    # 显示总结
    echo ""
    echo "=========================================="
    echo "              处理完成"
    echo "=========================================="
    echo ""
    
    if [ ${#created_users[@]} -gt 0 ]; then
        print_success "已处理的用户列表："
        for username in "${created_users[@]}"; do
            echo "  - $username"
        done
        echo ""
        echo "用户密码: $password"
        echo "默认Shell: $shell"
        if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
            echo "VNC密码: $vnc_password"
            if [[ "$use_systemd_vnc" =~ ^[Yy]$ ]]; then
                echo "VNC模式: systemd（自动启动）"
                echo "分辨率: $vnc_geometry"
                echo "会话: $vnc_session"
                echo "localhost: $vnc_localhost"
            else
                echo "VNC模式: 仅设置密码（需手动启动 vncserver）"
            fi
        fi
    else
        print_warning "没有创建或处理任何用户"
    fi
    echo ""
}

# 单用户模式
single_mode() {
    echo ""
    echo "=========================================="
    echo "         单用户创建和VNC配置"
    echo "=========================================="
    echo ""
    
    # 输入用户名
    prompt_info "请输入用户名："
    read -r username
    
    if [ -z "$username" ]; then
        print_error "用户名不能为空！"
        return
    fi
    
    # 输入密码
    prompt_info "请输入用户密码："
    read -rs password
    echo ""
    
    if [ -z "$password" ]; then
        print_error "密码不能为空！"
        return
    fi
    
    # 选择shell
    shell=$(select_shell)
    
    # 询问是否添加用户备注
    echo ""
    prompt_info "是否为用户添加备注（如真实姓名）？(y/n) [默认: n]:"
    read -r add_comment_choice
    
    local comment=""
    if [[ "$add_comment_choice" =~ ^[Yy]$ ]]; then
        prompt_info "请输入用户备注："
        read -r comment
    fi
    
    echo ""
    
    # 创建用户
    create_user "$username" "$password" "$shell" "$comment"
    local result=$?
    
    if [ $result -eq 0 ] || [ $result -eq 2 ]; then
        echo ""
        # 询问是否配置VNC
        prompt_info "是否为用户 $username 配置VNC？(y/n) [默认: n]:"
        read -r setup_vnc_choice
        
        if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
            prompt_info "请输入VNC密码："
            read -rs vnc_password
            echo ""
            
            if [ -z "$vnc_password" ]; then
                print_warning "VNC密码为空，跳过VNC配置"
            else
                echo ""
                setup_vnc "$username" "$vnc_password"

                local use_systemd_vnc
                use_systemd_vnc=$(ask_systemd_vnc_mode)
                if [[ "$use_systemd_vnc" =~ ^[Yy]$ ]]; then
                    local display_no
                    local desktop_conf
                    local vnc_geometry
                    local vnc_session
                    local vnc_localhost

                    display_no=$(ask_start_display "请输入用户 $username 的显示号" "2")
                    desktop_conf=$(ask_vnc_desktop_config)
                    vnc_geometry=$(echo "$desktop_conf" | cut -d'|' -f1)
                    vnc_session=$(echo "$desktop_conf" | cut -d'|' -f2)
                    vnc_localhost=$(echo "$desktop_conf" | cut -d'|' -f3)

                    echo ""
                    setup_vnc_systemd "$username" "$display_no" "$vnc_geometry" "$vnc_session" "$vnc_localhost"
                fi
            fi
        fi
    fi
    
    echo ""
    print_success "处理完成！"
    echo ""
}

# 仅VNC配置模式
vnc_only_mode() {
    echo ""
    echo "=========================================="
    echo "         VNC密码配置"
    echo "=========================================="
    echo ""
    
    prompt_info "请输入用户名列表（用空格分隔）："
    read -r user_list
    
    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi
    
    prompt_info "请输入VNC密码："
    read -rs vnc_password
    echo ""
    
    if [ -z "$vnc_password" ]; then
        print_error "VNC密码不能为空！"
        return
    fi

    local use_systemd_vnc
    local start_display_no="2"
    local vnc_geometry="1920x1080"
    local vnc_session="gnome"
    local vnc_localhost="no"

    use_systemd_vnc=$(ask_systemd_vnc_mode)
    if [[ "$use_systemd_vnc" =~ ^[Yy]$ ]]; then
        start_display_no=$(ask_start_display "请输入起始显示号（第一个用户将使用该显示号）" "2")
        local desktop_conf
        desktop_conf=$(ask_vnc_desktop_config)
        vnc_geometry=$(echo "$desktop_conf" | cut -d'|' -f1)
        vnc_session=$(echo "$desktop_conf" | cut -d'|' -f2)
        vnc_localhost=$(echo "$desktop_conf" | cut -d'|' -f3)
    fi
    
    echo ""
    print_info "开始配置VNC..."
    echo ""
    
    local current_display_no="$start_display_no"
    for username in $user_list; do
        setup_vnc "$username" "$vnc_password"

        if [[ "$use_systemd_vnc" =~ ^[Yy]$ ]]; then
            setup_vnc_systemd "$username" "$current_display_no" "$vnc_geometry" "$vnc_session" "$vnc_localhost"
            current_display_no=$((current_display_no + 1))
        fi

        echo ""
    done
    
    print_success "VNC配置完成！"
    echo ""
}

# 仅启用VNC开机自启模式（不修改现有VNC密码）
autostart_only_mode() {
    echo ""
    echo "=========================================="
    echo "   为现有用户启用VNC开机自启（CentOS7）"
    echo "=========================================="
    echo ""

    prompt_info "请输入用户名列表（用空格分隔）："
    read -r user_list

    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi

    local start_display_no
    local geometry
    local localhost_choice
    local localhost_mode="no"
    local overwrite_xstartup_choice
    local overwrite_xstartup="n"
    local session="gnome"

    start_display_no=$(ask_start_display "请输入起始显示号（第一个用户将使用该显示号）" "2")

    prompt_info "请输入VNC分辨率 [默认: 1920x1080]:"
    read -r geometry
    if [ -z "$geometry" ]; then
        geometry="1920x1080"
    fi

    prompt_info "是否仅允许本机访问（localhost）？(y/n) [默认: n]:"
    read -r localhost_choice
    if [[ "$localhost_choice" =~ ^[Yy]$ ]]; then
        localhost_mode="yes"
    fi

    prompt_info "是否覆盖现有 ~/.vnc/xstartup？(y/n) [默认: n]:"
    read -r overwrite_xstartup_choice
    if [[ "$overwrite_xstartup_choice" =~ ^[Yy]$ ]]; then
        overwrite_xstartup="y"
        prompt_info "请输入桌面会话（如 gnome）[默认: gnome]:"
        read -r session
        if [ -z "$session" ]; then
            session="gnome"
        fi
    fi

    echo ""
    print_info "开始启用VNC开机自启..."
    echo ""

    local current_display_no="$start_display_no"
    for username in $user_list; do
        if ! id "$username" &>/dev/null; then
            print_warning "用户 $username 不存在，跳过"
            echo ""
            continue
        fi

        if [ ! -f "/home/$username/.vnc/passwd" ]; then
            print_warning "用户 $username 尚未设置VNC密码（缺少 /home/$username/.vnc/passwd），请先执行 vncpasswd"
            echo ""
            continue
        fi

        local resolved_display_no
        resolved_display_no=$(resolve_display_for_user "$username" "$current_display_no") || {
            print_warning "已跳过用户 $username 的开机自启配置"
            echo ""
            current_display_no=$((current_display_no + 1))
            continue
        }

        if [ "$resolved_display_no" != "$current_display_no" ]; then
            print_info "用户 $username 将使用显示号 :$resolved_display_no（原请求 :$current_display_no）"
        fi

        set_vnc_display_mapping "$username" "$resolved_display_no"

        if [[ "$overwrite_xstartup" =~ ^[Yy]$ ]]; then
            write_vnc_xstartup "$username" "$session"
        else
            print_info "保留用户 $username 现有 ~/.vnc/xstartup"
        fi

        enable_start_vnc_service "$username" "$resolved_display_no" "$geometry" "$localhost_mode"
        current_display_no=$((resolved_display_no + 1))
        echo ""
    done

    print_success "VNC开机自启配置流程完成！"
    echo ""
}

# 删除用户模式（含VNC清理）
delete_mode() {
    echo ""
    echo "=========================================="
    echo "         删除用户和VNC清理"
    echo "=========================================="
    echo ""

    prompt_info "请输入要删除的用户名列表（用空格分隔）："
    read -r user_list

    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi

    echo ""
    print_warning "删除前检查清单："
    echo "  - 请确认用户没有未保存的重要远程会话"
    echo "  - 如需保留数据，请先备份 /home/用户名"
    echo "  - 请确认该用户不再需要VNC访问（:N / 5900+N）"
    echo "  - 端口范围规则（如 5900-5999/tcp）不会被本脚本删除"
    echo ""
    prompt_info "是否继续进入逐用户删除确认流程？(y/n) [默认: n]:"
    read -r pre_delete_confirm
    if ! [[ "$pre_delete_confirm" =~ ^[Yy]$ ]]; then
        print_warning "已取消删除流程"
        return
    fi

    echo ""
    print_info "开始删除用户并清理VNC..."
    echo ""

    for username in $user_list; do
        delete_user_with_vnc_cleanup "$username"
        echo ""
    done

    print_success "删除流程完成！"
    echo ""
}

# 显示主菜单
show_menu() {
    clear
    echo "=========================================="
    echo "      用户和VNC管理交互式脚本"
    echo "=========================================="
    echo ""
    echo "请选择操作模式："
    echo ""
    echo "  1) 批量创建用户和配置VNC"
    echo "  2) 创建单个用户和配置VNC"
    echo "  3) 仅为现有用户配置VNC"
    echo "  4) 仅为现有用户启用VNC开机自启"
    echo "  5) 删除用户（含VNC清理）"
    echo "  6) 退出"
    echo ""
    echo "=========================================="
}

# 主函数
main() {
    while true; do
        show_menu
        prompt_info "请输入选项 (1-6):"
        read -r choice
        
        case $choice in
            1)
                batch_mode
                ;;
            2)
                single_mode
                ;;
            3)
                vnc_only_mode
                ;;
            4)
                autostart_only_mode
                ;;
            5)
                delete_mode
                ;;
            6)
                print_info "退出脚本，再见！"
                exit 0
                ;;
            *)
                print_error "无效的选项，请重新选择！"
                sleep 2
                ;;
        esac
        
        # 询问是否继续
        echo ""
        prompt_info "按Enter键返回主菜单，或输入q退出..."
        read -r continue_choice
        if [[ "$continue_choice" =~ ^[Qq]$ ]]; then
            print_info "退出脚本，再见！"
            exit 0
        fi
    done
}

# 运行主函数
check_root
main
