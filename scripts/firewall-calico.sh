#!/usr/bin/env bash
###############################################################################
# firewalld : Calico
# - Idempotent
#
# ARGs: NTWK_INTERFACE ZONE_OF_INTERFACE LIST_OF_PEERS_IPV4 [ANY(to teardown)]
#
# https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements
# https://docs.tigera.io/calico/latest/reference/typha/overview
###############################################################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "❌️  ERR : MUST run as root" >&2

    exit 11
}
[[ $3 ]] || {
    echo "❌️  ERR : Missing args : Environment is UNCONFIGURED" >&2

    exit 22
}
export ifc="$1"
export zone=$2
export peers="$3"
[[ -n $4 ]] &&
    export do='remove' ||
        export do='add'

systemctl is-active --quiet firewalld ||
    systemctl enable --now firewalld

p4LockDown(){
    ## Protocol 4 is required by Calico IPIP mode (encapsulation), 
    ## yet it can be used to bypass normal (tcp/udp) rules,
    ## so lock it down using Rich Rules,
    ## allowing its traffic across this interface (zone) only if between K8s peers.
    export at="--permanent --zone=$zone"
    # For each peer (k8s node) 
    printf "%s\n" $peers |
        xargs -I{} firewall-cmd $at --$do-rich-rule='rule family="ipv4" protocol value="4" source address="'{}'" accept'
    # Drop all other protocol 4 traffic
    firewall-cmd $at --$do-rich-rule='rule family="ipv4" protocol value="4" drop'
}

at="--permanent --zone=$zone"

## Protocol 4
firewall-cmd $at --$do-protocol=4       # Allow IP-in-IP 
firewall-cmd $at --remove-rich-rule='rule protocol value="4" drop' # Added at p4LockDown
#p4LockDown                             # Allow IP-in-IP only betwen K8s peers

export svc='calico'

[[ $do == 'add' ]] && {
    firewall-cmd --list-services --zone=$zone |grep $svc ||
        firewall-cmd $at --new-service=$svc

    at="--permanent --zone=$zone --service=$svc"

    firewall-cmd $at --set-description='Calico : BGP, VXLAN, Typha agent hosts, Wireguard'
    firewall-cmd $at --add-port=179/tcp     # BGP (Calico)
    firewall-cmd $at --add-port=4789/udp    # VXLAN (Calico/Flannel)
    firewall-cmd $at --add-port=5473/tcp    # Calico Typha agent hosts
    firewall-cmd $at --add-port=51820/udp   # Wireguard (Calico)
    firewall-cmd $at --add-port=51821/udp   # Wireguard (Calico)
    firewall-cmd $at --add-port=9099/tcp    # Health check

}
firewall-cmd --permanent --zone=$zone --$do-service=$svc ||
    echo "ℹ️  Okay if error is NAME_CONFLICT"

firewall-cmd --reload
