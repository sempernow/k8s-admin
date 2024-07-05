#!/usr/bin/env bash
###################################
# Each must be unique per cluster
###################################
hostname
sudo cat /sys/class/dmi/id/product_uuid
ip -color=never -brief link show dev eth0 |awk '{print $3}'

