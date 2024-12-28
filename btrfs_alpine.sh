#!/bin/sh
set -e
clear
GREEN="\033[1;32m"
RESET="\033[0m"
MOUNTPOINT="/mnt"
BTRFS_OPTS="defaults,ssd,noatime,space_cache=v2"

echo "${GREEN}Enter the disk to use (e.g., /dev/XXX):${RESET}"
read -r DISK

#compress=zstd also need to install zstd pkg

#ROOTFS=btrfs BOOTFS=vfat BOOTLOADER=grub DISKLABEL=gpt DISKDEV=$DISK && #setup-disk -s 0 -m sys /mnt

apk add -q parted btrfs-progs lsblk
parted --script -a optimal "$DISK" \
    mklabel gpt \
    mkpart primary fat32 0% 200M \
    name 1 esp \
    set 1 esp on \
    mkpart primary btrfs 200M 100% \
    name 2 root

ESP_PAR=$(lsblk -nrpo NAME,FSTYPE "$DISK" | awk '$2 == "vfat" {print $1}')
BTRFS_PAR=$(lsblk -nrpo NAME,FSTYPE "$DISK" | awk '$2 == "btrfs" {print $1}')

# BTRFS SECTION
modprobe btrfs
mkfs.btrfs -f -q "$BTRFS_PAR"

echo "Mounting $BTRFS_PAR to $MOUNTPOINT for subvolume creation"
mount -t btrfs "$BTRFS_PAR" "$MOUNTPOINT"
SUBVOLUMES="@ @home @var_log @snapshots"
for subvol in $SUBVOLUMES; do
    echo "${GREEN}Creating subvolume: [ $subvol ]${RESET}"
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