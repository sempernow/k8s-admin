#!/usr/bin/env bash
###############################################################################
# firewalld (Linux host firewall) regarding K8s-internal traffic :
#
# A "default" firewalld zone binds to all *new* adapters of K8s-CNI plugin.
# These are isolated, virtual, ephemeral interfaces created, destroyed, 
# and otherwise managed per Pod by the CNI plugin (Calico, Cilium, ...).
# All Pod and Service (CIDRs) traffic traverses these adapters.
# 
# This script creates an apropos zone for all K8s-internal traffic, 
# and persists that as the "default" zone of firewalld.
# 
# - Idempotent.
#
# This scheme presumes another zone *explicitly* binds to the host's 
# *external* (domain-facing) adapter, and has apropos rules regarding 
# K8s-external inbound host traffic (from external clients and such).
#
# REQUIREMENTS:
# - These virtual adapters are "unmanaged" by NetworkManager (nmcli).
#     - This is default behavior at RHEL8+. 
#     - Verify by (unprivileged) execution of "nmcli dev status".
# 
# ARGs: ZONE  POD_CIDR  SERVICE_CIDR  HOST_CIDR  [ANY(to teardown)]
#
# https://kubernetes.io/docs/reference/networking/ports-and-protocols/
# https://docs.oracle.com/en/operating-systems/olcne/1.1/start/ports.html
###############################################################################

[[ "$(id -u)" -ne 0 ]] && {
    echo "❌  ERR : MUST run as root" >&2

    exit 11
}
[[ -n $4 ]] || {
    echo "❌  ERR : Missing args : Environment is UNCONFIGURED" >&2

    exit 22
}
export zone=$1
export podCIDR="$2"
export svcCIDR="$3"
export hostCIDR="$4"
[[ -n $5 ]] &&
    export do='remove' ||
        export do='add'

## Assure firewalld.service is running; persist otherwise.
systemctl is-active --quiet firewalld ||
    systemctl enable --now firewalld

export at="--permanent --zone=$zone"

[[ $do == 'add' ]] && {

    ## Add zone that binds to all *new* interfaces
    firewall-cmd --get-zones |grep -q "\b$zone\b" || {
        firewall-cmd --new-zone=$zone --permanent &&
            firewall-cmd --reload
    }

    firewall-cmd $at --set-target=ACCEPT    # CNI manages via NetworkPolicy resource(s)
    firewall-cmd --set-log-denied=all       # Logging applies to all zones

    ## Allow outbound traffic via NAT (e.g., IP-in-IP tunneling) and all internal Pod-Service routing.
    firewall-cmd $at --$do-forward
    firewall-cmd $at --$do-masquerade

    ## Set to default zone; will bind to all (internal, virtual, ephemeral) 
    ## interfaces created by the K8s CNI plugin (Calico, Cilium, ...).
    firewall-cmd --set-default-zone=$zone
}

## Allow ICMP for ping request/reply 
firewall-cmd $at --$do-icmp-block-inversion    # Remove if inverted
firewall-cmd $at --$do-icmp-block=echo-request # Allow request 
firewall-cmd $at --$do-icmp-block=echo-reply   # Allow reply

## Allow all Pod and Service (CIDRs) traffic
## Rich Rule : Requires zone bound to the internal interfaces, but it isn't.  
## That our zone is "default" is insufficient.
# for cidr in "$podCIDR" "$svcCIDR" "$hostCIDR"
# do 
#    firewall-cmd $at --$do-rich-rule='rule family=ipv4 source address='$cidr' accept'
#    firewall-cmd $at --$do-rich-rule='rule family=ipv4 destination address='$cidr' accept'
# done

export at="--permanent --direct"

## A --direct rule should take precedence over zone-based rules, including zone target=DROP.
## HOWEVER, in practice, when zones are mismatched between IN and OUT interfaces, 
## or when the kernel isn't able to conclusively route the packet before zone logic, 
## a --direct rule may be skipped or bypassed in the FORWARD chain evaluation.
firewall-cmd $at --$do-rule ipv4 filter FORWARD 0 -s "$podCIDR" -d "$podCIDR" -j ACCEPT
firewall-cmd $at --$do-rule ipv4 filter FORWARD 0 -s "$podCIDR" -d "$svcCIDR" -j ACCEPT
firewall-cmd $at --$do-rule ipv4 filter FORWARD 0 -s "$podCIDR" -d "$hostCIDR" -j ACCEPT
firewall-cmd $at --$do-rule ipv4 filter FORWARD 0 -s "$svcCIDR" -d "$hostCIDR" -j ACCEPT # Headless to NodePorts
firewall-cmd $at --$do-rule ipv4 filter FORWARD 0 -s "$svcCIDR" -d "$podCIDR" -j ACCEPT
firewall-cmd $at --$do-rule ipv4 filter FORWARD 0 -s "$hostCIDR" -d "$svcCIDR" -j ACCEPT

firewall-cmd --reload

firewall-cmd --get-default-zone |grep -q "\b$zone\b" || {
    echo "❌️  ERR : The default zone is NOT '$zone'"

    exit 99
}
