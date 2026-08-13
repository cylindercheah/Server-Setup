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

# VNC状态缓存关联数组 (需 Bash 4.0+)
declare -A VNC_MAPPING_CACHE=()
declare -A VNC_LEGACY_CACHE=()
declare -A VNC_PROCESS_CACHE=()
# 用户显示号聚合缓存 (user -> "d1 d2 ...")
declare -A VNC_USER_DISPLAYS_CACHE=()

VNC_MAPPING_READY=0
VNC_LEGACY_READY=0
VNC_PROCESS_READY=0
FIREWALL_ZONE_SNAPSHOT=""
FIREWALL_ZONE_READY=0

# 重置缓存函数
invalidate_vnc_state_cache() {
    VNC_MAPPING_CACHE=()
    VNC_LEGACY_CACHE=()
    VNC_PROCESS_CACHE=()
    VNC_USER_DISPLAYS_CACHE=()
    VNC_MAPPING_READY=0
    VNC_LEGACY_READY=0
    VNC_PROCESS_READY=0
    FIREWALL_ZONE_SNAPSHOT=""
    FIREWALL_ZONE_READY=0
}

build_vnc_mapping_snapshot() {
    local map_file="/etc/tigervnc/vncserver.users"
    if [ "$VNC_MAPPING_READY" -eq 1 ]; then return 0; fi

    if [ -f "$map_file" ]; then
        # 一次性解析映射文件到关联数组
        while read -r line; do
            [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]] && continue
            if [[ "$line" =~ ^:([0-9]+)=(.*) ]]; then
                local d="${BASH_REMATCH[1]}"
                local u="${BASH_REMATCH[2]}"
                VNC_MAPPING_CACHE["$d"]="$u"
                VNC_USER_DISPLAYS_CACHE["$u"]="${VNC_USER_DISPLAYS_CACHE["$u"]} $d"
            fi
        done < "$map_file"
    fi
    VNC_MAPPING_READY=1
}

