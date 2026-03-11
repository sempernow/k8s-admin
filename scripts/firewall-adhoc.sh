#!/usr/bin/env bash
[[ "$(id -u)" -ne 0 ]] && {
    echo "❌️  ERR : MUST run as root" >&2

    exit 11
}
firewall-cmd --permanent --zone=k8s-external \
    --remove-rich-rule='rule family=ipv4 destination address="224.0.0.0/4" accept'

firewwall-cmd --reload

