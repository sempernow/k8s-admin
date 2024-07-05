#!/usr/bin/env bash
# firewalld (Linux host firewall) get all
[[ "$(id -u)" -ne 0 ]] && {
    echo "❌  ERR : MUST run as root" >&2

    exit 11
}

for zone in k8s-external k8s-internal
do 
    firewall-cmd --zone=$zone --list-all
    printf "%s\n" $(firewall-cmd --list-services --zone=$zone) \
        |xargs -I{} firewall-cmd --info-service={}
done
echo "Direct rules : Scoped to interface, not zone"
firewall-cmd --direct --get-all-rules