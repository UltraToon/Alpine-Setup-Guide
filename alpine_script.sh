#!/bin/sh
# shellcheck disable=SC3040
set -euo pipefail

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
mount "$ESP_PAR" -t vfat  $MOUNTPOINT/boot

BOOTLOADER=none setup-disk -m sys $MOUNTPOINT

clear
echo "============================================================================="
echo ">>> [Phase 2] Chrooting to setup auto UKI [hook+image], ZRAM, and graphics..."
echo "============================================================================="

# Modified alpine chroot
MOUNTED=
umount_all() {
  case $MOUNTED in
  shm\ *) if [ -L ./dev/shm ]; then
            umount ./"$(readlink ./dev/shm)"
          else
            umount ./dev/shm
          fi
          MOUNTED=${MOUNTED#shm };;
  esac
  case $MOUNTED in
  run\ *) umount ./run
          MOUNTED=${MOUNTED#run };;
  esac
  case $MOUNTED in
  tmp\ *) umount ./tmp
          MOUNTED=${MOUNTED#tmp };;
  esac
  case $MOUNTED in
  proc\ *) umount ./proc
          MOUNTED=${MOUNTED#proc };;
  esac
  case $MOUNTED in
  sys\ *) umount ./sys
          MOUNTED=${MOUNTED#sys };;
  esac
  case $MOUNTED in
  pts\ *) umount ./dev/pts
          MOUNTED=${MOUNTED#pts };;
  esac
  case $MOUNTED in
  dev\ *) umount ./dev
          MOUNTED=${MOUNTED#dev };;
  esac

  echo ">>> Unmounted chroot directories, finalizing..."
}
trap 'umount_all' EXIT

mkdir -p ./etc ./dev/pts ./sys ./proc ./tmp ./run ./boot ./root
cp -fL /etc/resolv.conf ./etc/

mount --bind /dev ./dev
MOUNTED="dev $MOUNTED"

mount -t devpts devpts ./dev/pts -o nosuid,noexec
MOUNTED="pts $MOUNTED"

mount -t sysfs sys ./sys -o nosuid,nodev,noexec,ro
MOUNTED="sys $MOUNTED"

mount -t proc proc ./proc -o nosuid,nodev,noexec
MOUNTED="proc $MOUNTED"

mount -t tmpfs tmp ./tmp -o mode=1777,nosuid,nodev,strictatime
MOUNTED="tmp $MOUNTED"
mount -t tmpfs run ./run -o mode=0755,nosuid,nodev
MOUNTED="run $MOUNTED"
if [ -L ./dev/shm ]; then
  mkdir -p ./"$(readlink ./dev/shm)"
  mount -t tmpfs shm ./"$(readlink ./dev/shm)" -o mode=1777,nosuid,nodev
else
  #mkdir -p ./dev/shm
  mount -t tmpfs shm ./dev/shm -o mode=1777,nosuid,nodev
fi
MOUNTED="shm $MOUNTED"

chroot $MOUNTPOINT /usr/bin/env -i SHELL=/bin/sh HOME=/root TERM="$TERM" \
  PATH=/usr/sbin:/usr/bin:/sbin:/bin /bin/sh << EOF

echo ">>> Updating APK repositories..."
sed -i 's|alpine/[^/]\+|alpine/edge|g' "/etc/apk/repositories"
apk update -q
apk add -q binutils gummiboot-efistub efibootmgr zram-init intel-ucode kernel-hooks

