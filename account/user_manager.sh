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

VNC_ENV_CHECKED=0
VNC_ENV_READY=0
VNC_SERVER_CMD=""
VNC_DESKTOP_NAME=""
VNC_DESKTOP_CMD=""
VNC_SESSION_VALUE=""
VNC_DESKTOP_KIND=""
SERVER_IP_ADDRESSES=""
FIREWALL_ACTIVE=0
VNC_LAUNCH_MODE="legacy"

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "此脚本需要使用 root 权限运行！"
        echo "请使用: sudo $0"
        exit 1
    fi
}

command_exists() {
    command -v "$1" &>/dev/null
}

detect_package_manager() {
    local package_manager
    for package_manager in dnf yum apt-get; do
        if command_exists "$package_manager"; then
            echo "$package_manager"
            return 0
        fi
    done
    return 1
}

is_rpm_system() {
    command_exists rpm
}

is_rpm_package_installed() {
    local package_name=$1
    rpm -q "$package_name" &>/dev/null
}

install_vnc_packages() {
    local package_manager

    package_manager=$(detect_package_manager)
    if [ -z "$package_manager" ]; then
        print_error "未检测到支持的包管理器，无法自动安装VNC组件"
        return 1
    fi

    print_warning "检测到系统缺少VNC服务端组件"
    print_info "是否现在自动安装VNC服务端？(y/n) [默认: y]:"
    read -r install_choice

    if [[ -n "$install_choice" && ! "$install_choice" =~ ^[Yy]$ ]]; then
        print_warning "已跳过自动安装VNC组件"
        return 1
    fi

    case "$package_manager" in
        dnf|yum)
            if ! "$package_manager" install -y tigervnc-server; then
                print_error "安装 tigervnc-server 失败"
                return 1
            fi
            ;;
        apt-get)
            if ! apt-get update || ! apt-get install -y tigervnc-standalone-server tigervnc-tools; then
                print_error "安装 TigerVNC 组件失败"
                return 1
            fi
            ;;
        *)
            print_error "暂不支持自动安装的包管理器: $package_manager"
            return 1
            ;;
    esac

    return 0
}

ensure_vnc_runtime_dependencies() {
    local package_manager
    local missing_packages=()

    if ! command_exists Xvnc; then
        print_error "未检测到 Xvnc，可执行的TigerVNC服务端不完整"
        return 1
    fi

    if ! command_exists xauth; then
        missing_packages+=("xauth")
    fi

    if is_rpm_system; then
        if ! is_rpm_package_installed xorg-x11-fonts-Type1; then
            missing_packages+=("xorg-x11-fonts-Type1")
        fi
        if ! is_rpm_package_installed xorg-x11-fonts-misc; then
            missing_packages+=("xorg-x11-fonts-misc")
        fi
    fi

    if [ ${#missing_packages[@]} -eq 0 ]; then
        return 0
    fi

    package_manager=$(detect_package_manager)
    if [ -z "$package_manager" ]; then
        print_error "无法自动安装VNC运行时依赖: ${missing_packages[*]}"
        return 1
    fi

    print_warning "检测到缺少VNC运行时依赖: ${missing_packages[*]}"
    print_info "是否现在自动安装这些依赖？(y/n) [默认: y]:"
    read -r install_runtime_choice

    if [[ -n "$install_runtime_choice" && ! "$install_runtime_choice" =~ ^[Yy]$ ]]; then
        print_warning "已跳过VNC运行时依赖安装"
        return 1
    fi

    case "$package_manager" in
        dnf|yum)
            if ! "$package_manager" install -y "${missing_packages[@]}"; then
                print_error "安装VNC运行时依赖失败: ${missing_packages[*]}"
                return 1
            fi
            ;;
        apt-get)
            if ! apt-get update || ! apt-get install -y xauth xfonts-base xfonts-100dpi xfonts-75dpi; then
                print_error "安装VNC运行时依赖失败"
                return 1
            fi
            ;;
        *)
            print_error "暂不支持自动安装运行时依赖的包管理器: $package_manager"
            return 1
            ;;
    esac

    return 0
}

detect_vnc_server_command() {
    if command_exists vncserver; then
        echo "$(command -v vncserver)"
        return 0
    fi

    if command_exists tigervncserver; then
        echo "$(command -v tigervncserver)"
        return 0
    fi

    return 1
}

supports_vnc_systemd_launch() {
    [ -f "/usr/lib/systemd/system/vncserver@.service" ] && command_exists systemctl && [ "$(id -u)" -eq 0 ]
}

has_xsession_entry() {
    local session_name=$1

    [ -f "/usr/share/xsessions/${session_name}.desktop" ]
}

