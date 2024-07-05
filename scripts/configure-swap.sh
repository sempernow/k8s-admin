#!/usr/bin/env bash
########################################################
# Disable all swaps 
# - Idempotent.
########################################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "⚠️  ERR : MUST run as root" >&2

    exit 11
}

[[ $(cat /proc/swaps |grep -v Filename) ]] ||
    exit 0

## Disable swap now and forever : required by kubelet
## To find a particular swap, use lsblk 
swapoff -a  # Disable all swaps of /proc/swaps
## #############################################
## >>>  DO NOT disable swap.target (static)  <<<
## #############################################
## Comment out any swap entries of /etc/fstab (once)
## /etc/fstab : unconfigured example 
    ## /dev/mapper/almalinux-root                /          xfs     defaults                   0 0
    ## UUID=0ef0e28d-a54d-4cd6-b7f8-f55b5ca9ae03 /boot      xfs     defaults                   0 0
    ## UUID=B872-847F                            /boot/efi  vfat    umask=0077,shortname=winnt 0 2
    ## /dev/mapper/almalinux-swap                none       swap    defaults                   0 0

# Mod /etc/fstab only if swap-device mount is active (not commented out).
swap_mounted="$(cat /etc/fstab |grep ' swap' |grep -v '^ *#' |awk '{print $1}')"
[[ $swap_mounted ]] && {
    device="$(echo $swap_mounted |awk '{print $1}')"
    sed -i "s,$device,#$device," /etc/fstab
} 

#sudo swapon --show
cat /etc/fstab |grep swap
systemctl daemon-reload
