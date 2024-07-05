#!/usr/bin/env bash
###################################
# Install K8s CNI (idempotent)
# ARGs: ['eBPF' (to mount bpffs)]
###################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "⚠️  ERR : MUST run as root" >&2

    exit 11
}
unset eBPF
[[ ${1,,} =~ 'bpf' ]] && eBPF=yes

ARCH=$(uname -m)
[[ $ARCH ]] || ARCH=amd64
[[ $ARCH = aarch64 ]] && ARCH=arm64
[[ $ARCH = x86_64  ]] && ARCH=amd64

ok(){
    [[ $eBPF ]] || return 
    ## Configure persistent mount of BPF if needed; verify mount else fail, regardless.
    ## - Linux kernel (RHEL9) mounts BPF automatically (sans declaration at /etc/fstab).
    ##   ☩ cat /proc/self/mountinfo |grep /sys/fs/bpf
    ##   31 22 0:28 / /sys/fs/bpf rw,nosuid,nodev,noexec,relatime shared:8 - bpf bpf rw,mode=700
        
    mount |grep --quiet /sys/fs/bpf && return 
    
    ## Mount it directly, temporarily
    #mount bpffs /sys/fs/bpf -t bpf
    
    ## Configure persistent mount by /etc/fstab method
    cat /etc/fstab |grep --quiet bpffs ||
        printf "%s\n" 'bpffs                      /sys/fs/bpf             bpf     defaults 0 0' \
            |tee -a /etc/fstab

    ## Validate mount else fail 
    mount -a && mount |grep --quiet /sys/fs/bpf ||
        return 22

}
ok || exit $?

ok(){
    # Install CNI Plugins else fail
    # https://github.com/containernetworking/plugins/releases
    #ver='v1.5.1' # 2024-06-30
    ver='v1.6.0'  # 2024-06-30 @ K8s v1.29.6, 2024-11-30 @ K8s v1.30.1
    #ver='v1.7.1'  # 
    arch=${ARCH:-amd64}
    to=/opt/cni/bin # /etc/cni/net.d content is created by CNI (deletable on teardown)
    [[ -d $to && $($to/loopback 2>&1 |grep $ver) ]] &&
       return 0
    
    mkdir -p $to
    base="https://github.com/containernetworking/plugins/releases/download/$ver"
    curl -fsSL "$base/cni-plugins-linux-${arch}-${ver}.tgz" \
        |tar -C $to -xz

    # Verify loopback else fail
    [[ -d $to && $($to/loopback 2>&1 |grep $ver) ]] ||
        return 10
}
ok || exit $?

ok(){
    # calicoctl CLI : https://docs.tigera.io/calico/latest/operations/calicoctl/install
    ver='v3.29.3'
    #ver='v3.30.2'
    url=https://github.com/projectcalico/calico/releases/download/$ver/calicoctl-linux-${ARCH:-amd64}
    dir=/usr/local/bin
    file=calicoctl
    [[ $(type -t $file) && $($file version |grep $ver) ]] && return 
    curl -fsSL -o $dir/$file $url &&
        chmod 0755 $dir/$file &&
            $file version |grep $ver ||
                return 33

    # Configure 'kubectl calico' plugin
    # https://docs.tigera.io/calico/latest/operations/calicoctl/install#install-calicoctl-as-a-kubectl-plugin-on-a-single-host
    ln -sfT /usr/local/bin/calicoctl /usr/local/bin/kubectl-calico
}
ok || exit $?

ok(){
    # cilium CLI : https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
    url=https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt
    ver=$(curl -s $url) # v0.18.4
    ver=v0.16.22
    echo $ver |grep --quiet 'v' ||
        return 44
    
    tarball="cilium-linux-${ARCH:-amd64}.tar.gz"
    url=https://github.com/cilium/cilium-cli/releases/download/${ver}/$tarball{,.sha256sum}
    dir=/usr/local/bin
    file=cilium
    [[ $(type -t $file) ]] &&
        $file version |grep --quiet $ver &&
            return 0

    curl -fsSL --remote-name-all $url &&
        sha256sum --check $tarball.sha256sum &&
            tar xzvfC $tarball . &&
                rm $tarball{,.sha256sum} &&
                    install $file $dir/$file ||
                        return 45

    $file version |grep --quiet $ver ||
        return 46
}
ok || exit $?