echo ">>> Creating kernel hooks [UKI generation]"
cat >/etc/kernel-hooks.d/50-updateUKI.hook <<EOF1
if [ $# -lt 2 ]; then
    echo ">>ERROR DETECTED" >&2 # TEMPORARY
    exit 1
fi
readonly FLAVOR=$1
readonly NEW_VERSION=$2
output_name="alpine-$NEW_VERSION-$FLAVOR.efi"
[ "$NEW_VERSION" ] || exit 0

">>> Backing up"
rm -rf /boot/EFI/*.bak
cp -af "/boot/EFI/$output_name" "/boot/EFI$output_name.bak" # Ignore shellcheck problem

echo ">>> Creating unified initramfs...
sed -i 's/features="\(.*\)"/features="\1 kms"/' /etc/mkinitfs/mkinitfs.conf
echo 'disable_trigger=yes' >> /etc/mkinitfs/mkinitfs.conf
tmpdir=$(mktemp -dt "updateUKI.XXXXXX")
trap "rm -f '$tmpdir'/*; rmdir '$tmpdir'" EXIT HUP INT TERM # ignore shellcheck problem
/sbin/mkinitfs -o "$tmpdir"/initramfs "$NEW_VERSION-$FLAVOR"
cat /boot/intel-ucode.img $tmpdir/initramfs > $tmpdir/initramfs

echo ">>> Creating UKI...
objcopy \
	--add-section .osrel="/etc/os-release" --change-section-vma .osrel=0x20000 \
	--add-section .cmdline="root=UUID=$(blkid | grep btrfs | awk -F '"' '{print $2}') rootflags=subvol=@ rootfstype=btrfs zswap.enabled=0 modules=sd-mod,btrfs,nvme quiet ro" --change-section-vma .cmdline=0x30000 \
	--add-section .linux="/boot/vmlinuz-$FLAVOR" --change-section-vma .linux=0x40000 \
	--add-section .initrd="$tmpdir/initramfs --change-section-vma .initrd=0x3000000 \
	"/usr/lib/gummiboot/linuxx64.efi.stub" "/boot/EFI/$output_name"

echo ">>> Creating EFI boot entry..."
efibootmgr --disk "$(busybox fdisk -l | grep "^Disk /dev" | cut -d' ' -f2 | tr -d ':')" --part 1 --create --label 'Alpine Linux ($FLAVOR)' --load /EFI/$output_name --verbose
EOF1

apk fix kernel-hooks
apk add linux-edge
apk del linux-lts

echo ">>> Setting up zram"
rc-update add zram-init
cat >/etc/conf.d/zram-init <<EOF2
load_on_start=yes
unload_on_stop=yes
num_devices=1
type0=swap
size0=$(free -m | awk '/Mem:/ {print int($2/2)}')
maxs0=1 # maximum number of parallel processes for this device
algo0=lzo-rle # zstd (since linux-4.18), lz4 (since linux-3.15), or lzo.
labl0=zram_swap # the label name
EOF2

echo ">>> Setting up AMD graphics"

EOF

echo ""
echo " ########################################"
echo " # >>> Script completed, please reboot. #"
echo " ########################################"
echo ""


# Experimental aligned partitions, I dont understand and this isnt required as of now.

#align="$(objdump -p /usr/lib/gummiboot/linuxx64.efi.stub | awk '{ if ($1 == "SectionAlignment"){print $2} }')"
#align="$(echo "ibase=16; $1" | bc)"
#osrel_offs="$(objdump -h "/usr/lib/gummiboot/linuxx64.efi.stub" | awk 'NF==7 {size=strtonum("0x"$3); offset=strtonum("0x"$4)} END {print size + offset}')"
#osrel_offs=$((osrel_offs + "$align" - osrel_offs % "$align"))
#cmdline_offs=$((osrel_offs + $(stat -Lc%s "/usr/lib/os-release")))
#cmdline_offs=$((cmdline_offs + "$align" - cmdline_offs % "$align"))
#initrd_offs=$((initrd_offs + "$align" - initrd_offs % "$align"))
#linux_offs=$((initrd_offs + $(stat -Lc%s "initrd-file")))
#linux_offs=$((linux_offs + "$align" - linux_offs % "$align"))
#
#objcopy \
#	--add-section .osrel="/usr/lib/os-release" --change-section-vma .osrel=$(printf 0x%x "$osrel_offs") \
#	--add-section .cmdline="/etc/kernel/cmdline" --change-section-vma .cmdline=$(printf 0x%x "$cmdline_offs") \
#	--add-section .linux="/boot/vmlinuz-edge" --change-section-vma .linux=$(printf 0x%x "$linux_offs") \
#	--add-section .initrd="/tmp/initramfs-edge" --change-section-vma .initrd=$(printf 0x%x "$initrd_offs") \
#	/usr/lib/gummiboot/linuxx64.efi.stub /boot/EFI/alpine.efi