#!/bin/sh
set -e
MOUNTPOINT="/mnt"
BTRFS_OPTS="rw,noatime,ssd,compress=zstd,space_cache=v2"

echo ">>> Setting up..."
sed -i 's|alpine/[^/]\+|alpine/edge|g' "/etc/apk/repositories"
apk update -q
apk add -q parted btrfs-progs dosfstools zstd
umount "$MOUNTPOINT" 2>/dev/null || true
modprobe btrfs
clear

echo "=========================="
fdisk -l 2>/dev/null | grep "Disk \/" | grep -v "\/dev\/md" | awk '{print $2}' | sed -e 's/://g'
echo "=========================="
echo ">>> Enter the disk to use (e.g., /dev/XXX):"
read -r DISK

# Partitioning
parted --script -a optimal "$DISK" \
    mklabel gpt \
    mkpart primary fat32 1MiB 513MiB \
    name 1 esp \
    set 1 esp on \
    mkpart primary btrfs 513MiB 100% \
    name 2 root
#    mklabel gpt \
#    mkpart primary fat32 0% 512M \
#    name 1 esp \
#    set 1 esp on \
#    mkpart primary btrfs 512M 100% \
#    name 2 root


partprobe "$DISK"

# Partition Variable Setup
NVME_SUFFIX=$(case "$DISK" in /dev/nvme*) echo p ;; esac)
ESP_PAR="${DISK}${NVME_SUFFIX}1"
BTRFS_PAR="${DISK}${NVME_SUFFIX}2"


# Formatting
mkfs.fat -F 32 "$ESP_PAR"
mkfs.btrfs -f -q "$BTRFS_PAR"

# Subvolumes and Mounting
echo ">>> Creating snapper-style subvolume layouts"
mount -t btrfs "$BTRFS_PAR" "$MOUNTPOINT"
SUBVOLUMES="@ @home @var_log @snapshots"
for subvol in $SUBVOLUMES; do
    btrfs subvolume create "$MOUNTPOINT/$subvol"
done
btrfs subvolume set-default /mnt/@
umount "$MOUNTPOINT"
echo ">>> Unmounted $MOUNTPOINT and preparing subvolume mounts"
mount -o subvol=@,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT"
mkdir -p "$MOUNTPOINT/home" "$MOUNTPOINT/var/log" "$MOUNTPOINT/.snapshots" "$MOUNTPOINT/boot"
mount "$BTRFS_PAR" -o subvol=@home,$BTRFS_OPTS  "$MOUNTPOINT/home"
mount "$BTRFS_PAR" -o subvol=@var_log,$BTRFS_OPTS "$MOUNTPOINT/var/log"
mount "$BTRFS_PAR" -o subvol=@snapshots,$BTRFS_OPTS  "$MOUNTPOINT/.snapshots"
mount "$ESP_PAR" -t vfat  /mnt/boot

BOOTLOADER=none setup-disk -k edge -m sys /mnt

clear
echo ">>> Script completed, please reboot."

## setup fstab
## add chroot steps for zram, microcode, and basics