resolve_vnc_desktop_profile() {
    local mode=${1:-auto}

    case "$mode" in
        auto)
            if command_exists xfce4-session && has_xsession_entry xfce; then
                echo "XFCE|xfce4-session|xfce|desktop"
                return 0
            fi
            if command_exists mate-session && has_xsession_entry mate; then
                echo "MATE|mate-session|mate|desktop"
                return 0
            fi
            if command_exists startlxqt && has_xsession_entry lxqt; then
                echo "LXQt|startlxqt|lxqt|desktop"
                return 0
            fi
            if command_exists startplasma-x11 && has_xsession_entry plasma; then
                echo "KDE Plasma|startplasma-x11|plasma|desktop"
                return 0
            fi
            if command_exists xterm && has_xsession_entry xinit-compat; then
                echo "Minimal X11|xterm|xinit-compat|minimal"
                return 0
            fi
            if command_exists gnome-session && (has_xsession_entry gnome-classic || has_xsession_entry gnome-classic-xorg); then
                echo "GNOME Classic|env GNOME_SHELL_SESSION_MODE=classic gnome-session --session=gnome-classic|gnome-classic|desktop"
                return 0
            fi
            if command_exists gnome-session && (has_xsession_entry gnome || has_xsession_entry gnome-xorg); then
                echo "GNOME|gnome-session|gnome|desktop"
                return 0
            fi
            ;;
        minimal)
            if command_exists xterm && has_xsession_entry xinit-compat; then
                echo "Minimal X11|xterm|xinit-compat|minimal"
                return 0
            fi
            ;;
        xfce)
            if command_exists xfce4-session && has_xsession_entry xfce; then
                echo "XFCE|xfce4-session|xfce|desktop"
                return 0
            fi
            ;;
        mate)
            if command_exists mate-session && has_xsession_entry mate; then
                echo "MATE|mate-session|mate|desktop"
                return 0
            fi
            ;;
        lxqt)
            if command_exists startlxqt && has_xsession_entry lxqt; then
                echo "LXQt|startlxqt|lxqt|desktop"
                return 0
            fi
            ;;
        plasma)
            if command_exists startplasma-x11 && has_xsession_entry plasma; then
                echo "KDE Plasma|startplasma-x11|plasma|desktop"
                return 0
            fi
            ;;
        gnome-classic)
            if command_exists gnome-session && (has_xsession_entry gnome-classic || has_xsession_entry gnome-classic-xorg); then
                echo "GNOME Classic|env GNOME_SHELL_SESSION_MODE=classic gnome-session --session=gnome-classic|gnome-classic|desktop"
                return 0
            fi
            ;;
        gnome)
            if command_exists gnome-session && (has_xsession_entry gnome || has_xsession_entry gnome-xorg); then
                echo "GNOME|gnome-session|gnome|desktop"
                return 0
            fi
            ;;
    esac

    return 1
}

