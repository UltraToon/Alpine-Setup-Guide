Gaming KVM  
DWL  
Distrobox setup [flatpak too]  
Zellij with foot/ghostty  

I dont really plan this for public use, just for personal.

**BTRFS has asychronous discard (trim) default on kernel 6.2, use FITRIM periodic with chrontab for XFS SSD**

ONLY SUPPORTS INTEL CPU, GPT, SCSI/NVME SETUPS.

https://gist.github.com/QaidVoid/d83fa164e3534b816288d53ef3262c88  
https://it-notes.dragas.net/2021/11/03/alpine-linux-and-lxd-perfect-setup-part-1-btrfs-file-system/  
https://wiki.alpinelinux.org/wiki/Installation  
https://wiki.alpinelinux.org/wiki/Zram  


Sooo I dont know what I am doing, theres literally no point for this, i just wasted a week on this. Bruh.

# Install Process
1. Run `setup-alpine`
   - When prompted for APK repo, make sure to **enable community repos** then **find fastest mirror** (C+F)
   - When prompted for disk configuration, press **^C**.
6. Run `wget https://raw.githubusercontent.com/UltraToon/Alpine-Setup-Guide/refs/heads/main/alpine_script.sh && chmod +x alpine_script.sh`

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
