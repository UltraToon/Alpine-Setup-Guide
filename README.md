> Temp Notes
Alpine Linux Setup  
Gaming KVM  
DWL  
Distrobox setup [flatpak too]  
Custom Kernel  
XFS/BTRFS file system  
ZRAM  
Zellij with foot/ghostty  
EFIBOOTMGR
Trim with chrony?

*use GPT partitioning tools like gdisk., etc)
https://gist.github.com/QaidVoid/d83fa164e3534b816288d53ef3262c88
https://it-notes.dragas.net/2021/11/03/alpine-linux-and-lxd-perfect-setup-part-1-btrfs-file-system/
https://wiki.alpinelinux.org/wiki/Installation

# Install Process
1. Run through setup alpine, and then ^C the disk prompt.
2. Run `export ROOTFS=btrfs BOOTFS=vfat BOOTLOADER=grub && setup-disk -s 0 -v`
