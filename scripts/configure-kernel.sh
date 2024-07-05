#!/usr/bin/env bash
########################################
# Configure kernel for K8s CRI and CNI
# - Idempotent
########################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "⚠️  ERR : MUST run as root" >&2

    exit 11
}
# Install kernel headers else fail
rpm -q kernel-headers ||
    dnf -y install kernel-headers-$(uname -r) ||
        exit 10

rpm -q kernel-devel ||
    dnf -y install kernel-devel-$(uname -r) ||
        exit 11

ok(){
    # Load kernel modules now (okay if already loaded) else fail
    modprobe br_netfilter  
    [[ $(lsmod |grep br_netfilter) ]] ||
        return 21

    modprobe overlay  
    [[ $(lsmod |grep overlay) ]] ||
        return 22

    # Linux IPVS (IP Virtual Server) 

    modprobe ip_vs  
    [[ $(lsmod |grep ip_vs) ]] ||
        return 23

    modprobe ip_vs_rr  
    [[ $(lsmod |grep ip_vs_rr) ]] ||
        return 24

    modprobe ip_vs_wrr  
    [[ $(lsmod |grep ip_vs_wrr) ]] ||
        return 25
    
    modprobe ip_vs_sh  
    [[ $(lsmod |grep ip_vs_sh) ]] ||
        return 26

    # ip_vs_wlc : Weighted Least-Connections Scheduling;
    # - One of the built-in scheduling algorithms 
    #   provided by Linux IPVS 
    # - A load-balancing algorithm used by Linux-kernel IPVS  (IP Virtual Server)
    modprobe ip_vs_wlc
    [[ $(lsmod |grep ip_vs_wlc) ]] ||
        return 27

    # Load kernel modules on boot (configure for that else fail)
    conf=/etc/modules-load.d/kubernetes.conf
    [[ $(cat $conf 2>/dev/null |grep overlay) ]] &&
        return 0
    ## br_netfilter enables transparent masquerading 
    ## and facilitates VxLAN traffic between Pods.
	tee $conf <<-EOH
	br_netfilter
	ip_vs
	ip_vs_rr
	ip_vs_wrr
	ip_vs_sh
    ip_vs_wlc
	overlay
	EOH
    [[ $(cat $conf 2>/dev/null |grep overlay) ]] ||
        return 33
}
ok || exit $?

ok(){
    # Configure kernel runtime params (sysctl) 
    conf=/etc/sysctl.d/99-kubernetes.conf
    [[ $(cat $conf 2>/dev/null |grep 'net.bridge.bridge-nf-call-iptables  = 1') ]] &&
        return 0

	tee $conf <<-EOH
	net.bridge.bridge-nf-call-ip6tables = 1
	net.bridge.bridge-nf-call-iptables  = 1
	net.ipv4.ip_forward                 = 1
	EOH
    # |Kernel Parameter	                    | Description                      |
    # |-------------------------------------|----------------------------------|
    # |`net.bridge.bridge-nf-call-iptables` |Bridged IPv4 traffic via iptables.|
    # |`net.bridge.bridge-nf-call-ip6tables`|Bridged IPv6 traffic via iptables.|
    # |`net.ipv4.ip_forward`                |IPv4 packet forwarding.           |

    [[ $(cat $conf 2>/dev/null |grep 'net.bridge.bridge-nf-call-iptables  = 1') ]] ||
        return 44
}
ok || exit $?
    
# If configuration changed, then apply settings else fail
sysctl --system |grep Applying || exit 88

[[ $(sysctl net.ipv4.ip_forward |cut -d' ' -f3- |grep '1') ]] ||
    exit 99

exit 0
####

    ## RHEL 8+ migrated to nftables; depricated iptables.
    ## So, nf_* modules are loaded instead of ip_ :
    lsmod |grep nf_
    # nf_conntrack_netlink   65536  0
    # nf_reject_ipv4         16384  1 ipt_REJECT
    # nf_nat                 65536  3 xt_nat,nft_chain_nat,xt_MASQUERADE
    # nf_tables             356352  62 nft_compat,nft_counter,nft_chain_nat
    # nfnetlink              20480  4 nft_compat,nf_conntrack_netlink,nf_tables,ip_set
    # nf_conntrack          229376  7 xt_conntrack,nf_nat,xt_nat,nf_conntrack_netlink,xt_CT,xt_MASQUERADE,ip_vs
    # nf_defrag_ipv6         24576  2 nf_conntrack,ip_vs
    # nf_defrag_ipv4         12288  1 nf_conntrack
    # libcrc32c              12288  6 nf_conntrack,nf_nat,nf_tables,xfs,libceph,ip_vs

    ## @ IPVS (IP Virtual Server)
    ldmof |grep ip_vs
    # ip_vs_wlc              12288  0
    # ip_vs_sh               12288  0
    # ip_vs_wrr              12288  0
    # ip_vs_rr               12288  0
    # ip_vs                 237568  8 ip_vs_wlc,ip_vs_rr,ip_vs_sh,ip_vs_wrr
    # nf_conntrack          229376  7 xt_conntrack,nf_nat,xt_nat,nf_conntrack_netlink,xt_CT,xt_MASQUERADE,ip_vs
    # nf_defrag_ipv6         24576  2 nf_conntrack,ip_vs
    # libcrc32c              12288  6 nf_conntrack,nf_nat,nf_tables,xfs,libceph,ip_vs