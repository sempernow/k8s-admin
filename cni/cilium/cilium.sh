#!/usr/bin/env bash
# Chart : https://artifacthub.io/packages/helm/cilium/cilium/
# Images : https://github.com/cilium/cilium/releases
VER=1.16.5
REPO='cilium'
CHART='cilium'
APP=$CHART
ARCHIVE="${APP}-$VER.tgz"

pull_chart(){
    [[ -r $ARCHIVE ]] || {
        helm repo add $REPO https://helm.cilium.io/ ||
            helm repo update $REPO
        helm pull $REPO/$CHART --version $VER
    }
    [[ -r $ARCHIVE ]] || return 11
}
export -f pull_chart
download(){
    # CLI : https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/
    dir="cilium-cli"
    ./$dir/cilium version 2>&1 || {
        mkdir -p $dir
        pushd $dir || return 11
        url=https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt
        ver=$(curl -s $url) # v0.16.22
        echo $ver |grep 'v' || return 12
        arch=${ARCH:-amd64}
        [[ "$(uname -m)" = "aarch64" ]] && arch=arm64
        archive="cilium-linux-${arch}.tar.gz"
        url=https://github.com/cilium/cilium-cli/releases/download/${ver}/$archive{,.sha256sum}
        curl -L --fail --remote-name-all $url &&
            sha256sum --check $archive.sha256sum &&
                sudo tar xzvfC $archive . &&
                    rm $archive{,.sha256sum}
        popd
    }
    # Chart  : https://artifacthub.io/packages/helm/cilium/cilium/
    # Images : https://github.com/cilium/cilium/releases
    pull_chart &&
        tar -xaf $ARCHIVE &&
            cp -p $CHART/values.yaml . &&
                type -t hdi >/dev/null 2>&1 &&
                    hdi $CHART                
    rm -rf $CHART
}
helm_template(){
    # Chart : https://artifacthub.io/packages/helm/cilium/cilium/
    # Render the manifest for kubectl apply -f $manifest
    app=c
    helm template $APP --values $1 $APP/$APP |tee helm.template.$APP.$1
}
install_by_manifest(){
    [[ -r $1 ]] || {
        echo '
            @ '${BASH_SOURCE##*/}'

            Function '$FUNCNAME 'REQUIREs manifest file ($1) argument.

            Create manifest file by calling: 
            
                helm_template $a_values_file
        '
        return 0
    }
    kubectl apply -f $1
}
install_by_cli(){
    pull_chart &&
        tar -xaf $ARCHIVE &&
            cilium install \
                --values="$1" \
                --version="$VER" \
                --chart-directory="$CHART" &&
                    rm -rf $CHART

    # cilium install \
        #     --set debug.enabled='true' \
        #     --set k8sServiceHost="${K8S_CONTROL_IP}" \
        #     --set k8sServicePort="${K8S_CONTROL_PORT}" \
        #     --set cluster.name=${K8S_CLUSTER_NAME} \
        #     --set rollOutCiliumPods='true' \
        #     --set l2announcements.enabled='true' \
        #     --set l2podAnnouncements.enabled='true' \
        #     --set l2podAnnouncements.interface="$K8S_NETWORK_DEVICE" \
        #     --set bgp.enabled='false' \
        #     --set bgp.announce.loadbalancerIP='true' \
        #     --set bgp.announce.podCIDR='true' \
        #     --set bgpControlPlane.enabled='true' \
        #     --set bpf.autoMount.enabled='true' \
        #     --set bpf.masquerade='true' \
        #     --set bpf.datapathMode='veth' \
        #     --set waitForKubeProxy='false' \
        #     --set cni.install='true' \
        #     --set envoyConfig.enabled='true' \
        #     --set identityAllocationMode='crd' \
        #     --set ipam.mode=kubernetes \
        #     --set ipam.operator.clusterPoolIPv4PodCIDRList[0]="$K8S_POD_CIDR" \
        #     --set ipam.operator.clusterPoolIPv4MaskSize="$K8S_NODE_CIDR_MASK" \
        #     --set ipam.operator.clusterPoolIPv6PodCIDRList[0]="$K8S_POD_CIDR6" \
        #     --set ipam.operator.clusterPoolIPv6MaskSize="$K8S_NODE_CIDR6_MASK" \
        #     --set nodeIPAM.enabled='true' \
        #     --set tunnelProtocol='' \
        #     --set routingMode=native \
        #     --set autoDirectNodeRoutes='true' \
        #     --set directRoutingSkipUnreachable='true' \
        #     --set ipv4NativeRoutingCIDR="$K8S_POD_CIDR" \
        #     --set ipv6NativeRoutingCIDR="$K8S_POD_CIDR6" \
        #     --set ipMasqAgent.enabled='false' \
        #     --set ipv4.enabled='true' \
        #     --set ipv6.enabled='false' \
        #     --set k8s.requireIPv4PodCIDR='true' \
        #     --set k8s.requireIPv6PodCIDR='false' \
        #     --set kubeProxyReplacement='true' \
        #     --set kubeProxyReplacementHealthzBindAddr='0.0.0.0:10256' \
        #     --set l2NeighDiscovery.enabled='true' \
        #     --set l7Proxy='true' \
        #     --set logSystemLoad='true' \
        #     --set enableIPv4Masquerade='true' \
        #     --set enableIPv6Masquerade='true' \
        #     --set loadBalancer.algorithm=maglev \
        #     --set loadBalancer.mode=dsr \
        #     --set envoy.enabled='true' \
        #     --set operator.enabled='true' \
        #     --set operator.rollOutPods='true' \
        #     --set nodeinit.enabled='true' \
        #     --set preflight.enabled='true' \
        #     --version="$v" #--dry-run-helm-values

            #--chart-directory="$APP"
        
}
install_by_helm(){
    pull_chart &&
        tar -xaf $ARCHIVE &&
            helm upgrade $APP $CHART/ --install --values $1 &&
                rm -rf $CHART
    # kubectl patch ds -n kube-system kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-cilium": "true"}}}}}'
}
teardown(){
    helm -n kube-system uninstall $APP
    cilium uninstall || echo ERR : $APP $FUNCNAME : $?
}

pushd "${BASH_SOURCE%/*}" || pushd . || return 1
"$@" || code=$?
popd 
[[ $code ]] && echo ERR : ${BASH_SOURCE##*/} : $? || echo


exit
####

# Cilium app logs
kubectl -n kube-system logs -l k8s-app=cilium

# CM
kubectl -n kube-system get configmap cilium-config -o yaml

# Egress issues
cilium egress list
