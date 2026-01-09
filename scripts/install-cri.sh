#!/usr/bin/env bash
################################################
# Install K8s CRI (idempotent)
################################################
# >>>  ALIGN apps VERSIONs with K8s version  <<<
################################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "⚠️  ERR : MUST run as root" >&2

    exit 11
}
ARCH=$(uname -m)
[[ $ARCH ]] || ARCH=amd64
[[ $ARCH = aarch64 ]] && ARCH=arm64
[[ $ARCH = x86_64  ]] && ARCH=amd64

REGISTRY="${CNCF_REGISTRY_ENDPOINT:-registry.k8s.io}"

unset _flag_configure
disableContainerd(){
    _flag_configure=1
    systemctl is-active --quiet containerd.service &&
        systemctl disable --now containerd.service
}
export -f disableContainerd

ok(){
    # Install runc (containerd dependency) else fail
    # https://github.com/opencontainers/runc/releases
    # https://github.com/containerd/containerd/blob/main/docs/getting-started.md
    ver='1.2.2'
    #ver='1.2.6'
    [[ $(runc -v 2>&1 |grep $ver) ]] &&
        return 0 
    disableContainerd
    arch=${ARCH:-amd64}
    url="https://github.com/opencontainers/runc/releases/download/v${ver}/runc.$arch"
    dst=/usr/local/sbin
    curl -o $dst/runc -fsSL $url &&
        chmod 0755 $dst/runc ||
            return 11
    [[ $(runc -v 2>&1 |grep $ver) ]] ||
        return 12
    ln -sf $dst/runc /usr/sbin/runc
}
ok || exit $?

ok(){
    # Install containerd binaries else fail
    # https://github.com/containerd/containerd/blob/main/docs/getting-started.md
    # https://github.com/containerd/containerd/releases
    # ver='2.0.0' # Breaking changes : See keys & version of /etc/containerd/config.toml
    # Usage ctr vs. crictl : ctr -n k8s.io ...# Default namespace is not that of crictl.
    ver='1.7.24'
    #ver='2.1.3'
    arch=${ARCH:-amd64}
    tarball="containerd-${ver}-linux-${arch}.tar.gz"
    [[ $(containerd --version 2>&1 |grep v$ver) ]] &&
        return 0
    disableContainerd
    base=https://github.com/containerd/containerd/releases/download/v$ver
    curl -fsSL $base/$tarball |tar -C /usr/local -xz ||
        return 20
    [[ $(containerd --version 2>&1 |grep v$ver) ]] ||
        return 21
}
ok || exit $?

ok(){
    # Configure containerd for K8s CRI @ /etc/containerd/config.toml
    # https://github.com/containerd/containerd/blob/main/docs/cri/config.md
    # https://kubernetes.io/docs/setup/production-environment/container-runtimes/#containerd

    ## Local (insecure) registry perhaps :
    registry=$REGISTRY
    
    ## Select config : default|minimal|custom
    config=minimal

    toml=/etc/containerd/config.toml
    [[ -f $toml ]] &&
        return 0
    disableContainerd
    mkdir -p /etc/containerd
    
    default(){
        containerd config default |tee $toml
    }
    minimal(){
		cat <<-EOH |tee $toml
		## Configured for K8s : runc, systemd cgroup, GC
		version = 2
		[debug]
		  level = "info"
		[metrics]
		  address = "127.0.0.1:1338"
		[plugins]
		  [plugins."io.containerd.gc.v1.scheduler"]
		    deletion_threshold = 20
		    mutation_threshold = 20
		    pause_threshold = 0.8
		    schedule_delay = "1m"
		    startup_delay = "10s"
		  [plugins."io.containerd.grpc.v1.cri"]
		    sandbox_image = "registry.k8s.io/pause:3.9"
		    [plugins."io.containerd.grpc.v1.cri".containerd]
		      discard_unpacked_layers = true
		      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
		        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
		          runtime_type = "io.containerd.runc.v2"
		            [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
		              SystemdCgroup = true
		EOH
    }
    custom(){
        [[ $registry ]] ||
            return 33
		cat <<-EOH |tee $toml
		## Configured for K8s : runc, systemd, and local insecure registry 
		version = 2
		[debug]
		  level = "info"
		[metrics]
		  address = "127.0.0.1:1338"
		[plugins]
		  [plugins."io.containerd.grpc.v1.cri"]
		    sandbox_image = "$registry/pause:3.9"
		    [plugins."io.containerd.grpc.v1.cri".containerd]
		      discard_unpacked_layers = true
		      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
		        [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
		          runtime_type = "io.containerd.runc.v2"
		          [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
		            SystemdCgroup = true
		    [plugins."io.containerd.grpc.v1.cri".registry]
		      [plugins."io.containerd.grpc.v1.cri".registry.configs]
		        [plugins."io.containerd.grpc.v1.cri".registry.configs."$registry"]
		          endpoint = ["http://$registry"]
		          [plugins."io.containerd.grpc.v1.cri".registry.configs."$registry".tls]
		            insecure_skip_verify = true
		EOH
    }
    $config ||
        return $?

    [[ $(cat $toml |grep '\[debug\]') ]] ||
        return 35
}
ok || exit $?

ok(){
    # Configure containerd as a systemd service else fail
    url=https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
    sys=/etc/systemd/system
    # [[ -f $sys/containerd.service ]] &&
    #     return 0
    disableContainerd
    mkdir -p $sys
    curl -o $sys/containerd.service -fsSL $url ||
        return 40
}
ok || exit $?

ok(){
    [[ $_flag_configure ]] &&
        systemctl daemon-reload &&
        	  systemctl enable --now containerd.service

    registry=${REGISTRY:-k8s.registry.io}
    [[ $(containerd config dump |grep $registry) ]] ||
        return 50

	  systemctl is-active --quiet containerd.service ||
        return 55
}
ok || exit $?

ok(){
    # Install CRI tools (cri-tools) else fail
    # https://github.com/kubernetes-sigs/cri-tools?tab=readme-ov-file#install 
    ver='v1.29.0'
    #ver='v1.33.0'
    arch=${ARCH:-amd64}
    base="https://github.com/kubernetes-sigs/cri-tools/releases/download/$ver"
    suffix="${ver}-linux-${arch}.tar.gz"

    bin=/usr/local/bin # Documented install location, yet not in default sudo path
    [[ $(crictl --version 2>&1 |grep $ver) ]] ||
        curl -fsSL "$base/crictl-$suffix" |tar -C $bin -xz

    [[ $(critest --version 2>&1 |grep $ver) ]] ||
        curl -fsSL "$base/critest-$suffix" |tar -C $bin -xz

    ln=/usr/sbin # Create link at default sudoers path

    ln -sf $bin/crictl $ln/ &&
        crictl --version ||
            return 60

    ln -sf $bin/critest $ln/ &&
        critest --version ||
            return 61

    # Default behavior is depricated; declare endpoints
    # https://github.com/kubernetes-sigs/cri-tools/blob/master/docs/crictl.md
    conf=/etc/crictl.yaml
    #[[ -f $conf ]] && return 0
	tee $conf <<-EOH
	runtime-endpoint: unix:///run/containerd/containerd.sock
	image-endpoint: unix:///run/containerd/containerd.sock
	timeout: 2
	debug: true
	pull-image-on-create: false
	EOH
}
ok || exit $?