choose_vnc_desktop_mode() {
    local mode_keys=("auto")
    local auto_profile
    local auto_name="自动"
    local mode_labels=()
    local mode_choice

    auto_profile=$(resolve_vnc_desktop_profile auto 2>/dev/null || true)
    if [ -n "$auto_profile" ]; then
        auto_name=${auto_profile%%|*}
    fi
    mode_labels+=("自动选择（推荐；当前主机默认将使用 ${auto_name}）")

    if resolve_vnc_desktop_profile minimal >/dev/null; then
        mode_keys+=("minimal")
        mode_labels+=("Minimal X11（仅基础图形会话，适合排障和临时使用）")
    fi
    if resolve_vnc_desktop_profile xfce >/dev/null; then
        mode_keys+=("xfce")
        mode_labels+=("XFCE（完整轻量桌面，推荐用于VNC）")
    fi
    if resolve_vnc_desktop_profile mate >/dev/null; then
        mode_keys+=("mate")
        mode_labels+=("MATE（完整轻量桌面）")
    fi
    if resolve_vnc_desktop_profile lxqt >/dev/null; then
        mode_keys+=("lxqt")
        mode_labels+=("LXQt（完整轻量桌面，资源占用较低）")
    fi
    if resolve_vnc_desktop_profile plasma >/dev/null; then
        mode_keys+=("plasma")
        mode_labels+=("KDE Plasma（完整桌面，较重）")
    fi
    if resolve_vnc_desktop_profile gnome-classic >/dev/null; then
        mode_keys+=("gnome-classic")
        mode_labels+=("GNOME Classic（完整桌面，但当前主机上VNC稳定性一般）")
    fi
    if resolve_vnc_desktop_profile gnome >/dev/null; then
        mode_keys+=("gnome")
        mode_labels+=("GNOME（完整桌面，但当前主机上VNC稳定性较差）")
    fi

    echo "" >&2
    print_info "请选择VNC桌面模式：" >&2
    for i in "${!mode_keys[@]}"; do
        echo "  $((i + 1))) ${mode_labels[$i]}" >&2
    done
    echo "" >&2
    print_info "请输入序号 [默认: 1]:" >&2
    read -r mode_choice

    if [ -z "$mode_choice" ]; then
        mode_choice=1
    fi

    if ! [[ "$mode_choice" =~ ^[0-9]+$ ]] || [ "$mode_choice" -lt 1 ] || [ "$mode_choice" -gt ${#mode_keys[@]} ]; then
        print_warning "无效的选择，使用自动模式" >&2
        echo "auto"
        return
    fi

    echo "${mode_keys[$((mode_choice - 1))]}"
}

get_server_ip_addresses() {
    local ip_addresses

    if command_exists hostname; then
        ip_addresses=$(hostname -I 2>/dev/null | xargs)
    fi

    if [ -z "$ip_addresses" ] && command_exists ip; then
        ip_addresses=$(ip -4 addr show 2>/dev/null | awk '/inet / {print $2}' | cut -d/ -f1 | paste -sd ' ' -)
    fi

    echo "$ip_addresses"
}

is_firewalld_active() {
    if ! command_exists firewall-cmd || ! command_exists systemctl; then
        return 1
    fi

    systemctl is-active --quiet firewalld
}

get_user_home() {
    getent passwd "$1" | cut -d: -f6
}

get_lock_pid() {
    local display=$1
    local lock_file="/tmp/.X${display}-lock"

    if [ ! -f "$lock_file" ]; then
        return 1
    fi

    tr -dc '0-9' < "$lock_file"
}

display_process_running() {
    local display=$1
    local lock_pid

    lock_pid=$(get_lock_pid "$display")
    if [ -n "$lock_pid" ] && kill -0 "$lock_pid" 2>/dev/null; then
        return 0
    fi

    if pgrep -af "(Xtigervnc|Xvnc|Xorg).*(:| )${display}(\b|$)" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

cleanup_stale_display_artifacts() {
    local display=$1
    local lock_file="/tmp/.X${display}-lock"
    local socket_file="/tmp/.X11-unix/X${display}"
    local removed=0

    if display_process_running "$display"; then
        return 1
    fi

    if [ -f "$lock_file" ]; then
        rm -f "$lock_file"
        removed=1
    fi

    if [ -S "$socket_file" ]; then
        rm -f "$socket_file"
        removed=1
    fi

    if [ "$removed" -eq 1 ]; then
        print_warning "已清理 display :$display 的陈旧锁文件或socket"
    fi

    return 0
}

display_is_occupied() {
    local display=$1
    local home_dir=$2
    local port=$((5900 + display))
    local lock_file="/tmp/.X${display}-lock"
    local socket_file="/tmp/.X11-unix/X${display}"

    if display_process_running "$display"; then
        return 0
    fi

    if command_exists ss && ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
        return 0
    fi

    if [ -d "$home_dir/.vnc" ] && compgen -G "$home_dir/.vnc/*:${display}.pid" > /dev/null; then
        return 0
    fi

    if [ -f "$lock_file" ] || [ -S "$socket_file" ]; then
        cleanup_stale_display_artifacts "$display"
    fi

    return 1
}

find_available_display() {
    local username=$1
    local home_dir=$2
    local start_display=${3:-1}
    local display

    for display in $(seq "$start_display" 99); do
        if display_is_occupied "$display" "$home_dir"; then
            continue
        fi

        echo "$display"
        return 0
    done

    return 1
}

try_start_vnc_on_display() {
    local username=$1
    local home_dir=$2
    local display=$3
    local localhost_mode=$4
    local preferred_launch_mode=$5
    local start_output

    print_info "正在为 $username 启动 VNC 会话，桌面环境: $VNC_DESKTOP_NAME，display: :$display"
    start_output=$(start_vnc_session "$username" "$display" "$localhost_mode" 2>&1)
    if [ $? -ne 0 ]; then
        if [ "$preferred_launch_mode" = "systemd" ]; then
            start_output=$(fallback_to_legacy_vnc "$username" "$home_dir" "$display" "$localhost_mode" 2>&1)
            if [ $? -ne 0 ]; then
                echo "$start_output"
                return 1
            fi
        else
            print_warning "首次启动用户 $username 的VNC会话失败，尝试清理 display :$display 后重试一次"
            cleanup_stale_display_artifacts "$display" >/dev/null 2>&1 || true
            start_output=$(start_vnc_session "$username" "$display" "$localhost_mode" 2>&1)
            if [ $? -ne 0 ]; then
                echo "$start_output"
                return 1
            fi
        fi
    fi

    if ! verify_vnc_session_running "$display" "$username"; then
        if [ "$preferred_launch_mode" = "systemd" ] && [ "$VNC_LAUNCH_MODE" = "systemd" ]; then
            start_output=$(fallback_to_legacy_vnc "$username" "$home_dir" "$display" "$localhost_mode" 2>&1)
            if [ $? -eq 0 ] && verify_vnc_session_running "$display" "$username"; then
                echo "$start_output"
                return 0
            fi
        fi

        echo "$start_output"
        return 1
    fi

    echo "$start_output"
    return 0
}

write_vnc_xstartup() {
    local username=$1
    local home_dir=$2
    local desktop_cmd=$3
    local xstartup_path="$home_dir/.vnc/xstartup"
    local startup_command="$desktop_cmd"

    if [ "$VNC_SESSION_VALUE" = "xinit-compat" ] && command_exists xterm; then
        cat > "$xstartup_path" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
xsetroot -solid '#1f2430' >/dev/null 2>&1 || true
if command -v matchbox-window-manager >/dev/null 2>&1; then
    matchbox-window-manager -use_titlebar yes -use_cursor yes >/dev/null 2>&1 &
fi
exec xterm -fa Monospace -fs 11 -geometry 120x36+20+20 -ls -title "VNC Terminal"
EOF

        chown "$username:$username" "$xstartup_path"
        chmod 700 "$xstartup_path"
        return 0
    fi

    if [ "$VNC_SESSION_VALUE" = "xfce" ]; then
        cat > "$xstartup_path" <<'EOF'
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
if [ -d "/run/user/$(id -u)" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
if command -v dbus-launch >/dev/null 2>&1; then
    exec dbus-launch --exit-with-session xfce4-session
fi
exec xfce4-session
EOF

        chown "$username:$username" "$xstartup_path"
        chmod 700 "$xstartup_path"
        return 0
    fi

    if command_exists dbus-launch; then
        startup_command="dbus-launch --exit-with-session $desktop_cmd"
    fi

    cat > "$xstartup_path" <<EOF
#!/bin/sh
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS
export XDG_SESSION_TYPE=x11
exec $startup_command
EOF

    chown "$username:$username" "$xstartup_path"
    chmod 700 "$xstartup_path"
}

write_vnc_xclients() {
    local username=$1
    local home_dir=$2
    local xclients_path="$home_dir/.Xclients"

    if [ "$VNC_SESSION_VALUE" = "xinit-compat" ] && command_exists matchbox-window-manager; then
        cat > "$xclients_path" <<'EOF'
#!/bin/sh
xsetroot -solid '#1f2430' >/dev/null 2>&1 || true
matchbox-window-manager -use_titlebar yes -use_cursor yes >/dev/null 2>&1 &
exec xterm -fa Monospace -fs 11 -geometry 120x36+20+20 -ls -title "VNC Terminal"
EOF
    elif [ "$VNC_SESSION_VALUE" = "xinit-compat" ]; then
        cat > "$xclients_path" <<'EOF'
#!/bin/sh
xsetroot -solid '#1f2430' >/dev/null 2>&1 || true
exec xterm -fa Monospace -fs 11 -geometry 120x36+20+20 -ls -title "VNC Terminal"
EOF
    elif [ "$VNC_SESSION_VALUE" = "xfce" ]; then
        cat > "$xclients_path" <<'EOF'
#!/bin/sh
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
export XDG_CURRENT_DESKTOP=XFCE
export DESKTOP_SESSION=xfce
if [ -d "/run/user/$(id -u)" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
exec xfce4-session
EOF
    else
        cat > "$xclients_path" <<EOF
#!/bin/sh
exec $VNC_DESKTOP_CMD
EOF
    fi

    chown "$username:$username" "$xclients_path"
    chmod 700 "$xclients_path"
}

write_legacy_vnc_config() {
    local username=$1
    local home_dir=$2
    local direct_access=$3
    local config_path="$home_dir/.vnc/config"
    local legacy_xdg_dir="$home_dir/.vnc/legacy-xdg/tigervnc"
    local legacy_xdg_config="$legacy_xdg_dir/config"

    mkdir -p "$home_dir/.vnc"
    mkdir -p "$legacy_xdg_dir"

    cat > "$config_path" <<EOF
geometry=1920x1080
depth=24
securitytypes=vncauth,tlsvnc
alwaysshared
EOF

    if [[ ! "$direct_access" =~ ^[Yy]$ ]]; then
        echo "localhost" >> "$config_path"
    fi

    chown "$username:$username" "$config_path"
    chmod 600 "$config_path"

    cat > "$legacy_xdg_config" <<EOF
session=$VNC_SESSION_VALUE
geometry=1920x1080
depth=24
securitytypes=vncauth,tlsvnc
alwaysshared
EOF

    if [[ ! "$direct_access" =~ ^[Yy]$ ]]; then
        echo "localhost" >> "$legacy_xdg_config"
    fi

    chown -R "$username:$username" "$home_dir/.vnc/legacy-xdg"
    chmod 700 "$home_dir/.vnc/legacy-xdg" "$legacy_xdg_dir"
    chmod 600 "$legacy_xdg_config"
}

write_vnc_gnome_tweaks() {
    local username=$1
    local home_dir=$2
    local local_bin_dir="$home_dir/.local/bin"
    local autostart_dir="$home_dir/.config/autostart"
    local setup_script="$local_bin_dir/vnc-session-setup.sh"
    local desktop_file="$autostart_dir/vnc-session-setup.desktop"

    mkdir -p "$local_bin_dir" "$autostart_dir"

    cat > "$setup_script" <<'EOF'
#!/bin/sh
gsettings set org.gnome.desktop.screensaver lock-enabled false >/dev/null 2>&1
gsettings set org.gnome.desktop.lockdown disable-lock-screen true >/dev/null 2>&1
gsettings set org.gnome.desktop.session idle-delay 0 >/dev/null 2>&1
xset s off -dpms >/dev/null 2>&1
EOF

    cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=VNC Session Setup
Exec=$setup_script
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

    chown -R "$username:$username" "$home_dir/.local" "$autostart_dir"
    chmod 700 "$local_bin_dir"
    chmod 755 "$setup_script"
    chmod 644 "$desktop_file"
}

write_vnc_xfce_tweaks() {
    local username=$1
    local home_dir=$2
    local local_bin_dir="$home_dir/.local/bin"
    local autostart_dir="$home_dir/.config/autostart"
    local cache_sessions_dir="$home_dir/.cache/sessions"
    local setup_script="$local_bin_dir/vnc-xfce-session-setup.sh"
    local desktop_file="$autostart_dir/vnc-xfce-session-setup.desktop"
    local override_file

    mkdir -p "$local_bin_dir" "$autostart_dir" "$cache_sessions_dir"

    rm -f "$cache_sessions_dir"/xfce4-session-* >/dev/null 2>&1 || true

    cat > "$setup_script" <<'EOF'
#!/bin/sh
(
sleep 5
if [ -d "/run/user/$(id -u)" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi
export XDG_SESSION_TYPE=x11
export GDK_BACKEND=x11
xset s off -dpms >/dev/null 2>&1 || true
xfconf-query -c xfwm4 -p /general/use_compositing -n -t bool -s false >/dev/null 2>&1 || true
xfconf-query -c xfce4-session -p /general/SaveOnExit -n -t bool -s false >/dev/null 2>&1 || true
pkill -x xfce4-power-manager >/dev/null 2>&1 || true
pkill -x xfce4-screensaver >/dev/null 2>&1 || true
pkill -x xfce-polkit >/dev/null 2>&1 || true
rm -f "$HOME/.cache/sessions"/xfce4-session-* >/dev/null 2>&1 || true
) >/dev/null 2>&1 &
EOF

    cat > "$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Name=VNC XFCE Session Setup
Exec=$setup_script
OnlyShowIn=XFCE;
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

    for override_file in xfce-polkit.desktop xfce4-power-manager.desktop xfce4-screensaver.desktop; do
        cat > "$autostart_dir/$override_file" <<'EOF'
[Desktop Entry]
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
    done

    chown -R "$username:$username" "$home_dir/.local" "$autostart_dir" "$cache_sessions_dir"
    chmod 700 "$local_bin_dir"
    chmod 755 "$setup_script"
    chmod 644 "$desktop_file" "$autostart_dir/xfce-polkit.desktop" "$autostart_dir/xfce4-power-manager.desktop" "$autostart_dir/xfce4-screensaver.desktop"
}

write_vnc_desktop_tweaks() {
    local username=$1
    local home_dir=$2

    case "$VNC_SESSION_VALUE" in
        xfce)
            write_vnc_xfce_tweaks "$username" "$home_dir"
            ;;
        gnome|gnome-classic)
            write_vnc_gnome_tweaks "$username" "$home_dir"
            ;;
    esac
}

write_tigervnc_user_config() {
    local username=$1
    local home_dir=$2
    local direct_access=$3
    local config_dir="$home_dir/.config/tigervnc"
    local config_path="$config_dir/config"

    mkdir -p "$config_dir"

    cat > "$config_path" <<EOF
session=$VNC_SESSION_VALUE
securitytypes=vncauth,tlsvnc
EOF

    if [[ ! "$direct_access" =~ ^[Yy]$ ]]; then
        echo "localhost" >> "$config_path"
    fi

    chown -R "$username:$username" "$home_dir/.config"
    chmod 700 "$config_dir"
    chmod 600 "$config_path"
}

set_vnc_password_file() {
    local username=$1
    local home_dir=$2
    local vnc_password=$3
    local password_file
    local legacy_password_file="$home_dir/.vnc/passwd"
    local legacy_xdg_password_file="$home_dir/.vnc/legacy-xdg/tigervnc/passwd"

    if [ "$VNC_LAUNCH_MODE" = "systemd" ]; then
        mkdir -p "$home_dir/.config/tigervnc"
        password_file="$home_dir/.config/tigervnc/passwd"
    else
        mkdir -p "$home_dir/.vnc"
        mkdir -p "$home_dir/.vnc/legacy-xdg/tigervnc"
        password_file="$legacy_password_file"
    fi

    if ! echo "$vnc_password" | sudo -u "$username" vncpasswd -f > "$password_file"; then
        return 1
    fi

    chown "$username:$username" "$password_file"
    chmod 600 "$password_file"

    mkdir -p "$home_dir/.vnc/legacy-xdg/tigervnc"
    cp -f "$password_file" "$legacy_password_file"
    cp -f "$password_file" "$legacy_xdg_password_file"
    chown "$username:$username" "$legacy_password_file" "$legacy_xdg_password_file"
    chmod 600 "$legacy_password_file" "$legacy_xdg_password_file"

    return 0
}

update_vnc_user_mapping() {
    local display=$1
    local username=$2
    local mapping_file="/etc/tigervnc/vncserver.users"
    local temp_file

    temp_file=$(mktemp)
    touch "$mapping_file"

    awk -v display=":${display}" -v username="$username" '
        BEGIN { updated = 0 }
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { print; next }
        {
            split($0, parts, "=")
            current_display = parts[1]
            current_user = parts[2]
            if (current_display == display) {
                if (!updated) {
                    print display "=" username
                    updated = 1
                }
                next
            }
            if (current_user == username) {
                next
            }
            print
        }
        END {
            if (!updated) {
                print display "=" username
            }
        }
    ' "$mapping_file" > "$temp_file"

    mv "$temp_file" "$mapping_file"
    chmod 644 "$mapping_file"
}

start_vnc_with_systemd() {
    local username=$1
    local display=$2
    local service_name="vncserver@:${display}.service"

    update_vnc_user_mapping "$display" "$username"

    if systemctl is-active --quiet "$service_name"; then
        systemctl stop "$service_name"
    fi

    systemctl daemon-reload
    if ! systemctl start "$service_name"; then
        journalctl -u "$service_name" -n 50 --no-pager 2>/dev/null || true
        return 1
    fi

    return 0
}

start_vnc_session() {
    local username=$1
    local display=$2
    local localhost_mode=$3
    local user_home

    if [ "$VNC_LAUNCH_MODE" = "systemd" ]; then
        start_vnc_with_systemd "$username" "$display"
        return $?
    fi

    user_home=$(get_user_home "$username")
    sudo -u "$username" env HOME="$user_home" XDG_CONFIG_HOME="$user_home/.vnc/legacy-xdg" "$VNC_SERVER_CMD" ":$display" -localhost "$localhost_mode" -xstartup "$user_home/.vnc/xstartup" 2>&1
    return $?
}

fallback_to_legacy_vnc() {
    local username=$1
    local home_dir=$2
    local display=$3
    local localhost_mode=$4
    local fallback_output

    print_warning "systemd 启动方式未能建立可用的VNC监听，回退到 direct vncserver 模式"

    if command_exists systemctl; then
        systemctl stop "vncserver@:${display}.service" >/dev/null 2>&1 || true
    fi

    cleanup_stale_display_artifacts "$display" >/dev/null 2>&1 || true

    if ! write_vnc_xstartup "$username" "$home_dir" "$VNC_DESKTOP_CMD"; then
        print_error "回退到 direct vncserver 模式时生成 xstartup 失败"
        return 1
    fi

    if ! write_vnc_xclients "$username" "$home_dir"; then
        print_error "回退到 direct vncserver 模式时生成 .Xclients 失败"
        return 1
    fi

    if ! write_legacy_vnc_config "$username" "$home_dir" "$([[ "$localhost_mode" = "no" ]] && echo y || echo n)"; then
        print_error "回退到 direct vncserver 模式时生成 VNC 配置失败"
        return 1
    fi

    write_vnc_desktop_tweaks "$username" "$home_dir"

    VNC_LAUNCH_MODE="legacy"
    fallback_output=$(start_vnc_session "$username" "$display" "$localhost_mode" 2>&1)
    if [ $? -ne 0 ]; then
        echo "$fallback_output"
        return 1
    fi

    if ! verify_vnc_session_running "$display" "$username"; then
        echo "$fallback_output"
        return 1
    fi

    echo "$fallback_output"
    return 0
}

wait_for_vnc_listener() {
    local display=$1
    local port=$((5900 + display))
    local attempt

    for attempt in $(seq 1 10); do
        if command_exists ss && ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
            return 0
        fi
        sleep 1
    done

    return 1
}

verify_vnc_session_running() {
    local display=$1
    local username=$2
    local port=$((5900 + display))
    local service_name="vncserver@:${display}.service"
    local attempt

    if ! wait_for_vnc_listener "$display"; then
        return 1
    fi

    for attempt in $(seq 1 3); do
        sleep 1
        if ! command_exists ss || ! ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
            return 1
        fi
    done

    if [ "$VNC_LAUNCH_MODE" = "systemd" ] && ! systemctl is-active --quiet "$service_name"; then
        return 1
    fi

    case "$VNC_SESSION_VALUE" in
        xfce)
            if ! pgrep -u "$username" -x xfce4-session >/dev/null 2>&1; then
                return 1
            fi
            ;;
        xinit-compat)
            if ! pgrep -u "$username" -x xterm >/dev/null 2>&1; then
                return 1
            fi
            ;;
    esac

    return 0
}

stop_existing_user_vnc_sessions() {
    local username=$1
    local session_output
    local display

    session_output=$(sudo -u "$username" env HOME="$(get_user_home "$username")" "$VNC_SERVER_CMD" -list 2>/dev/null || true)
    while IFS= read -r line; do
        display=$(echo "$line" | awk '/^:[0-9]+/ {print $1}')
        if [ -n "$display" ]; then
            print_warning "检测到用户 $username 已有VNC会话 $display，正在停止以应用新配置"
            sudo -u "$username" env HOME="$(get_user_home "$username")" "$VNC_SERVER_CMD" -kill "$display" >/dev/null 2>&1 || true
            cleanup_stale_display_artifacts "${display#:}" >/dev/null 2>&1 || true
            if command_exists systemctl; then
                systemctl stop "vncserver@${display}.service" >/dev/null 2>&1 || true
            fi
        fi
    done <<< "$session_output"

    pkill -u "$username" -f '/usr/bin/Xvnc|Xtigervnc|xinit /etc/X11/xinit/Xsession' >/dev/null 2>&1 || true
}

open_vnc_firewall_port() {
    local port=$1

    if [ "$FIREWALL_ACTIVE" -ne 1 ]; then
        return 0
    fi

    if firewall-cmd --quiet --query-port="${port}/tcp"; then
        print_info "firewalld 已允许 ${port}/tcp"
        return 0
    fi

    print_info "检测到 firewalld 正在运行，是否开放 ${port}/tcp 用于VNC直连？(y/n) [默认: y]:"
    read -r firewall_choice

    if [[ -n "$firewall_choice" && ! "$firewall_choice" =~ ^[Yy]$ ]]; then
        print_warning "已跳过开放防火墙端口 ${port}/tcp"
        return 0
    fi

    if firewall-cmd --permanent --add-port="${port}/tcp" && firewall-cmd --reload; then
        print_success "已开放防火墙端口 ${port}/tcp"
        return 0
    fi

    print_warning "防火墙端口 ${port}/tcp 开放失败，请手动检查 firewalld 配置"
    return 1
}

prepare_vnc_environment() {
    if [ "$VNC_ENV_CHECKED" -eq 1 ]; then
        if [ "$VNC_ENV_READY" -eq 1 ]; then
            return 0
        fi
        return 1
    fi

    VNC_ENV_CHECKED=1

    if ! command_exists vncpasswd || ! detect_vnc_server_command >/dev/null; then
        if ! install_vnc_packages; then
            return 1
        fi
    fi

    VNC_SERVER_CMD=$(detect_vnc_server_command)
    if [ -z "$VNC_SERVER_CMD" ] || ! command_exists vncpasswd; then
        print_error "VNC组件仍不完整，请确认 vncserver 和 vncpasswd 已安装"
        return 1
    fi

    if ! ensure_vnc_runtime_dependencies; then
        print_error "VNC运行时依赖不完整，无法继续配置"
        return 1
    fi

    if ! resolve_vnc_desktop_profile auto >/dev/null && ! resolve_vnc_desktop_profile minimal >/dev/null && ! resolve_vnc_desktop_profile gnome >/dev/null && ! resolve_vnc_desktop_profile gnome-classic >/dev/null; then
        print_error "未检测到可用的桌面会话（如 GNOME/XFCE/MATE/KDE）"
        print_info "请先安装桌面环境，再运行VNC配置"
        return 1
    fi

    SERVER_IP_ADDRESSES=$(get_server_ip_addresses)
    if supports_vnc_systemd_launch; then
        VNC_LAUNCH_MODE="systemd"
    fi

    if is_firewalld_active; then
        FIREWALL_ACTIVE=1
    fi

    print_success "VNC环境检查通过"
    print_info "检测到VNC服务命令: $VNC_SERVER_CMD"
    print_info "检测到VNC启动方式: $VNC_LAUNCH_MODE"
    if [ -n "$SERVER_IP_ADDRESSES" ]; then
        print_info "检测到服务器IP: $SERVER_IP_ADDRESSES"
    fi

    VNC_ENV_READY=1
    return 0
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
    print_info "系统中可用的Shell列表：" >&2
    for i in "${!shells[@]}"; do
        echo "  $((i+1))) ${shells[$i]}" >&2
    done
    echo "" >&2
    print_info "请选择默认shell (输入序号) [默认: 1]:" >&2
    read -r shell_choice
    
    # 验证输入
    if [ -z "$shell_choice" ]; then
        shell_choice=1
    fi
    
    # 检查输入是否为有效数字
    if ! [[ "$shell_choice" =~ ^[0-9]+$ ]] || [ "$shell_choice" -lt 1 ] || [ "$shell_choice" -gt ${#shells[@]} ]; then
        print_warning "无效的选择，使用第一个shell: ${shells[0]}" >&2
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
        if ! sudo useradd -m -s "$shell" -c "$comment" "$username" 2>&1; then
            print_error "创建用户 $username 失败"
            return 1
        fi
    else
        if ! sudo useradd -m -s "$shell" "$username" 2>&1; then
            print_error "创建用户 $username 失败"
            return 1
        fi
    fi
    
    # 设置密码
    if ! echo "$username:$password" | sudo chpasswd 2>&1; then
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
    local direct_access=$3
    local desktop_mode=${4:-auto}
    local home_dir
    local display
    local port
    local localhost_mode="yes"
    local start_output
    local xauthority_path
    local preferred_launch_mode
    local attempt_display
    local next_display_start=1
    local max_display_attempts=5
    local attempt_number
    local desktop_info
    
    # 检查用户是否存在
    if ! id "$username" &>/dev/null; then
        print_warning "用户 $username 不存在，跳过VNC配置"
        return 1
    fi

    if [ -z "$vnc_password" ]; then
        print_error "VNC密码不能为空"
        return 1
    fi

    if ! prepare_vnc_environment; then
        print_error "VNC环境检查失败，跳过用户 $username 的VNC配置"
        return 1
    fi

    desktop_info=$(resolve_vnc_desktop_profile "$desktop_mode")
    if [ -z "$desktop_info" ]; then
        print_error "所选VNC桌面模式不可用: $desktop_mode"
        return 1
    fi

    VNC_DESKTOP_NAME=${desktop_info%%|*}
    desktop_info=${desktop_info#*|}
    VNC_DESKTOP_CMD=${desktop_info%%|*}
    desktop_info=${desktop_info#*|}
    VNC_SESSION_VALUE=${desktop_info%%|*}
    VNC_DESKTOP_KIND=${desktop_info#*|}

    print_info "本次VNC桌面模式: $VNC_DESKTOP_NAME ($VNC_SESSION_VALUE)"
    if [ "$desktop_mode" = "auto" ] && [ "$VNC_SESSION_VALUE" = "xinit-compat" ]; then
        print_warning "当前主机暂未检测到可用的完整轻量桌面，自动模式将回退到 Minimal X11"
    fi
    if [ "$VNC_SESSION_VALUE" = "xfce" ] && [ "$VNC_LAUNCH_MODE" = "systemd" ]; then
        print_info "检测到 XFCE 在当前主机上使用 direct vncserver 启动更稳定，自动切换到 legacy 模式"
        VNC_LAUNCH_MODE="legacy"
    fi

    home_dir=$(get_user_home "$username")
    if [ -z "$home_dir" ] || [ ! -d "$home_dir" ]; then
        print_error "未找到用户 $username 的home目录"
        return 1
    fi

    xauthority_path="$home_dir/.Xauthority"
    if [ ! -f "$xauthority_path" ]; then
        touch "$xauthority_path"
        chown "$username:$username" "$xauthority_path"
        chmod 600 "$xauthority_path"
    fi
    
    # 创建.vnc目录（如果不存在）
    if [ ! -d "$home_dir/.vnc" ]; then
        mkdir -p "$home_dir/.vnc"
        chown "$username:$username" "$home_dir/.vnc"
        chmod 700 "$home_dir/.vnc"
        print_info "已创建 $home_dir/.vnc 目录"
    fi

    stop_existing_user_vnc_sessions "$username"
    
    # 设置VNC密码
    print_info "正在为 $username 设置VNC密码..."
    if ! set_vnc_password_file "$username" "$home_dir" "$vnc_password"; then
        print_error "为用户 $username 设置VNC密码失败"
        return 1
    fi

    if [ "$VNC_LAUNCH_MODE" = "systemd" ]; then
        if ! write_tigervnc_user_config "$username" "$home_dir" "$direct_access"; then
            print_error "为用户 $username 生成 TigerVNC 配置失败"
            return 1
        fi
        write_vnc_xclients "$username" "$home_dir"
        write_vnc_desktop_tweaks "$username" "$home_dir"
        restorecon -RF "$home_dir/.config/tigervnc" "$home_dir/.vnc" >/dev/null 2>&1 || true
    else
        if ! write_vnc_xstartup "$username" "$home_dir" "$VNC_DESKTOP_CMD"; then
            print_error "为用户 $username 生成 xstartup 失败"
            return 1
        fi
        write_vnc_xclients "$username" "$home_dir"
        if ! write_legacy_vnc_config "$username" "$home_dir" "$direct_access"; then
            print_error "为用户 $username 生成 VNC 配置失败"
            return 1
        fi
        write_vnc_desktop_tweaks "$username" "$home_dir"
    fi

    if [[ "$direct_access" =~ ^[Yy]$ ]]; then
        localhost_mode="no"
    fi

    preferred_launch_mode=$VNC_LAUNCH_MODE

    for attempt_number in $(seq 1 "$max_display_attempts"); do
        attempt_display=$(find_available_display "$username" "$home_dir" "$next_display_start")
        if [ -z "$attempt_display" ]; then
            break
        fi

        start_output=$(try_start_vnc_on_display "$username" "$home_dir" "$attempt_display" "$localhost_mode" "$preferred_launch_mode" 2>&1)
        if [ $? -eq 0 ]; then
            display=$attempt_display
            port=$((5900 + display))
            break
        fi

        print_warning "display :$attempt_display 启动失败，尝试下一个可用 display"
        cleanup_stale_display_artifacts "$attempt_display" >/dev/null 2>&1 || true
        if [ "$preferred_launch_mode" = "systemd" ]; then
            systemctl stop "vncserver@:${attempt_display}.service" >/dev/null 2>&1 || true
        fi
        next_display_start=$((attempt_display + 1))
    done

    if [ -z "$display" ]; then
        print_error "启动用户 $username 的VNC会话失败，已尝试多个 display"
        echo "$start_output"
        return 1
    fi

    if [[ "$direct_access" =~ ^[Yy]$ ]]; then
        open_vnc_firewall_port "$port"
    fi
    
    print_success "用户 $username 的VNC密码已设置，并启动了 display :$display (端口 $port)"
    if [ -n "$SERVER_IP_ADDRESSES" ]; then
        print_info "可使用以下地址连接:"
        for server_ip in $SERVER_IP_ADDRESSES; do
            echo "  - ${server_ip}:$display"
        done
    fi

    if [[ "$direct_access" =~ ^[Yy]$ ]]; then
        print_info "已启用网络直连模式，可使用 RealVNC 等客户端连接端口 $port"
    else
        print_info "当前为仅本地监听模式，建议通过SSH隧道连接"
        if [ -n "$SERVER_IP_ADDRESSES" ]; then
            local first_ip
            first_ip=${SERVER_IP_ADDRESSES%% *}
            echo "  ssh -L ${port}:localhost:${port} ${username}@${first_ip}"
            echo "  然后在VNC客户端连接 localhost:${port}"
        fi
    fi

    echo "$start_output"
    return 0
}

# 批量处理模式
batch_mode() {
    local direct_access_choice="n"
    local failed_users=()
    local failed_vnc_users=()
    local desktop_mode="auto"

    echo ""
    echo "=========================================="
    echo "         批量用户创建和VNC配置"
    echo "=========================================="
    echo ""
    
    # 输入用户列表
    print_info "请输入用户名列表（用空格分隔）："
    read -r user_list
    
    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi
    
    # 输入统一密码
    print_info "请输入统一的用户密码："
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
    print_info "是否为所有用户添加备注（如真实姓名）？(y/n) [默认: n]:"
    read -r add_comment_choice
    
    local comment=""
    if [[ "$add_comment_choice" =~ ^[Yy]$ ]]; then
        print_info "请输入用户备注（所有用户使用相同备注）："
        read -r comment
    fi
    
    # 询问是否配置VNC
    print_info "是否为用户配置VNC？(y/n) [默认: n]:"
    read -r setup_vnc_choice
    
    local vnc_password=""
    if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
        print_info "请输入VNC密码（可以与用户密码相同或不同）："
        read -rs vnc_password
        echo ""
        
        if [ -z "$vnc_password" ]; then
            print_warning "VNC密码为空，将跳过VNC配置"
            setup_vnc_choice="n"
        else
            print_info "是否允许VNC客户端直接连接（RealVNC等）？(y/n) [默认: n，推荐SSH隧道]:"
            read -r direct_access_choice
            desktop_mode=$(choose_vnc_desktop_mode)
        fi
    fi
    
    echo ""
    print_info "开始批量处理..."
    echo ""
    
    # 处理每个用户
    local created_users=()
    for username in $user_list; do
        create_user "$username" "$password" "$shell" "$comment"
        local result=$?
        
        if [ $result -eq 0 ] || [ $result -eq 2 ]; then
            created_users+=("$username")
            
            # 如果需要配置VNC
            if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
                if ! setup_vnc "$username" "$vnc_password" "$direct_access_choice" "$desktop_mode"; then
                    failed_vnc_users+=("$username")
                fi
            fi
        else
            failed_users+=("$username")
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
            echo "VNC桌面模式: $desktop_mode"
            if [[ "$direct_access_choice" =~ ^[Yy]$ ]]; then
                echo "VNC连接模式: 允许直连"
            else
                echo "VNC连接模式: 仅本地监听（建议SSH隧道）"
            fi
        fi
        if [ ${#failed_vnc_users[@]} -gt 0 ]; then
            print_warning "以下用户的VNC启动失败："
            for username in "${failed_vnc_users[@]}"; do
                echo "  - $username"
            done
        fi
        if [ ${#failed_users[@]} -gt 0 ]; then
            print_warning "以下用户创建失败："
            for username in "${failed_users[@]}"; do
                echo "  - $username"
            done
        fi
    else
        print_warning "没有创建或处理任何用户"
    fi
    echo ""
}

# 单用户模式
single_mode() {
    local direct_access_choice="n"
    local vnc_result=0
    local desktop_mode="auto"

    echo ""
    echo "=========================================="
    echo "         单用户创建和VNC配置"
    echo "=========================================="
    echo ""
    
    # 输入用户名
    print_info "请输入用户名："
    read -r username
    
    if [ -z "$username" ]; then
        print_error "用户名不能为空！"
        return
    fi
    
    # 输入密码
    print_info "请输入用户密码："
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
    print_info "是否为用户添加备注（如真实姓名）？(y/n) [默认: n]:"
    read -r add_comment_choice
    
    local comment=""
    if [[ "$add_comment_choice" =~ ^[Yy]$ ]]; then
        print_info "请输入用户备注："
        read -r comment
    fi
    
    echo ""
    
    # 创建用户
    create_user "$username" "$password" "$shell" "$comment"
    local result=$?
    
    if [ $result -eq 0 ] || [ $result -eq 2 ]; then
        echo ""
        # 询问是否配置VNC
        print_info "是否为用户 $username 配置VNC？(y/n) [默认: n]:"
        read -r setup_vnc_choice
        
        if [[ "$setup_vnc_choice" =~ ^[Yy]$ ]]; then
            print_info "请输入VNC密码："
            read -rs vnc_password
            echo ""
            
            if [ -z "$vnc_password" ]; then
                print_warning "VNC密码为空，跳过VNC配置"
            else
                print_info "是否允许VNC客户端直接连接（RealVNC等）？(y/n) [默认: n，推荐SSH隧道]:"
                read -r direct_access_choice
                desktop_mode=$(choose_vnc_desktop_mode)
                echo ""
                setup_vnc "$username" "$vnc_password" "$direct_access_choice" "$desktop_mode"
                vnc_result=$?
            fi
        fi
    fi
    
    echo ""
    if [ "$vnc_result" -ne 0 ]; then
        print_warning "用户创建已完成，但VNC启动失败，请检查上方错误信息"
    else
        print_success "处理完成！"
    fi
    echo ""
}

# 仅VNC配置模式
vnc_only_mode() {
    local direct_access_choice="n"
    local failed_vnc_users=()
    local desktop_mode="auto"

    echo ""
    echo "=========================================="
    echo "         VNC密码配置"
    echo "=========================================="
    echo ""
    
    print_info "请输入用户名列表（用空格分隔）："
    read -r user_list
    
    if [ -z "$user_list" ]; then
        print_error "用户列表不能为空！"
        return
    fi
    
    print_info "请输入VNC密码："
    read -rs vnc_password
    echo ""
    
    if [ -z "$vnc_password" ]; then
        print_error "VNC密码不能为空！"
        return
    fi

    print_info "是否允许VNC客户端直接连接（RealVNC等）？(y/n) [默认: n，推荐SSH隧道]:"
    read -r direct_access_choice
    desktop_mode=$(choose_vnc_desktop_mode)
    
    echo ""
    print_info "开始配置VNC..."
    echo ""
    
    for username in $user_list; do
        if ! setup_vnc "$username" "$vnc_password" "$direct_access_choice" "$desktop_mode"; then
            failed_vnc_users+=("$username")
        fi
        echo ""
    done
    
    if [ ${#failed_vnc_users[@]} -gt 0 ]; then
        print_warning "以下用户的VNC配置失败："
        for username in "${failed_vnc_users[@]}"; do
            echo "  - $username"
        done
    else
        print_success "VNC配置完成！"
    fi
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
    echo "  4) 退出"
    echo ""
    echo "=========================================="
}

# 主函数
main() {
    while true; do
        show_menu
        print_info "请输入选项 (1-4):"
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
        print_info "按Enter键返回主菜单，或输入q退出..."
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
