#!/bin/sh
set -e
MOUNTPOINT="/mnt"
BTRFS_OPTS="defaults,ssd,noatime,space_cache=v2"

echo ">>> Setting up..."
apk add -q parted btrfs-progs dosfstools
umount /mnt
modprobe btrfs
clear

echo "=========================="
fdisk -l 2>/dev/null | grep "Disk \/" | grep -v "\/dev\/md" | awk '{print $2}' | sed -e 's/://g'
echo "=========================="
echo ">>> Enter the disk to use (e.g., /dev/XXX):"
read -r DISK

#compress=zstd also need to install zstd pkg

#ROOTFS=btrfs BOOTFS=vfat BOOTLOADER=grub DISKLABEL=gpt DISKDEV=$DISK && #setup-disk -s 0 -m sys /mnt

# Partitioning
parted --script -a optimal "$DISK" \
    mklabel gpt \
    mkpart primary fat32 0% 200M \
    name 1 esp \
    set 1 esp on \
    mkpart primary btrfs 200M 100% \
    name 2 root

partprobe $DISK

# Partition Variable Setup
NVME_SUFFIX=$(case "$DISK" in /dev/nvme*) echo p ;; esac)
ESP_PAR="${DISK}${NVME_SUFFIX}1"
BTRFS_PAR="${DISK}${NVME_SUFFIX}2"

# Filesystem Format
mkfs.vfat -n BOOT -F 32 "$ESP_PAR"
mkfs.btrfs -L alpine -f -q "$BTRFS_PAR"

# EFI SECTION
mkdir -p /mnt/boot
mount -t vfat "$ESP_PAR" /mnt/boot

# BTRFS SECTION
echo ">>> Mounting $BTRFS_PAR to $MOUNTPOINT for subvolume creation"
mount -t btrfs "$BTRFS_PAR" "$MOUNTPOINT"
SUBVOLUMES="@ @home @var_log @snapshots"
for subvol in $SUBVOLUMES; do
    btrfs subvolume create "$MOUNTPOINT/$subvol"
done
umount "$MOUNTPOINT"

echo ">>> Unmounted $MOUNTPOINT and preparing subvolume mounts"
mount -o subvol=@,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT"
mkdir -p "$MOUNTPOINT/home" "$MOUNTPOINT/var/log" "$MOUNTPOINT/.snapshots"
mount -o subvol=@home,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT/home"
mount -o subvol=@var_log,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT/var/log"
mount -o subvol=@snapshots,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT/.snapshots"

DISKDEV=$DISK setup-disk -m sys /mnt

echo "${GREEN}Script completed, please reboot.${RESET}"

## setup fstab
## add chroot steps for zram, microcode, and basics