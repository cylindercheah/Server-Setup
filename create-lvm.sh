#!/bin/bash

# LVM创建脚本 - 简化版
# 功能：创建LVM卷组和逻辑卷，支持自定义挂载目录

# ---------------------------- 配置参数 ----------------------------
VG_PREFIX="vg_"  # 卷组前缀
LV_NAME="data_lv"
FS_TYPE="xfs"  # 支持xfs或ext4
CONFIRM_DESTRUCTIVE=true  # 是否需要确认破坏性操作
# -----------------------------------------------------------------

# 日志输出函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] [$level] $message"
}

# 错误处理函数
handle_error() {
    local message="$1"
    local command="${2:-}"
    local output="${3:-}"
    log "错误" "$message"
    if [ -n "$command" ]; then
        log "错误" "执行命令: $command"
    fi
    if [ -n "$output" ]; then
        log "错误" "命令输出: $output"
    fi
    exit 1
}

# 确认函数
confirm() {
    if [ "$CONFIRM_DESTRUCTIVE" = true ]; then
        read -p "$1 (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "信息" "用户取消操作"
            exit 0
        fi
    fi
}

# 获取可用硬盘列表
list_available_disks() {
    log "信息" "扫描可用硬盘..."
    local disks=()
    
    # 获取所有块设备（排除系统盘和分区）
    while IFS= read -r device; do
        if [[ $device =~ /dev/(sd[a-z]|nvme[0-9]+n[0-9]+)$ ]] && [ -b "$device" ]; then
            # 检查是否为系统盘（通常包含系统分区）
            local is_system_disk=false
            if lsblk "$device" 2>/dev/null | grep -q "/boot\|/ \|/home"; then
                is_system_disk=true
            fi
            
            if [ "$is_system_disk" = false ]; then
                local size=$(lsblk -ndo SIZE "$device" 2>/dev/null)
                local model=$(lsblk -dno MODEL "$device" 2>/dev/null | head -1)
                disks+=("$device|$size|$model")
            fi
        fi
    done < <(lsblk -ndo NAME | grep -E "^(sd[a-z]|nvme[0-9]+n[0-9]+)$" | sed 's|^|/dev/|')
    
    echo "${disks[@]}"
}

