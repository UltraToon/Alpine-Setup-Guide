#!/bin/sh
set -e

echo "Did you ^C out of the disk prompt in setup-alpine? If not, please reboot the medium. (yes/no)"
read -r response
[ "$response" = "yes" ] || exit

MOUNTPOINT="/mnt"
BTRFS_OPTS="rw,noatime,ssd,compress=zstd,space_cache=v2"
SUBVOLUMES="@ @home @var_log @snapshots" # Make directory creation follow this flexibly.

clear
echo "================================================================="
echo ">>> [Phase 1] Setting up partitions, btrfs, and system install..."
echo "================================================================="
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
    mkpart primary fat32 0% 300MiB \
    name 1 esp \
    set 1 esp on \
    mkpart primary btrfs 300MiB 100% \
    name 2 root

partprobe "$DISK"

# Partition Variable Setup
NVME_SUFFIX=$(case "$DISK" in /dev/nvme*) echo p ;; esac)
ESP_PAR="${DISK}${NVME_SUFFIX}1"
BTRFS_PAR="${DISK}${NVME_SUFFIX}2"


# Formatting
mkfs.fat -F 32 "$ESP_PAR"
mkfs.btrfs -f -q "$BTRFS_PAR"

# Subvolumes and Mounting
echo ">>> Creating snapper-style subvolume layout"
mount -t btrfs "$BTRFS_PAR" "$MOUNTPOINT"
for subvol in $SUBVOLUMES; do
    btrfs subvolume create "$MOUNTPOINT/$subvol"
done
btrfs subvolume set-default $MOUNTPOINT/@
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
echo "============================================================"
echo ">>> [Phase 2] System installed, setting up UKI and ZRAM..."
echo "============================================================"

chroot $MOUNTPOINT /bin/sh << EOF

mount -t proc proc /proc
mount -t devtmpfs dev /dev

# Run secureboot.conf setup before APK due to secureboot-hook running instantly.
mkdir -p /etc/kernel /etc/kernel-hooks.d
cat >/etc/kernel-hooks.d/secureboot.conf <<EOF1
cmdline="root=UUID=$(blkid "$BTRFS_PAR" | cut -d '"' -f 2) rootflags=subvol=@ rootfstype=btrfs modules=sd-mod,btrfs,nvme quiet ro"
signing_disabled=yes
output_dir="/boot/EFI/Linux"
output_name="alpine-linux-{flavor}.efi"
EOF1

apk add -q secureboot-hook gummiboot-efistub efibootmgr zram-init

echo ">>> Updating hooks and initramfs"
apk fix kernel-hooks
sed -i 's/features="\(.*\)"/features="\1 kms"/' /etc/mkinitfs/mkinitfs.conf
echo 'disable_trigger=yes' >> /etc/mkinitfs/mkinitfs.conf

echo ">>> Creating boot entry"
efibootmgr --disk "$DISK" --part 1 --create --label 'Alpine Linux' --load /EFI/Linux/alpine-linux-edge.efi --verbose

echo ">>> Setting up zram"
rc-update add zram-init
cat >/etc/conf.d/zram-init <<EOF2
load_on_start=yes
unload_on_stop=yes
num_devices=1
type0=swap
size0=8192
maxs0=1 # maximum number of parallel processes for this device
algo0=lzo-rle # zstd (since linux-4.18), lz4 (since linux-3.15), or lzo.
labl0=zram_swap # the label name
EOF2

EOF

echo ""
echo " ########################################"
echo " # >>> Script completed, please reboot. #"
echo " ########################################"
echo ""