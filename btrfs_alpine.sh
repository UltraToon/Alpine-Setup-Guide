#!/bin/sh
set -e
clear
MOUNTPOINT="/mnt"
BTRFS_OPTS="defaults,ssd,noatime,space_cache=v2"

echo "[> Setting up... <]"
apk add -q parted btrfs-progs

echo "=========================="
lsblk -nrpo NAME,FSTYPE | awk '$2 == "" {print $1}'
echo "=========================="
echo "Enter the disk to use (e.g., /dev/XXX):"
read -r DISK

#compress=zstd also need to install zstd pkg

#ROOTFS=btrfs BOOTFS=vfat BOOTLOADER=grub DISKLABEL=gpt DISKDEV=$DISK && #setup-disk -s 0 -m sys /mnt

parted --script -a optimal "$DISK" \
    mklabel gpt \
    mkpart primary fat32 0% 200M \
    name 1 esp \
    set 1 esp on \
    mkpart primary btrfs 200M 100% \
    name 2 root


PART_SUFFIX=$(case "$DISK" in /dev/nvme*) echo p ;; esac)
ESP_PAR="${DISK}${PART_SUFFIX}1"
BTRFS_PAR="${DISK}${PART_SUFFIX}2"

# BTRFS SECTION
modprobe btrfs
mkfs.btrfs -f -q "$BTRFS_PAR"

echo "[> Mounting $BTRFS_PAR to $MOUNTPOINT for subvolume creation <]"
mount -t btrfs "$BTRFS_PAR" "$MOUNTPOINT"
SUBVOLUMES="@ @home @var_log @snapshots"
for subvol in $SUBVOLUMES; do
    echo "[> Creating subvolume: $subvol <]"
    btrfs subvolume create "$MOUNTPOINT/$subvol"
done
umount "$MOUNTPOINT"

echo "Unmounted $MOUNTPOINT and preparing subvolume mounts"
mkdir -p "$MOUNTPOINT/home" "$MOUNTPOINT/var/log" "$MOUNTPOINT/.snapshots"
mount -o subvol=@,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT"
mount -o subvol=@home,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT/home"
mount -o subvol=@var_log,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT/var/log"
mount -o subvol=@snapshots,$BTRFS_OPTS "$BTRFS_PAR" "$MOUNTPOINT/.snapshots"

# EFI SECTION
mkfs.vfat -F32 "$ESP_PAR"
mkdir -p /mnt/boot
mount -t vfat "$ESP_PAR" /mnt/boot

DISKDEV=$DISK setup-disk -m sys /mnt

echo "${GREEN}Script completed, please reboot.${RESET}"

## setup fstab
## add chroot steps for zram, microcode, and basics