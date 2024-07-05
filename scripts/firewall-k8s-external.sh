#!/usr/bin/env bash
###############################################################################
# firewalld (Linux host firewall) regarding K8s-external traffic :
#
# This script creates an apropos zone for all K8s-external traffic, 
# and persistently binds that to host's external (domain-facing) adapter 
# such that zone-interface binding survives the dynamic control 
# of all such "connected" devices by NetworkManager (nmcli).
# 
# - Idempotent.
#
# This scheme presumes another zone binds to all *internal* adapters
# managed by the K8s-CNI plugin, and that its rules fit requirements
# regarding (K8s) Pod and Service (CIDRs) traffic.
#
# ARGs: NETWORK_INTERFACE  ZONE_OF_INTERFACE  [ANY(to teardown)]
#
# https://docs.oracle.com/en/operating-systems/olcne/1.1/start/ports.html
# https://kubernetes.io/docs/reference/networking/ports-and-protocols/
###############################################################################

[[ "$(id -u)" -ne 0 ]] && {
    echo "❌  ERR : MUST run as root" >&2

    exit 11
}
[[ -n $2 ]] || {
    echo "❌  ERR : Missing args : Environment is UNCONFIGURED" >&2

    exit 22
}
export ifc="$1"
export zone=$2
[[ -n $3 ]] &&
    export do='remove' ||
        export do='add'

ip_scoped_rules(){
    ## Allow K8s (common & control) ports only if source is another K8s node
    
    _do=$1
    echo "ℹ️  $_do ip-scoped rules"

    common_tcp='10249 10250 10255 10256 30000-32767'
    control_tcp='2379-2381 6443 10257 10259'

    export at="--permanent --zone=$zone"

    for ipv4 in $K8S_PEERS; do
        for port in $common_tcp $control_tcp; do
            firewall-cmd $at --$_do-rich-rule="rule family=ipv4 source address=$ipv4 port port=$port protocol=tcp accept" || return 34
        done
        firewall-cmd $at --$_do-rich-rule="rule family=ipv4 source address=$ipv4 port port=30000-32767 protocol=udp accept" || return 35
    done
}
svc_scoped_rules(){
    ## Allow K8s (common & control) ports regardless of source
    
    _do=$1
    echo "ℹ️  $_do service-scoped rules"

    ## Service : K8s common (control and worker)
    svc='k8s-common'
    [[ $_do == 'add' ]] && {
        ## Create and configure the service
        firewall-cmd --get-services |grep -q "\b$svc\b" ||
            firewall-cmd --permanent --new-service=$svc

        at="--permanent --zone=$zone --service=$svc"

        firewall-cmd $at --set-description="K8s every node"
        firewall-cmd $at --$_do-port=10249/tcp       # kubelet read-only
        firewall-cmd $at --$_do-port=10250/tcp       # kubelet API inbound
        firewall-cmd $at --$_do-port=10255/tcp       # kubelet Node/Pod CIDRs (v1.23.6+)
        firewall-cmd $at --$_do-port=10256/tcp       # GKE LB Health checks
        firewall-cmd $at --$_do-port=30000-32767/tcp # NodePort Services inbound 
        firewall-cmd $at --$_do-port=30000-32767/udp # NodePort Services inbound
        ##... Our K8s NodePort range (default) is *outside* of IANA-registered ranges and 
        ##    just *below* that of Linux/RHEL (default) Ephemeral ports (32768–60999) AKA Local ports, 
        ##    which is for host's (short-lived) network connections, e.g., UDP/TCP/HTTP(S) traffic:
        ##        $ cat /proc/sys/net/ipv4/ip_local_port_range # Print the ephemeral-ports range
        ##        $ sysctl net.ipv4.ip_local_port_range        # Print the ephemeral-ports range

        ## @ Metrics
        firewall-cmd $at --$_do-port=9100/tcp        # Node exporter
        firewall-cmd $at --$_do-port=9153/tcp        # CoreDNS metrics
    }
    firewall-cmd --permanent --zone=$zone --$_do-service=$svc ||
        echo "ℹ️  Okay if error is NAME_CONFLICT"

    ## Service : K8s Control nodes
    svc='k8s-control'
    [[ $_do == 'add' ]] && {
        ## Create and configure the service
        firewall-cmd --get-services |grep -q "\b$svc\b" ||
            firewall-cmd --permanent --new-service=$svc

        at="--permanent --zone=$zone --service=$svc"

        firewall-cmd $at --set-description="K8s Control node"
        firewall-cmd $at --$_do-port=2379-2380/tcp   # etcd, kube-apiserver inbound
        firewall-cmd $at --$_do-port=2381/tcp        # etcd non-default
        firewall-cmd $at --$_do-port=6443/tcp        # kube-apiserver inbound
        firewall-cmd $at --$_do-port=10257/tcp       # kube-controller-manager inbound   (10252/tcp @ v1.17-)
        firewall-cmd $at --$_do-port=10259/tcp       # kube-scheduler inbound            (10259/tcp @ v1.17-)
    }
    
    firewall-cmd --permanent --zone=$zone --$_do-service=$svc ||
        echo "ℹ️  Okay if error is NAME_CONFLICT"
}
export -f ip_scoped_rules svc_scoped_rules