build_vnc_legacy_snapshot() {
    if [ "$VNC_LEGACY_READY" -eq 1 ]; then return 0; fi

    local unit_file
    local base
    local d
    local u

    # 同时兼容：
    # 1) 旧自定义单元中的 User=username
    # 2) 新版RHEL7 wrapper单元中的 ExecStart=/usr/bin/vncserver_wrapper username :N
    for unit_file in /etc/systemd/system/vncserver@:*.service; do
        [ -f "$unit_file" ] || continue

        base=$(basename "$unit_file")
        if [[ ! "$base" =~ ^vncserver@:([0-9]+)\.service$ ]]; then
            continue
        fi
        d="${BASH_REMATCH[1]}"

        u=$(awk -F'=' '/^User=/{print $2; exit}' "$unit_file" 2>/dev/null)
        if [ -z "$u" ]; then
            u=$(awk '
                /^ExecStart=.*vncserver_wrapper[[:space:]]+/ {
                    for (i=1; i<=NF; i++) {
                        if ($i ~ /vncserver_wrapper$/ && (i+1) <= NF) {
                            print $(i+1)
                            exit
                        }
                    }
                }
            ' "$unit_file" 2>/dev/null)
        fi

        if [ -n "$u" ]; then
            VNC_LEGACY_CACHE["$d"]="$u"
            VNC_USER_DISPLAYS_CACHE["$u"]="${VNC_USER_DISPLAYS_CACHE["$u"]} $d"
        fi
    done

    VNC_LEGACY_READY=1
}

# 仅从 /etc/systemd/system/vncserver@:N.service 单元获取指定用户的显示号
# 用于深度清理，兼容旧 User= 单元和新的 vncserver_wrapper 单元。
get_user_vnc_displays_from_legacy_units() {
    local username=$1
    local d

    build_vnc_legacy_snapshot
    for d in "${!VNC_LEGACY_CACHE[@]}"; do
        if [ "${VNC_LEGACY_CACHE[$d]}" = "$username" ]; then
            echo "$d"
        fi
    done | sort -n
}

build_vnc_process_snapshot() {
    if [ "$VNC_PROCESS_READY" -eq 1 ]; then return 0; fi

    # ps 一次性拉取所有 Xvnc 进程
    while read -r u d; do
        if [[ -n "$u" && -n "$d" ]]; then
            VNC_PROCESS_CACHE["$d"]="$u"
            VNC_USER_DISPLAYS_CACHE["$u"]="${VNC_USER_DISPLAYS_CACHE["$u"]} $d"
        fi
    done < <(ps -eo user,args | awk 'match($0, /\/usr\/bin\/(Xvnc|Xtigervnc)[[:space:]]*:([0-9]+)/, m) { print $1 " " m[2] }')

    VNC_PROCESS_READY=1
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
        gnome|gnome-session|gnome-classic|gnome-classic-session)
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

# 写入RHEL/CentOS 7 vncserver_wrapper所使用的用户级VNC选项
# geometry 使用 ~/.vnc/config；localhost=yes 时写入裸 "localhost" 选项。
# localhost=no 时移除该选项，让TigerVNC保持远程可连接行为。
configure_vnc_user_options() {
    local username=$1
    local geometry=$2
    local localhost_mode=$3
    local home_dir="/home/$username"
    local vnc_dir="$home_dir/.vnc"
    local config_file="$vnc_dir/config"
    local tmp_file

    if ! id "$username" >/dev/null 2>&1; then
        print_error "用户 $username 不存在，无法写入VNC用户配置"
        return 1
    fi

    if ! [[ "$geometry" =~ ^[0-9]+x[0-9]+$ ]]; then
        print_warning "VNC分辨率 '$geometry' 格式无效，改用 1920x1080"
        geometry="1920x1080"
    fi

    mkdir -p "$vnc_dir" || return 1
    touch "$config_file" || return 1
    tmp_file=$(mktemp) || return 1

    # 仅替换脚本负责的 geometry / localhost，保留用户其他自定义VNC选项。
    awk '
        /^[[:space:]]*geometry[[:space:]]*=/ { next }
        /^[[:space:]]*localhost([[:space:]]*=.*)?[[:space:]]*$/ { next }
        { print }
    ' "$config_file" > "$tmp_file"

    printf 'geometry=%s\n' "$geometry" >> "$tmp_file"
    if [ "$localhost_mode" = "yes" ]; then
        printf 'localhost\n' >> "$tmp_file"
    fi

    cp "$tmp_file" "$config_file"
    rm -f "$tmp_file"

    chown "$username:$username" "$vnc_dir" "$config_file"
    chmod 700 "$vnc_dir"
    chmod 600 "$config_file"

    if command -v restorecon >/dev/null 2>&1; then
        restorecon -R "$vnc_dir" >/dev/null 2>&1 || true
    fi

    if [ "$localhost_mode" = "yes" ]; then
        print_success "已写入VNC用户配置: geometry=$geometry, localhost=启用"
    else
        print_success "已写入VNC用户配置: geometry=$geometry, localhost=关闭"
    fi
    return 0
}

# 为指定显示号创建RHEL/CentOS 7兼容的TigerVNC wrapper单元文件
# 关键点：不再使用 User=username + 直接 ExecStart=vncserver。
# systemd保持跟踪长期运行的 vncserver_wrapper；wrapper内部通过 runuser -l
# 启动VNC，使GNOME获得有效的XDG_SESSION_ID/logind会话，从而可正常锁屏/解锁。
ensure_legacy_vnc_unit_file() {
    local username=$1
    local display_no=$2
    local geometry=$3
    local localhost_mode=$4
    local unit_file="/etc/systemd/system/vncserver@:${display_no}.service"
    local pam_test_dropin="/etc/systemd/system/vncserver@:${display_no}.service.d/pam-session.conf"

    # 清理由旧调试流程可能遗留的 PAMName= drop-in；wrapper模式不需要它，
    # 且在CentOS 7 systemd 219上会导致fork后的Xvnc PID被移出service cgroup。
    if [ -f "$pam_test_dropin" ] && grep -q '^[[:space:]]*PAMName=' "$pam_test_dropin" 2>/dev/null; then
        rm -f "$pam_test_dropin"
        rmdir "$(dirname "$pam_test_dropin")" >/dev/null 2>&1 || true
        print_warning "已移除显示号 :$display_no 的旧PAMName测试drop-in"
    fi

    if [ ! -x /usr/bin/vncserver_wrapper ]; then
        print_error "未找到可执行的 /usr/bin/vncserver_wrapper"
        print_error "请确认已安装CentOS/RHEL 7 tigervnc-server软件包"
        return 1
    fi

    if ! configure_vnc_user_options "$username" "$geometry" "$localhost_mode"; then
        print_error "用户 $username 的 ~/.vnc/config 写入失败"
        return 1
    fi

    cat > "$unit_file" <<EOF
[Unit]
Description=Remote desktop service (TigerVNC wrapper) for ${username} on :${display_no}
After=syslog.target network.target

[Service]
Type=simple
ExecStartPre=-/usr/bin/bash -c '/usr/bin/rm -f /tmp/.X${display_no}-lock /tmp/.X11-unix/X${display_no} /home/${username}/.vnc/*:${display_no}.pid >/dev/null 2>&1 || true'
ExecStartPre=/bin/sh -c '/usr/bin/vncserver -kill :${display_no} > /dev/null 2>&1 || :'
ExecStart=/usr/bin/vncserver_wrapper ${username} :${display_no}
ExecStop=/bin/sh -c '/usr/bin/vncserver -kill :${display_no} > /dev/null 2>&1 || :'

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$unit_file"
    print_success "已生成RHEL7 wrapper VNC服务单元: $unit_file"
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
    local is_admin=$5
    local cdsinit_file
    local bashrc_file
    local env_source_line='source /eda/enviroment/envic618.bash'
    
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

    # 在用户 .bashrc 中追加环境加载行
    bashrc_file="/home/$username/.bashrc"
    if [ ! -f "$bashrc_file" ]; then
        if ! touch "$bashrc_file"; then
            print_error "为用户 $username 创建 .bashrc 文件失败"
            return 1
        fi
    fi

    if ! grep -Fqx "$env_source_line" "$bashrc_file" 2>/dev/null; then
        if ! echo "$env_source_line" >> "$bashrc_file"; then
            print_error "为用户 $username 写入 .bashrc 环境配置失败"
            return 1
        fi
    fi

    if ! chown "$username:$username" "$bashrc_file" || ! chmod 644 "$bashrc_file"; then
        print_error "设置用户 $username 的 .bashrc 权限失败"
        return 1
    fi

    # 创建 .cdsinit 文件并写入 ICV QuerySKL 加载配置
    cdsinit_file="/home/$username/.cdsinit"
    if ! cat > "$cdsinit_file" <<'EOF'
load(strcat(getShellEnvVar("MGC_HOME")
"/shared/pkgs/icv/tools/queryskl/calibre.skl"))
EOF
    then
        print_error "为用户 $username 创建 .cdsinit 文件失败"
        return 1
    fi

    if ! chown "$username:$username" "$cdsinit_file" || ! chmod 644 "$cdsinit_file"; then
        print_error "设置用户 $username 的 .cdsinit 权限失败"
        return 1
    fi

    # 可选：授予管理员权限（优先使用 wheel 组，兼容部分发行版的 sudo 组）
    if [[ "$is_admin" =~ ^[Yy]$ ]]; then
        if getent group wheel >/dev/null 2>&1; then
            if usermod -aG wheel "$username" 2>&1; then
                print_success "已将用户 $username 加入 wheel 管理员组"
            else
                print_warning "将用户 $username 加入 wheel 组失败，请手动检查"
            fi
        elif getent group sudo >/dev/null 2>&1; then
            if usermod -aG sudo "$username" 2>&1; then
                print_success "已将用户 $username 加入 sudo 管理员组"
            else
                print_warning "将用户 $username 加入 sudo 组失败，请手动检查"
            fi
        else
            print_warning "未检测到 wheel/sudo 组，无法自动授予管理员权限"
        fi
    fi
    
    if [[ "$is_admin" =~ ^[Yy]$ ]]; then
        print_success "已创建用户 $username, shell: $shell, 密码: $password, 管理员: 是"
    else
        print_success "已创建用户 $username, shell: $shell, 密码: $password, 管理员: 否"
    fi
    return 0
}

# 设置VNC密码函数
setup_vnc() {
    local username=$1
    local vnc_password=$2
    local vnc_dir="/home/$username/.vnc"
    local passwd_file="$vnc_dir/passwd"
    local passwd_size
    
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
    if [ ! -d "$vnc_dir" ]; then
        mkdir -p "$vnc_dir"
        chown "$username:$username" "$vnc_dir"
        chmod 700 "$vnc_dir"
        print_info "已创建 $vnc_dir 目录"
    fi
    
    # 设置VNC密码
    print_info "正在为 $username 设置VNC密码..."
    if ! printf '%s\n' "$vnc_password" | run_as_user "$username" bash -lc 'umask 077; mkdir -p "$HOME/.vnc"; vncpasswd -f > "$HOME/.vnc/passwd"'; then
        print_error "为用户 $username 生成VNC密码文件失败"
        return 1
    fi

    if [ ! -f "$passwd_file" ]; then
        print_error "未找到 $passwd_file，VNC密码设置失败"
        return 1
    fi

    passwd_size=$(wc -c < "$passwd_file" 2>/dev/null)
    if [ -z "$passwd_size" ] || [ "$passwd_size" -lt 8 ]; then
        print_error "检测到异常的VNC密码文件（大小: ${passwd_size:-0}字节）"
        return 1
    fi
    
    # 设置权限
    chown "$username:$username" "$passwd_file"
    chmod 600 "$passwd_file"

    # SELinux 开启时，修正上下文可避免 Xvnc 读取 passwd 被拒绝
    if command -v restorecon >/dev/null 2>&1; then
        restorecon -R "$vnc_dir" >/dev/null 2>&1 || true
    fi
    
    print_success "用户 $username 的VNC密码已设置为: $vnc_password"
    return 0
}

# 恢复VNC用户的GNOME正常锁屏行为
# 说明：旧版本脚本曾为绕过GNOME reauthentication错误而禁用锁屏。
# 现在VNC服务使用官方 vncserver_wrapper，可获得有效logind/XDG_SESSION_ID，
# 因此菜单1/2/4会自动恢复GNOME默认锁屏设置，使锁屏/解锁认证正常工作。
restore_vnc_gnome_lock_defaults() {
    local username=$1
    local home_dir="/home/$username"
    local dbus_runner=""
    local lock_enabled=""
    local disable_lock_screen=""
    local idle_delay=""
    local idle_activation=""
    local failed=0

    if [ -z "$username" ] || ! id "$username" >/dev/null 2>&1; then
        print_warning "无法恢复VNC锁屏设置：用户 '$username' 不存在"
        return 1
    fi

    if ! command -v gsettings >/dev/null 2>&1; then
        print_warning "未找到 gsettings，无法自动恢复用户 $username 的GNOME锁屏设置"
        return 1
    fi

    if command -v dbus-run-session >/dev/null 2>&1; then
        dbus_runner="dbus-run-session"
    elif command -v dbus-launch >/dev/null 2>&1; then
        dbus_runner="dbus-launch"
    else
        print_warning "未找到 dbus-run-session/dbus-launch，无法可靠恢复GNOME锁屏设置"
        return 1
    fi

    print_info "正在为VNC用户 $username 恢复GNOME正常锁屏/解锁设置..."

    if [ "$dbus_runner" = "dbus-run-session" ]; then
        # 重置旧版脚本曾修改的四个键，恢复系统/Schema默认值。
        run_as_user "$username" env HOME="$home_dir" dbus-run-session -- \
            gsettings reset org.gnome.desktop.session idle-delay >/dev/null 2>&1 || failed=1
        run_as_user "$username" env HOME="$home_dir" dbus-run-session -- \
            gsettings reset org.gnome.desktop.screensaver lock-enabled >/dev/null 2>&1 || failed=1
        run_as_user "$username" env HOME="$home_dir" dbus-run-session -- \
            gsettings reset org.gnome.desktop.screensaver idle-activation-enabled >/dev/null 2>&1 || true
        run_as_user "$username" env HOME="$home_dir" dbus-run-session -- \
            gsettings reset org.gnome.desktop.lockdown disable-lock-screen >/dev/null 2>&1 || true

        lock_enabled=$(run_as_user "$username" env HOME="$home_dir" dbus-run-session -- \
            gsettings get org.gnome.desktop.screensaver lock-enabled 2>/dev/null || true)
        disable_lock_screen=$(run_as_user "$username" env HOME="$home_dir" dbus-run-session -- \
            gsettings get org.gnome.desktop.lockdown disable-lock-screen 2>/dev/null || true)
        idle_delay=$(run_as_user "$username" env HOME="$home_dir" dbus-run-session -- \
            gsettings get org.gnome.desktop.session idle-delay 2>/dev/null || true)
        idle_activation=$(run_as_user "$username" env HOME="$home_dir" dbus-run-session -- \
            gsettings get org.gnome.desktop.screensaver idle-activation-enabled 2>/dev/null || true)
    else
        run_as_user "$username" env HOME="$home_dir" bash -lc \
            'eval "$(dbus-launch --sh-syntax)"; gsettings reset org.gnome.desktop.session idle-delay' \
            >/dev/null 2>&1 || failed=1
        run_as_user "$username" env HOME="$home_dir" bash -lc \
            'eval "$(dbus-launch --sh-syntax)"; gsettings reset org.gnome.desktop.screensaver lock-enabled' \
            >/dev/null 2>&1 || failed=1
        run_as_user "$username" env HOME="$home_dir" bash -lc \
            'eval "$(dbus-launch --sh-syntax)"; gsettings reset org.gnome.desktop.screensaver idle-activation-enabled' \
            >/dev/null 2>&1 || true
        run_as_user "$username" env HOME="$home_dir" bash -lc \
            'eval "$(dbus-launch --sh-syntax)"; gsettings reset org.gnome.desktop.lockdown disable-lock-screen' \
            >/dev/null 2>&1 || true

        lock_enabled=$(run_as_user "$username" env HOME="$home_dir" bash -lc \
            'eval "$(dbus-launch --sh-syntax)"; gsettings get org.gnome.desktop.screensaver lock-enabled' \
            2>/dev/null || true)
        disable_lock_screen=$(run_as_user "$username" env HOME="$home_dir" bash -lc \
            'eval "$(dbus-launch --sh-syntax)"; gsettings get org.gnome.desktop.lockdown disable-lock-screen' \
            2>/dev/null || true)
        idle_delay=$(run_as_user "$username" env HOME="$home_dir" bash -lc \
            'eval "$(dbus-launch --sh-syntax)"; gsettings get org.gnome.desktop.session idle-delay' \
            2>/dev/null || true)
        idle_activation=$(run_as_user "$username" env HOME="$home_dir" bash -lc \
            'eval "$(dbus-launch --sh-syntax)"; gsettings get org.gnome.desktop.screensaver idle-activation-enabled' \
            2>/dev/null || true)
    fi

    if [ "$lock_enabled" = "true" ] && [ "$disable_lock_screen" = "false" ]; then
        print_success "用户 $username 已恢复正常GNOME锁屏（lock-enabled=true, disable-lock-screen=false, idle-delay=${idle_delay:-未知}, idle-activation=${idle_activation:-未知}）"
        return 0
    fi

    if [ "$failed" -eq 1 ]; then
        print_warning "用户 $username 的部分GNOME锁屏设置恢复失败，请检查gsettings/dconf环境"
    else
        print_warning "用户 $username 的GNOME锁屏设置未完全验证（lock-enabled=${lock_enabled:-未知}, disable-lock-screen=${disable_lock_screen:-未知}）"
    fi

    # 锁屏设置恢复失败不应阻断VNC服务本身配置。
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
    local default_session="gnome-classic"
    local geometry
    local session
    local localhost_choice
    local localhost_value="no"

    prompt_info "请输入VNC分辨率 [默认: $default_geometry]:"
    read -r geometry
    if [ -z "$geometry" ]; then
        geometry="$default_geometry"
    fi

    prompt_info "请输入桌面会话（如 gnome-classic）[默认: $default_session]:"
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
            # 只移除该显示号的旧映射（无论是兑人）
            if ($0 ~ ("^" display "=")) {
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
    invalidate_vnc_state_cache

    print_success "已设置VNC显示映射: :$display_no=$username"
}

# 生成 CentOS 7 兼容的 ~/.vnc/xstartup
write_vnc_xstartup() {
    local username=$1
    local session=$2
    local home_dir="/home/$username"
    local vnc_dir="$home_dir/.vnc"
    local startup_file="$vnc_dir/xstartup"

    mkdir -p "$vnc_dir"
    cat > "$startup_file" <<EOF
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

if command -v gnome-classic >/dev/null 2>&1; then
    exec gnome-classic
fi

if [ -x /etc/X11/xinit/xinitrc ]; then
    exec /etc/X11/xinit/xinitrc
fi

if command -v xterm >/dev/null 2>&1; then
    exec xterm
fi

if [ -e /usr/bin/gnome-session ]; then
    vncserver -kill
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

    # O(1) 关联数组查找，取代 awk 子进程
    build_vnc_process_snapshot
    owner="${VNC_PROCESS_CACHE[$display_no]}"
    if [ -n "$owner" ]; then echo "$owner"; return 0; fi

    build_vnc_mapping_snapshot
    owner="${VNC_MAPPING_CACHE[$display_no]}"
    if [ -n "$owner" ]; then echo "$owner"; return 0; fi

    build_vnc_legacy_snapshot
    owner="${VNC_LEGACY_CACHE[$display_no]}"
    if [ -n "$owner" ]; then echo "$owner"; fi
}

# 强制回收显示号（停止旧会话并清理锁文件）
force_reclaim_display() {
    local display_no=$1

    # 优先尝试通过vncserver wrapper终止，失败时回退到pkill
    vncserver -kill ":$display_no" >/dev/null 2>&1 || true
    pkill -f "^/usr/bin/Xvnc :${display_no} " >/dev/null 2>&1 || true

    rm -f "/tmp/.X${display_no}-lock" "/tmp/.X11-unix/X${display_no}"
}

# 获取映射文件中指定显示号的用户 (弃用，保留供参考)
get_mapped_display_owner() {
    build_vnc_mapping_snapshot
    echo "${VNC_MAPPING_CACHE[$1]}"
}

# 获取旧版自定义单元中指定显示号的用户 (弃用，保留供参考)
get_legacy_unit_display_owner() {
    build_vnc_legacy_snapshot
    echo "${VNC_LEGACY_CACHE[$1]}"
}

# 获取用户在 /etc/tigervnc/vncserver.users 或旧版自定义VNC单元中的显示号列表（不带冒号）
get_user_vnc_displays() {
    local username=$1
    
    build_vnc_mapping_snapshot
    build_vnc_legacy_snapshot
    build_vnc_process_snapshot

    # 从聚合缓存获取并去重排序，极大地减少循环中的分支调用
    local raw_displays="${VNC_USER_DISPLAYS_CACHE["$username"]}"
    [ -z "$raw_displays" ] && return 0
    
    echo "$raw_displays" | tr ' ' '\n' | awk 'NF && !seen[$0]++' | sort -n
}

# 打印用户当前VNC连接信息（显示号与端口）
print_user_vnc_connection_hint() {
    local username=$1
    local displays

    displays=$(get_user_vnc_displays "$username")
    if [ -z "$displays" ]; then
        print_warning "未找到用户 $username 的VNC显示映射"
        return 1
    fi

    print_info "用户 $username 当前VNC连接信息："
    for d in $displays; do
        echo "  - 显示号 :$d, 端口: $((5900 + d))"
    done

    return 0
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
    invalidate_vnc_state_cache
}

# 删除用户在 /etc/tigervnc/vncserver.users 的指定显示号映射
remove_user_vnc_mapping_by_display() {
    local username=$1
    local display_no=$2
    local map_file="/etc/tigervnc/vncserver.users"
    local tmp_file

    if [ ! -f "$map_file" ]; then
        return 0
    fi

    tmp_file=$(mktemp)
    awk -F'=' -v user="$username" -v display=":${display_no}" '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
        $1 == display && $2 == user { next }
        { print }
    ' "$map_file" > "$tmp_file"

    cp "$tmp_file" "$map_file"
    rm -f "$tmp_file"
    chmod 644 "$map_file"
    invalidate_vnc_state_cache
}

# 获取活动防火墙zone（默认取第一个活动zone；取不到则回退public）
get_active_firewalld_zone() {
    local zone

    if ! has_firewall_cmd; then
        return 1
    fi

    if [ "$FIREWALL_ZONE_READY" -eq 1 ]; then
        echo "$FIREWALL_ZONE_SNAPSHOT"
        return 0
    fi

    zone=$(firewall-cmd --get-active-zones 2>/dev/null | awk 'NF{print $1; exit}')
    if [ -z "$zone" ]; then
        zone="public"
    fi
    FIREWALL_ZONE_SNAPSHOT="$zone"
    FIREWALL_ZONE_READY=1
    echo "$zone"
}

# 清理用户的VNC资源（映射、service、进程、端口）
cleanup_vnc_for_user() {
    local username=$1
    local cleanup_level=${2:-standard}
    local target_displays_input=$3
    local displays
    local cleanup_displays=""
    local zone
    local firewall_changed=0
    local manage_firewall=0
    local unit_file_removed=0
    local cleaned_any=0
    local vnc_home_dir="/home/$username/.vnc"
    local normalized_displays
    local d

    displays=$(get_user_vnc_displays "$username")

    if [ -n "$target_displays_input" ]; then
        normalized_displays=$(echo "$target_displays_input" | tr ',' ' ')
        for d in $normalized_displays; do
            if ! [[ "$d" =~ ^[0-9]+$ ]]; then
                print_warning "显示号 '$d' 无效，已跳过"
                continue
            fi

            if [[ " $cleanup_displays " == *" $d "* ]]; then
                continue
            fi

            cleanup_displays="$cleanup_displays $d"
        done

        if [ -z "$cleanup_displays" ]; then
            print_error "未提供有效显示号"
            return 1
        fi
    else
        cleanup_displays="$displays"
    fi

    if [ -z "$cleanup_displays" ]; then
        print_warning "未发现用户 $username 的VNC显示号，将继续执行深度清理"
    fi

    if has_firewall_cmd; then
        zone=$(get_active_firewalld_zone)
        if [ -n "$zone" ]; then
            manage_firewall=1
        fi
    else
        print_warning "未检测到 firewall-cmd，跳过防火墙端口清理"
    fi

    for d in $cleanup_displays; do
        local unit_name="vncserver@:${d}.service"
        local port=$((5900 + d))

        systemctl stop "$unit_name" >/dev/null 2>&1 || true
        systemctl disable "$unit_name" >/dev/null 2>&1 || true
        remove_legacy_vnc_unit_file "$d"
        unit_file_removed=1
        force_reclaim_display "$d"
        cleaned_any=1
        print_success "已停止并禁用 $unit_name"

        if [ "$manage_firewall" -eq 1 ] && firewall-cmd --zone="$zone" --query-port="${port}/tcp" >/dev/null 2>&1; then
            firewall-cmd --permanent --zone="$zone" --remove-port="${port}/tcp" >/dev/null 2>&1 || true
            firewall_changed=1
            print_success "已从防火墙zone($zone)移除端口 ${port}/tcp"
        fi
    done

    # 补充清理：仅在“清理全部显示号”时，移除任何残留的用户级VNC systemd实例
    if [ -z "$target_displays_input" ]; then
        local legacy_displays
        legacy_displays=$(get_user_vnc_displays_from_legacy_units "$username")
        for d in $legacy_displays; do
            local unit_name="vncserver@:${d}.service"
            local port=$((5900 + d))

            systemctl stop "$unit_name" >/dev/null 2>&1 || true
            systemctl disable "$unit_name" >/dev/null 2>&1 || true
            remove_legacy_vnc_unit_file "$d"
            force_reclaim_display "$d"
            unit_file_removed=1
            cleaned_any=1

            if [ "$manage_firewall" -eq 1 ] && firewall-cmd --zone="$zone" --query-port="${port}/tcp" >/dev/null 2>&1; then
                firewall-cmd --permanent --zone="$zone" --remove-port="${port}/tcp" >/dev/null 2>&1 || true
                firewall_changed=1
            fi
        done
    fi

    # 深度清理：终止残留VNC相关进程
    if [ -n "$target_displays_input" ]; then
        for d in $cleanup_displays; do
            pkill -u "$username" -f "Xvnc :${d}|Xtigervnc :${d}|vncserver :${d}" >/dev/null 2>&1 || true
        done
    else
        pkill -u "$username" -f 'Xvnc|Xtigervnc|vncserver' >/dev/null 2>&1 || true
    fi

    # 深度清理：移除用户目录中的VNC运行时文件
    if [ -d "$vnc_home_dir" ]; then
        if [ -n "$target_displays_input" ]; then
            for d in $cleanup_displays; do
                rm -f "$vnc_home_dir"/*:"${d}".pid >/dev/null 2>&1 || true
                rm -f "$vnc_home_dir"/*:"${d}".log >/dev/null 2>&1 || true
            done
        else
            rm -f "$vnc_home_dir"/*.pid "$vnc_home_dir"/*:*.pid >/dev/null 2>&1 || true
            rm -f "$vnc_home_dir"/*.log "$vnc_home_dir"/*:*.log >/dev/null 2>&1 || true
        fi
        rm -f "$vnc_home_dir"/*.sock "$vnc_home_dir"/*.tmp >/dev/null 2>&1 || true
        cleaned_any=1

        if [ "$cleanup_level" = "full" ] && [ -z "$target_displays_input" ]; then
            rm -rf "$vnc_home_dir"
            print_success "已删除用户 $username 的VNC配置目录: $vnc_home_dir"
        elif [ "$cleanup_level" = "full" ] && [ -n "$target_displays_input" ]; then
            print_info "已执行指定显示号的深度清理（保留 ~/.vnc 目录与其他显示号配置）"
        fi
    fi

    if [ -n "$target_displays_input" ]; then
        for d in $cleanup_displays; do
            remove_user_vnc_mapping_by_display "$username" "$d"
            print_success "已清理用户 $username 的VNC显示号映射: :$d"
        done
    else
        remove_user_vnc_mappings "$username"
        print_success "已清理用户 $username 的VNC显示号映射"
    fi

    if [ "$unit_file_removed" -eq 1 ]; then
        systemctl daemon-reload >/dev/null 2>&1 || true
    fi

    if [ "$manage_firewall" -eq 1 ] && [ "$firewall_changed" -eq 1 ]; then
        firewall-cmd --reload >/dev/null 2>&1 || true
        print_success "防火墙规则已重载"
    fi

    if [ "$cleaned_any" -eq 0 ]; then
        print_warning "用户 $username 未检测到可清理的VNC运行资源（已完成映射与残留检查）"
    fi

    invalidate_vnc_state_cache

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

    cleanup_vnc_for_user "$username" "full"
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

# 从指定显示号开始查找下一个空闲显示号（可选忽略指定用户的现有显示号）
find_next_free_display() {
    local start_display=$1
    local exclude_user=$2
    local probe_display="$start_display"
    local user_displays=""
    local d

    # 如果指定了要忽略的用户，获取其现有显示号
    if [ -n "$exclude_user" ]; then
        user_displays=$(get_user_vnc_displays "$exclude_user")
    fi

    while [ "$probe_display" -lt 100 ]; do
        local owner
        owner=$(get_display_owner "$probe_display")
        
        # 跳过有所有者的显示号
        if [ -n "$owner" ]; then
            probe_display=$((probe_display + 1))
            continue
        fi

        # 如果指定了用户，也跳过该用户自己的现有显示号
        if [ -n "$exclude_user" ] && [ -n "$user_displays" ]; then
            local skip=0
            for d in $user_displays; do
                if [ "$d" = "$probe_display" ]; then
                    skip=1
                    break
                fi
            done
            if [ "$skip" -eq 1 ]; then
                probe_display=$((probe_display + 1))
                continue
            fi
        fi

        echo "$probe_display"
        return 0
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
        prompt_warning "显示号 :$requested_display 当前已由用户 $username 占用"
        prompt_info "请选择处理方式："
        echo "  1) 强制回收 :$requested_display 并重新启动会话" >&2
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
                next_display=$(find_next_free_display $((requested_display + 1)) "$username") || {
                    print_error "未找到可用的空闲显示号（2-99）" >&2
                    return 1
                }
                echo "$next_display"
                return 0
                ;;
            *)
                prompt_warning "已取消为用户 $username 配置VNC"
                return 1
                ;;
        esac
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
            next_display=$(find_next_free_display $((requested_display + 1)) "$username") || {
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

# 验证wrapper启动的Xvnc是否继承有效的logind会话ID。
# 这是修复GNOME锁屏反复“下一步/Authentication Error”的关键状态。
verify_vnc_logind_session() {
    local username=$1
    local display_no=$2
    local pid=""
    local sid=""
    local attempt

    for attempt in 1 2 3; do
        pid=$(ps -eo pid=,user=,args= | awk -v u="$username" -v d=":${display_no}" '
            $2 == u && ($3 == "/usr/bin/Xvnc" || $3 == "/usr/bin/Xtigervnc") && $4 == d {
                print $1
                exit
            }
        ')

        if [ -n "$pid" ] && [ -r "/proc/$pid/environ" ]; then
            sid=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^XDG_SESSION_ID=//p' | head -n 1)
            if [ -n "$sid" ]; then
                print_success "VNC :$display_no 已获得logind会话 XDG_SESSION_ID=$sid（用户: $username）"
                return 0
            fi
        fi
        sleep 1
    done

    print_warning "VNC :$display_no 已启动，但暂未检测到XDG_SESSION_ID；如锁屏认证异常，请检查journalctl中的 'No session available'"
    return 1
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
        print_error "未找到VNC单元: $unit_file"
        return 1
    fi

    # 新架构必须使用RHEL/CentOS 7官方wrapper模式，确保GNOME获得有效logind会话。
    if ! grep -qE '^ExecStart=/usr/bin/vncserver_wrapper[[:space:]]+' "$unit_file"; then
        print_error "VNC单元未使用 vncserver_wrapper，拒绝启动: $unit_file"
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

    # Type=simple 的wrapper会先返回systemctl启动成功，再等待Xvnc PID出现；
    # 因此这里主动等待Xvnc真正启动，避免wrapper几秒后失败但脚本误报成功。
    local ready=0
    local attempt
    for attempt in 1 2 3 4 5 6; do
        if ! systemctl is-active --quiet "$unit_name"; then
            break
        fi

        if ps -eo user=,args= | awk -v u="$username" -v d=":${display_no}" '
            $1 == u && ($2 == "/usr/bin/Xvnc" || $2 == "/usr/bin/Xtigervnc") && $3 == d { found=1; exit }
            END { exit(found ? 0 : 1) }
        '; then
            ready=1
            break
        fi
        sleep 1
    done

    if [ "$ready" -ne 1 ]; then
        print_error "$unit_name 未检测到有效Xvnc进程"
        systemctl status "$unit_name" --no-pager -l 2>/dev/null | tail -n 20 || true
        journalctl -u "$unit_name" -n 30 --no-pager 2>/dev/null || true
        return 1
    fi

    print_success "已启用并启动 $unit_name（端口: $((5900 + display_no))）"
    verify_vnc_logind_session "$username" "$display_no" || true
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
    local original_owner

    if ! id "$username" &>/dev/null; then
        print_warning "用户 $username 不存在，跳过 systemd VNC 配置"
        return 1
    fi

    if ! check_vnc_runtime_requirements "$session"; then
        print_error "用户 $username 的VNC运行环境检查失败，已跳过 systemd 启动"
        return 1
    fi

    print_info "正在检查显示号 :$display_no 的占用情况..."
    original_owner=$(get_display_owner "$display_no")
    resolved_display_no=$(resolve_display_for_user "$username" "$display_no") || {
        return 1
    }

    if [ "$resolved_display_no" != "$display_no" ]; then
        print_info "用户 $username 将使用显示号 :$resolved_display_no（原请求 :$display_no）"

        # 若原显示号本就属于该用户，且选择了新显示号，则清理旧显示号，避免同一用户保留多个旧映射/会话
        if [ "$original_owner" = "$username" ]; then
            cleanup_vnc_for_user "$username" "full" "$display_no" >/dev/null 2>&1 || true
            print_info "已清理用户 $username 的旧显示号 :$display_no"
        fi
    fi

    set_vnc_display_mapping "$username" "$resolved_display_no"

    # Wrapper模式已修复GNOME reauthentication；恢复旧版脚本曾禁用的正常锁屏。
    restore_vnc_gnome_lock_defaults "$username"

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

    show_existing_users_for_creation
    
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

    # 询问是否授予管理员权限
    prompt_info "是否将这些用户设置为管理员？(y/n) [默认: n]:"
    read -r is_admin_choice
    
    # 询问是否配置VNC
    prompt_info "是否为用户配置VNC？(y/n) [默认: n]:"
    read -r setup_vnc_choice
    
    local vnc_password=""
    local use_systemd_vnc="n"
    local start_display_no="2"
    local vnc_geometry="1920x1080"
    local vnc_session="gnome-classic"
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
        create_user "$username" "$password" "$shell" "$comment" "$is_admin_choice"
        local result=$?
        
        if [ $result -eq 0 ] || [ $result -eq 2 ]; then
            created_users+=("$username")
            
            # 如果需要配置VNC
            if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
                setup_vnc "$username" "$vnc_password"

                if [[ "$use_systemd_vnc" =~ ^[Yy]$ ]]; then
                    if setup_vnc_systemd "$username" "$current_display_no" "$vnc_geometry" "$vnc_session" "$vnc_localhost"; then
                        print_user_vnc_connection_hint "$username"
                    else
                        print_warning "用户 $username 的systemd VNC配置失败，请检查日志"
                    fi
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
        if [[ "$is_admin_choice" =~ ^[Yy]$ ]]; then
            echo "管理员权限: 是"
        else
            echo "管理员权限: 否"
        fi
        if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
            echo "VNC密码: $vnc_password"
            if [[ "$use_systemd_vnc" =~ ^[Yy]$ ]]; then
                echo "VNC模式: systemd + vncserver_wrapper（自动启动，支持正常锁屏/解锁）"
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

    show_existing_users_for_creation
    
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

    # 询问是否授予管理员权限
    prompt_info "是否将用户 $username 设置为管理员？(y/n) [默认: n]:"
    read -r is_admin_choice
    
    echo ""
    
    # 创建用户
    create_user "$username" "$password" "$shell" "$comment" "$is_admin_choice"
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
                    if setup_vnc_systemd "$username" "$display_no" "$vnc_geometry" "$vnc_session" "$vnc_localhost"; then
                        print_user_vnc_connection_hint "$username"
                    else
                        print_warning "用户 $username 的systemd VNC配置失败，请检查日志"
                    fi
                fi
            fi
        fi
    fi
    
    echo ""
    print_success "处理完成！"
    echo ""
}

# 获取用户所属组列表
get_user_group_list() {
    local username=$1
    local groups

    if ! id "$username" &>/dev/null; then
        echo "未知"
        return 1
    fi

    groups=$(id -nG "$username" 2>/dev/null)
    if [ -z "$groups" ]; then
        echo "无"
        return 0
    fi

    echo "$groups" | tr ' ' ','
}

# 列表显示现有普通用户及其VNC显示号（统一辅助函数）
list_existing_users_vnc_info() {
    local title=$1
    local users
    local user
    local displays
    local port_list
    local group_list

    print_info "正在扫描系统用户和VNC状态，请稍候..."
    invalidate_vnc_state_cache
    build_vnc_mapping_snapshot
    build_vnc_legacy_snapshot
    build_vnc_process_snapshot

    users=$(awk -F: '
        $3 >= 1000 && $1 != "nobody" && $6 ~ "^/home/" {
            print $1
        }
    ' /etc/passwd)

    if [ -z "$users" ]; then
        print_info "当前未检测到 /home 下的普通用户"
        echo ""
        return 0
    fi

    print_info "$title"
    printf '+------------------+--------------------------------------+----------------------+----------------------+\n'
    printf '| %-16s | %-36s | %-20s | %-20s |\n' "USERNAME" "GROUPS" "VNC DISPLAY" "VNC PORT"
    printf '+------------------+--------------------------------------+----------------------+----------------------+\n'

    while IFS= read -r user; do
        [ -z "$user" ] && continue
        group_list=$(get_user_group_list "$user")
        displays=$(get_user_vnc_displays "$user")
        if [ -n "$displays" ]; then
            local display_list=""
            local d
            port_list=""
            for d in $displays; do
                if [ -z "$display_list" ]; then
                    display_list=":$d"
                else
                    display_list="$display_list, :$d"
                fi

                if [ -z "$port_list" ]; then
                    port_list="$((5900 + d))"
                else
                    port_list="$port_list, $((5900 + d))"
                fi
            done
            printf '| %-16.16s | %-36.36s | %-20.20s | %-20.20s |\n' "$user" "$group_list" "$display_list" "$port_list"
        else
            printf '| %-16.16s | %-36.36s | %-20.20s | %-20.20s |\n' "$user" "$group_list" "none" "none"
        fi
    done <<< "$users"
    printf '+------------------+--------------------------------------+----------------------+----------------------+\n'
    echo ""
}

show_existing_users_for_creation() {
    list_existing_users_vnc_info "现有普通用户（含用户组）及VNC显示号："
}

# 统一VNC配置模式（智能检测密码，自动配置）
vnc_unified_mode() {
    echo ""
    echo "=========================================="
    echo "       VNC配置（密码 + 开机自启）"
    echo "=========================================="
    echo ""

    show_existing_users_for_vnc_setup
    
    prompt_info "请输入用户名列表（用空格分隔）："
    read -r user_list
    
    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi

    echo ""
    prompt_info "是否为用户配置开机自启VNC? (y/n) [默认: y]:"
    read -r enable_autostart_choice
    if [ -z "$enable_autostart_choice" ] || [[ "$enable_autostart_choice" =~ ^[Yy]$ ]]; then
        enable_autostart_choice="y"
    else
        enable_autostart_choice="n"
    fi

    local start_display_no="2"
    local vnc_geometry="1920x1080"
    local vnc_session="gnome-classic"
    local vnc_localhost="no"

    if [[ "$enable_autostart_choice" =~ ^[Yy]$ ]]; then
        echo ""
        start_display_no=$(ask_start_display "请输入起始显示号（第一个用户将使用该显示号）" "2")

        prompt_info "请输入VNC分辨率 [默认: 1920x1080]:"
        read -r vnc_geometry
        if [ -z "$vnc_geometry" ]; then
            vnc_geometry="1920x1080"
        fi

        prompt_info "是否仅允许本机访问（localhost）？(y/n) [默认: n]:"
        read -r localhost_choice
        if [[ "$localhost_choice" =~ ^[Yy]$ ]]; then
            vnc_localhost="yes"
        fi

        prompt_info "请输入桌面会话（如 gnome-classic）[默认: gnome-classic]:"
        read -r vnc_session
        if [ -z "$vnc_session" ]; then
            vnc_session="gnome-classic"
        fi
    fi
    
    echo ""
    print_info "开始配置VNC..."
    echo ""

    local current_display_no="$start_display_no"
    for username in $user_list; do
        if ! id "$username" &>/dev/null; then
            print_warning "用户 $username 不存在，跳过"
            echo ""
            continue
        fi

        # 检查是否已有VNC密码
        if [ -f "/home/$username/.vnc/passwd" ]; then
            print_success "用户 $username 已存在VNC密码"
        else
            # 需要设置新密码
            prompt_info "用户 $username 的VNC密码："
            read -rs vnc_password
            echo ""
            
            if [ -z "$vnc_password" ]; then
                print_error "用户 $username 的VNC密码不能为空，已跳过"
                echo ""
                continue
            fi
            
            setup_vnc "$username" "$vnc_password"
        fi

        # 配置开机自启（如果用户选择）
        if [[ "$enable_autostart_choice" =~ ^[Yy]$ ]]; then
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

            # 现有用户迁移到wrapper后恢复GNOME正常锁屏/解锁。
            restore_vnc_gnome_lock_defaults "$username"

            write_vnc_xstartup "$username" "$vnc_session"

            if enable_start_vnc_service "$username" "$resolved_display_no" "$vnc_geometry" "$vnc_localhost"; then
                print_user_vnc_connection_hint "$username"
            else
                print_warning "用户 $username 的开机自启配置失败，请检查日志"
            fi
            current_display_no=$((resolved_display_no + 1))
        fi

        echo ""
    done
    
    print_success "VNC配置完成！"
    echo ""
}

# 密码更改模式
change_password_mode() {
    echo ""
    echo "=========================================="
    echo "          更改用户密码"
    echo "=========================================="
    echo ""

    show_existing_users_for_vnc_setup
    
    prompt_info "请输入用户名列表（用空格分隔）："
    read -r user_list
    
    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi

    echo ""
    prompt_info "请选择要更改的密码："
    echo "  1) 更改系统用户密码" >&2
    echo "  2) 更改VNC密码" >&2
    echo "  3) 同时更改系统用户密码和VNC密码" >&2
    prompt_info "请输入选项 (1-3) [默认: 2]:"
    read -r password_choice

    if [ -z "$password_choice" ]; then
        password_choice="2"
    fi

    local change_user_password=0
    local change_vnc_password=0
    local user_password=""
    local vnc_password=""

    case "$password_choice" in
        1)
            change_user_password=1
            ;;
        2)
            change_vnc_password=1
            ;;
        3)
            change_user_password=1
            change_vnc_password=1
            ;;
        *)
            change_vnc_password=1
            ;;
    esac

    echo ""
    if [ "$change_user_password" -eq 1 ]; then
        prompt_info "请输入新的系统用户密码："
        read -r user_password
        if [ -z "$user_password" ]; then
            print_warning "系统用户密码为空，将跳过用户密码更改"
            change_user_password=0
        fi
    fi

    if [ "$change_vnc_password" -eq 1 ]; then
        prompt_info "请输入新的VNC密码："
        read -rs vnc_password
        echo ""
        if [ -z "$vnc_password" ]; then
            print_warning "VNC密码为空，将跳过VNC密码更改"
            change_vnc_password=0
        fi
    fi

    echo ""
    print_info "开始更改密码..."
    echo ""

    for username in $user_list; do
        if ! id "$username" &>/dev/null; then
            print_warning "用户 $username 不存在，跳过"
            echo ""
            continue
        fi

        # 更改系统用户密码
        if [ "$change_user_password" -eq 1 ]; then
            if echo "$username:$user_password" | chpasswd 2>&1; then
                print_success "用户 $username 的系统密码已更改"
            else
                print_warning "用户 $username 的系统密码更改失败"
            fi
        fi

        # 更改VNC密码
        if [ "$change_vnc_password" -eq 1 ]; then
            setup_vnc "$username" "$vnc_password"
        fi

        echo ""
    done
    
    print_success "密码更改完成！"
    echo ""
}

# 为现有用户配置VNC模式
show_existing_users_for_vnc_setup() {
    list_existing_users_vnc_info "当前可用于VNC配置的普通用户（含用户组与VNC显示号）："
}

show_existing_users_for_delete() {
    list_existing_users_vnc_info "当前可删除的普通用户（含用户组与VNC显示号）："
}

# 删除用户模式（含VNC清理）
delete_mode() {
    echo ""
    echo "=========================================="
    echo "         删除用户和VNC清理"
    echo "=========================================="
    echo ""

    show_existing_users_for_delete

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

# 仅禁用VNC模式（保留系统用户）
disable_vnc_only_mode() {
    echo ""
    echo "=========================================="
    echo "        仅禁用VNC（保留用户）"
    echo "=========================================="
    echo ""

    show_existing_users_for_vnc_setup

    prompt_info "请输入要禁用VNC的用户名列表（用空格分隔）："
    read -r user_list

    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi

    echo ""
    print_warning "禁用前检查清单："
    echo "  - 将停止并禁用该用户相关VNC服务"
    echo "  - 将清理显示号映射与会话进程"
    echo "  - 将移除已添加的按端口放行规则"
    echo "  - 不会删除Linux用户与/home目录"
    echo ""
    prompt_info "是否继续进入逐用户禁用确认流程？(y/n) [默认: n]:"
    read -r pre_disable_confirm
    if ! [[ "$pre_disable_confirm" =~ ^[Yy]$ ]]; then
        print_warning "已取消禁用流程"
        return
    fi

    echo ""
    print_info "开始禁用VNC并清理资源..."
    echo ""

    for username in $user_list; do
        local user_exists=1
        local current_displays=""
        local current_displays_flat=""
        local target_display_input
        local normalized_displays
        local selected_displays=""
        local display_token

        prompt_info "是否确认仅禁用用户 $username 的VNC（保留系统用户）？(y/n) [默认: n]:"
        read -r confirm_disable

        if ! [[ "$confirm_disable" =~ ^[Yy]$ ]]; then
            prompt_warning "已跳过用户 $username"
            echo ""
            continue
        fi

        if ! id "$username" &>/dev/null; then
            user_exists=0
            print_warning "用户 $username 不存在，已仅尝试执行VNC清理"
        else
            current_displays=$(get_user_vnc_displays "$username")
            current_displays_flat=$(echo "$current_displays" | tr '\n' ' ')
            if [ -n "$current_displays" ]; then
                print_info "用户 $username 当前VNC连接信息："
                for display_token in $current_displays; do
                    echo "  - 显示号 :$display_token, 端口: $((5900 + display_token))"
                done
            else
                print_warning "未找到用户 $username 的VNC显示映射"
            fi
        fi

        prompt_info "请输入要清理的显示号（支持多个，如 2 5 或 2,5）。直接回车表示清理该用户全部显示号："
        read -r target_display_input

        # 回车：清理该用户全部显示号
        if [ -z "$target_display_input" ]; then
            cleanup_vnc_for_user "$username" "full"
            echo ""
            continue
        fi

        # 兼容逗号分隔输入
        normalized_displays=$(echo "$target_display_input" | tr ',' ' ')

        for display_token in $normalized_displays; do
            if ! [[ "$display_token" =~ ^[0-9]+$ ]]; then
                print_warning "显示号 '$display_token' 无效（必须为数字），已跳过"
                continue
            fi

            # 去重
            if [[ " $selected_displays " == *" $display_token "* ]]; then
                continue
            fi

            # 对存在的用户，限制只能清理其自身显示号
            if [ "$user_exists" -eq 1 ] && [ -n "$current_displays_flat" ] && [[ " $current_displays_flat " != *" $display_token "* ]]; then
                print_warning "显示号 :$display_token 不属于用户 $username，已跳过"
                continue
            fi

            selected_displays="$selected_displays $display_token"
        done

        if [ -z "$selected_displays" ]; then
            print_warning "没有可清理的有效显示号，已跳过用户 $username"
            echo ""
            continue
        fi

        cleanup_vnc_for_user "$username" "full" "$selected_displays"
        echo ""
    done

    print_success "仅禁用VNC流程完成！"
    echo ""
}

# 显示主菜单
show_menu() {
    clear
    echo "=========================================="
    echo "      用户和VNC管理交互式脚本"
    echo "=========================================="
    echo -e "${YELLOW}[提示]${NC} Windows终端用户若点击屏幕导致界面冻结，"
    echo -e "       请按下 ${BLUE}Esc${NC} 或 ${BLUE}再次点击右键${NC} 以恢复响应。"
    echo -e "       SSH环境建议保持窗口焦点，避免在运行扫描时进行文本选择。"
    echo ""
    echo "请选择操作模式："
    echo ""
    echo "  1) 批量创建用户和配置VNC（wrapper会话，支持正常锁屏/解锁）"
    echo "  2) 创建单个用户和配置VNC（wrapper会话，支持正常锁屏/解锁）"
    echo "  3) 更改用户密码"
    echo "  4) 为现有用户配置VNC（密码+wrapper开机自启）"
    echo "  5) 删除用户（含VNC清理）"
    echo "  6) 仅禁用VNC（保留用户）"
    echo "  7) 退出"
    echo ""
    echo "=========================================="
}

# 主函数
main() {
    while true; do
        show_menu
        prompt_info "请输入选项 (1-7):"
        read -r choice
        
        case $choice in
            1)
                batch_mode
                ;;
            2)
                single_mode
                ;;
            3)
                change_password_mode
                ;;
            4)
                vnc_unified_mode
                ;;
            5)
                delete_mode
                ;;
            6)
                disable_vnc_only_mode
                ;;
            7)
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
