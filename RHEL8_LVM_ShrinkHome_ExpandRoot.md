完整且安全的操作指南如下，包含所有命令、每步目的、以及最后的退出与重启步骤。
目标：把 `/home` 的 856 G 缩成约 256 G，把 600 G 加到 `/`。

---

## **0️⃣ 变更前检查**

**目的：确认文件系统类型与当前容量、估算备份空间**

```bash
df -Th                # 看 / 与 /home 是否是 xfs，确认使用量
vgs; lvs              # 记录 VG/LV 名称和大小（rhel/root、rhel/home）
du -sh /home          # 估算 /home 实际数据量（便于备份）
```

---

## **1️⃣ 进入救援模式**

**目的：让 /home 不被占用，确保能安全删除重建 LV**

```bash
systemctl isolate rescue.target    # 或 systemctl rescue
# 进入后用 root 登录
```

---

## **2️⃣ 备份 /home 数据**

**目的：XFS 不能缩小，只能删 LV，必须先完整备份数据**

```bash
mkdir -p /mnt/backup_home
# 假设 /dev/nvme1n1p1 是你用来备份的盘
mount /dev/nvme1n1p1 /mnt/backup_home
rsync -aHAX /home/ /mnt/backup_home/
```

> `-aHAX`：保留权限、ACL、扩展属性和硬链接。
> 若无外盘，请暂时备份到另一块 NVMe 或网络路径。

---

## **3️⃣ 卸载并停用 /home**

**目的：释放 LV，避免任何进程占用**

```bash
fuser -km /home || true
umount /home
# 注释掉 /etc/fstab 中的 /home 挂载行，防止重启自动挂载旧卷
sed -i.bak '/[[:space:]]\/home[[:space:]]/ s/^/#/' /etc/fstab
```

---

## **4️⃣ 删除旧 /home LV**

**目的：将 856 G 空间释放回 VG**

```bash
lvremove -y /dev/rhel/home
```

---

## **5️⃣ 扩 root LV 600 G**

**目的：将 600 G 分配给根卷（70 G → 670 G）**

```bash
lvextend -L +600G /dev/rhel/root
xfs_growfs /
```

> `lvextend` 改变 LV 大小；`xfs_growfs` 扩文件系统本身。

---

## **6️⃣ 重建新的 /home**

**目的：用剩余的约 256 G 重建新的 /home LV**

```bash
lvcreate -n home -l 100%FREE rhel
mkfs.xfs -f /dev/rhel/home
mkdir -p /home
echo '/dev/rhel/home  /home  xfs  defaults  0 0' >> /etc/fstab
mount -a
```

---

## **7️⃣ 恢复数据并修复权限/SELinux**

**目的：恢复用户数据，修复登录权限**

```bash
rsync -aHAX /mnt/backup_home/ /home/
chmod 755 /home
chown -R mini_bicasl:mini_bicasl /home/mini_bicasl
restorecon -Rv /home        # 修复 SELinux 上下文
```

---

## **8️⃣ 验证结果**

**目的：确认调整成功**

```bash
df -Th         # / ≈ 670 G；/home ≈ 256 G
lvs            # 查看 LV 大小是否符合预期
```

---

## **9️⃣ 退出救援并重启（可选但推荐）**

**目的：让系统重新加载新 LVM/FSTAB 配置**

```bash
exit      # 退出 rescue 回到多用户模式
reboot    # 重启系统加载新配置
```

---

### ✅ **完成后**

系统启动后：

```bash
df -Th
lvs
ls -ld /home/mini_bicasl
```

确认：

* `/` 约 670 G，`/home` 约 256 G；
* `/home/mini_bicasl` 存在；
* 用户能正常登录图形界面。

---

> ⚠️ 关键安全点：
>
> * 所有操作都在 **rescue 模式** 下执行；
> * XFS 只能变大，不能缩小；
> * 任何误删都可通过第 2 步的备份恢复。