# 选择硬盘和挂载目录
setup_configuration() {
    local disks_info=($(list_available_disks))
    
    if [ ${#disks_info[@]} -eq 0 ]; then
        handle_error "未找到可用的硬盘设备"
    fi
    
    echo
    log "信息" "可用硬盘列表:"
    echo "=========================================="
    printf "%-3s %-12s %-10s %-20s\n" "编号" "设备" "大小" "型号"
    echo "------------------------------------------"
    
    local index=1
    declare -A disk_map
    
    for disk_info in "${disks_info[@]}"; do
        IFS='|' read -r device size model <<< "$disk_info"
        printf "%-3d %-12s %-10s %-20s\n" "$index" "$device" "$size" "$model"
        disk_map["$index"]="$device"
        ((index++))
    done
    
    echo "=========================================="
    echo
    
    # 选择硬盘
    read -p "请选择要使用的硬盘编号（多个编号用逗号分隔，如: 1,3 或输入 all 选择全部）: " selection
    
    local selected_devices=()
    
    if [[ $selection =~ ^[Aa][Ll][Ll]$ ]]; then
        # 选择所有硬盘
        for disk_info in "${disks_info[@]}"; do
            IFS='|' read -r device size model <<< "$disk_info"
            selected_devices+=("$device")
        done
    else
        # 解析用户选择的编号
        IFS=',' read -ra indices <<< "$selection"
        for idx in "${indices[@]}"; do
            idx=$(echo "$idx" | tr -d '[:space:]')
            if [[ $idx =~ ^[0-9]+$ ]] && [ $idx -ge 1 ] && [ $idx -le ${#disks_info[@]} ]; then
                selected_devices+=("${disk_map[$idx]}")
            else
                handle_error "无效的编号: $idx (有效范围: 1-${#disks_info[@]})"
            fi
        done
    fi
    
    if [ ${#selected_devices[@]} -eq 0 ]; then
        handle_error "未选择任何硬盘"
    fi
    
    # 选择挂载目录
    echo
    read -p "请输入挂载目录（默认: /data）: " mount_point
    MOUNT_POINT="${mount_point:-/data}"
    
    # 生成卷组名称
    VG_NAME="${VG_PREFIX}$(date +%s)"
    
    VALID_DEVICES=("${selected_devices[@]}")
    
    log "信息" "选择的硬盘: ${VALID_DEVICES[*]}"
    log "信息" "挂载目录: $MOUNT_POINT"
    log "信息" "卷组名称: $VG_NAME"
}

# 预处理硬盘
prepare_disk() {
    local device="$1"
    
    # 检查是否被挂载
    if mount | grep -q "^$device"; then
        log "信息" "卸载 $device"
        umount -lf "$device" || handle_error "无法卸载 $device"
    fi
    
    # 检查是否被LVM使用
    if pvs "$device" &>/dev/null; then
        log "信息" "从LVM中移除 $device"
        vgreduce --removemissing "$VG_NAME" &>/dev/null
        pvremove -ff "$device" || handle_error "无法移除物理卷 $device"
    fi
    
    # 检查是否被RAID使用
    if mdadm --detail "$device" &>/dev/null; then
        log "信息" "停止RAID设备 $device"
        mdadm --stop "$device" || true
        mdadm --zero-superblock "$device" || true
    fi
    
    # 擦除磁盘签名
    log "信息" "擦除 $device 的签名"
    wipefs -a "$device" || handle_error "无法擦除 $device 的签名"
}

# 创建物理卷
create_physical_volume() {
    local device="$1"
    
    prepare_disk "$device"
    
    if ! pvs "$device" > /dev/null 2>&1; then
        log "信息" "创建物理卷 $device"
        local output
        output=$(pvcreate -ff "$device" 2>&1)
        if [ $? -ne 0 ]; then
            handle_error "无法创建物理卷 $device" "pvcreate -ff $device" "$output"
        fi
    fi
}

# 创建卷组
create_volume_group() {
    if vgdisplay "$VG_NAME" > /dev/null 2>&1; then
        log "信息" "卷组 $VG_NAME 已存在，跳过创建"
        return 0
    fi
    
    log "信息" "创建卷组 $VG_NAME"
    local output
    output=$(vgcreate "$VG_NAME" "${VALID_DEVICES[@]}" 2>&1)
    if [ $? -ne 0 ]; then
        handle_error "无法创建卷组 $VG_NAME" "vgcreate $VG_NAME ${VALID_DEVICES[*]}" "$output"
    fi
}

# 创建逻辑卷
create_logical_volume() {
    local lv_path="/dev/$VG_NAME/$LV_NAME"
    if ! lvdisplay "$lv_path" > /dev/null 2>&1; then
        log "信息" "创建逻辑卷 $LV_NAME"
        local output
        output=$(lvcreate -l 100%FREE -n "$LV_NAME" "$VG_NAME" 2>&1)
        if [ $? -ne 0 ]; then
            handle_error "无法创建逻辑卷 $LV_NAME" "lvcreate -l 100%FREE -n $LV_NAME $VG_NAME" "$output"
        fi
    fi
}

# 创建文件系统
create_filesystem() {
    local lv_path="/dev/$VG_NAME/$LV_NAME"
    local fs_exists=$(blkid -o value -s TYPE "$lv_path" 2>/dev/null)
    
    if [ -z "$fs_exists" ]; then
        log "信息" "在 $lv_path 上创建 $FS_TYPE 文件系统"
        local output
        case "$FS_TYPE" in
            xfs)
                output=$(mkfs.xfs -f "$lv_path" 2>&1)
                ;;
            ext4)
                output=$(mkfs.ext4 -F "$lv_path" 2>&1)
                ;;
            *)
                handle_error "不支持的文件系统类型: $FS_TYPE"
                ;;
        esac
        
        if [ $? -ne 0 ]; then
            handle_error "无法创建文件系统" "mkfs.$FS_TYPE $lv_path" "$output"
        fi
    fi
}

# 设置挂载
setup_mount() {
    # 创建挂载点
    if [ ! -d "$MOUNT_POINT" ]; then
        log "信息" "创建挂载点 $MOUNT_POINT"
        mkdir -p "$MOUNT_POINT" || handle_error "无法创建挂载点 $MOUNT_POINT"
    fi
    
    # 添加fstab条目
    local lv_path="/dev/$VG_NAME/$LV_NAME"
    local uuid=$(blkid -o value -s UUID "$lv_path")
    
    if [ -z "$uuid" ]; then
        handle_error "无法获取 $lv_path 的UUID"
    fi
    
    if ! grep -q "^UUID=$uuid" /etc/fstab; then
        log "信息" "添加fstab条目"
        echo "UUID=$uuid $MOUNT_POINT $FS_TYPE defaults,noatime 0 0" >> /etc/fstab || handle_error "无法更新fstab"
    fi
    
    # 挂载
    if ! mountpoint -q "$MOUNT_POINT"; then
        log "信息" "挂载 $MOUNT_POINT"
        mount "$MOUNT_POINT" || handle_error "无法挂载 $MOUNT_POINT"
    fi
}

# 主程序
main() {
    log "信息" "开始LVM配置"
    
    # 设置配置
    setup_configuration
    
    # 确认操作
    confirm "此操作将格式化所选硬盘并创建LVM，是否继续？"
    
    # 创建物理卷
    log "信息" "开始创建物理卷"
    for device in "${VALID_DEVICES[@]}"; do
        create_physical_volume "$device"
    done
    
    # 创建卷组
    create_volume_group
    
    # 创建逻辑卷
    create_logical_volume
    
    # 创建文件系统
    create_filesystem
    
    # 设置挂载
    setup_mount
    
    # 显示结果
    log "信息" "LVM配置完成"
    echo
    log "信息" "卷组信息:"
    vgdisplay "$VG_NAME"
    echo
    log "信息" "逻辑卷信息:"
    lvdisplay "/dev/$VG_NAME/$LV_NAME"
    echo
    log "信息" "挂载信息:"
    df -h "$MOUNT_POINT"
    echo
    log "信息" "挂载目录: $MOUNT_POINT"
    log "信息" "卷组名称: $VG_NAME"
    log "信息" "逻辑卷路径: /dev/$VG_NAME/$LV_NAME"
}

# 捕获中断信号
trap 'handle_error "脚本被中断。"' SIGINT SIGTERM

# 运行主程序
main
