Gaming KVM  
DWL  
Distrobox setup [flatpak too]  
Custom Kernel
Zellij with foot/ghostty  
EFIBOOTMGR
**BTRFS has asychronous discard (trim) default on kernel 6.2, use FITRIM periodic with chrontab for XFS SSD**

https://gist.github.com/QaidVoid/d83fa164e3534b816288d53ef3262c88  
https://it-notes.dragas.net/2021/11/03/alpine-linux-and-lxd-perfect-setup-part-1-btrfs-file-system/  
https://wiki.alpinelinux.org/wiki/Installation  
https://wiki.alpinelinux.org/wiki/Zram  

# Install Process
1. Run `setup-alpine`, when prompted for disk configuration, press **^C**.
2. `export ROOTFS=btrfs BOOTFS=vfat BOOTLOADER=grub DISKLABEL=gpt && setup-disk -s 0 -v -m sys` **512GB SSD**
3. `BTRFS_OPTS="defaults,noatime,compress=zstd,space_cache=v2"`
4. `mount -o $BTRFS_OPTS /dev/XXX /mnt` **512GB SSD**
5. sed -i 's/\r//' file.text
```
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@snapshots
umount /mnt
```
5. 

## Setting up secondary SSD for KVM.  
3. `apk add xfsprogs cfdisk`
4. Use cfdisk to create one **Linux filesystem** partition for 1tb SSD, format with `mkfs.xfs /dev/XXX`
5. Create a `/kvm` directory and mount the 1tb SSD, `mount /dev/XXX /kvm`
6. `blkid >> /etc/fstab` then edit correspondingly

> Mount / FSTAB Options
`defaults,noatime,compress=zstd,space_cache=v2`
Dont use space cache for the XFS ssd.

# Post Install
1. Setup zram: https://wiki.alpinelinux.org/wiki/Zram  