## Assure firewalld.service is running; persist otherwise.
systemctl is-active --quiet firewalld ||
    systemctl enable --now firewalld

## Set the default zone that will bind to all internal (ephemeral/CNI) virtual interfaces 
firewall-cmd --set-default-zone=trusted # Reset to k8s-internal zone by firewall-k8s-internal.sh

export at="--permanent --zone=$zone"

[[ $do == 'add' ]] && {

    ## Add zone that binds to the external (domain-facing) interface ($2) of this host
    firewall-cmd --get-zones |grep -q "\b$zone\b" || {
        firewall-cmd --new-zone=$zone --permanent &&
            firewall-cmd --reload
    }

    firewall-cmd $at --set-target=DROP  # Drop all packets not explicitly allowed (Whitelisted)
    firewall-cmd --set-log-denied=all   # Logging applies to all zones

    ## Add all nominal services : Never remove ($do)
    if_nfs='mountd nfs rpc-bind samba'
    printf "%s\n" dhcp dhcpv6-client dns kerberos ldap ldaps ntp ssh $if_nfs |
        xargs -I{} firewall-cmd $at --add-service={}
}

## @ Ingress (HTTP/HTTPS)
firewall-cmd $at --$do-service=http
firewall-cmd $at --$do-service=https

## @ ping : Allow ICMP echo-request/reply : Inversion is *required* if zone target is DROP 
firewall-cmd $at --$do-icmp-block-inversion    # Invert so block allows
firewall-cmd $at --$do-icmp-block=echo-request # block (allow if inversion) request 
firewall-cmd $at --$do-icmp-block=echo-reply   # block (allow if inversion) reply

# @ Pod-Pod and Pod-Service traffic
firewall-cmd $at --$do-forward      # Allow pod-pod traffic, esp. cross-node IP-in-IP
firewall-cmd $at --$do-masquerade   # Allow NAT 

# @ Rules per scope (ip OR svc)
scope=svc # DECLARE scope HERE
[[ $scope == 'svc' ]] && {
    ip_scoped_rules remove 
    svc_scoped_rules $do || {
        echo "❌  ERR : $? : svc_scoped_rules '$do'" >&2

        exit 44
    }
}
[[ $scope == 'ip' ]] && {
    svc_scoped_rules remove 
    ip_scoped_rules $do || {
        echo "❌  ERR : $? : ip_scoped_rules '$do'" >&2

        exit 45
    }
}

[[ $do == 'add' ]] && {
    ## Bind interface to zone at NetworkManager.service (by nmcli), NOT at firewalld.service :
    false && firewall-cmd $at --change-interface="$ifc" # <== DO NOT USE firewall-cmd method.
    ## WHY? NetworkManager *overrules* firewalld, so if NetworkManager configuration differs, 
    ## then change of ifc-zone binding at firewalld WILL NOT PERSIST.
    ## This nmcli method precludes that (silent and delayed) fail mode.
    ##
    ## Apply firewalld rules declared above ONLY IF ifc-zone binding
    ## succeeds (or already existed) as reported by nmcli method below:
    nmcli con show "$ifc" |grep connection.zone |grep -q "\b$zone\b" && firewall-cmd --reload || {
        nmcli con modify "$ifc" connection.zone $zone &&
            nmcli con down "$ifc" &&
                nmcli con up "$ifc" &&
                    firewall-cmd --reload ||
                        echo "❌️  ERR : $? @ nmcli, ifc: '$ifc', zone: '$zone'"
    }

    ## Verify zone is active by verifying interface is bound to it.
    export z="$(firewall-cmd --get-zone-of-interface=$ifc)"
    [[  "$z" == "$zone" ]] || {
        echo "❌️  ERR : Zone of interface '$ifc' is '$z' NOT '$zone'"

        exit 99
    }
}
[[ $do != 'add' ]] && firewall-cmd --reload || echo 
