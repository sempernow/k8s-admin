#!/usr/bin/env bash
#####################################
# krew : https://krew.sigs.k8s.io/
#####################################
ok(){
    # krew : Install 
    # https://krew.sigs.k8s.io/docs/user-guide/setup/install/ 
    export KUBECONFIG=~/.kube/config
    kubectl version >/dev/null || exit 100
    kubectl krew version 2>/dev/null || (
        set -x
        cd "$(mktemp -d)" &&
        OS="$(uname |tr '[:upper:]' '[:lower:]')" &&
        ARCH="$(uname -m |sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
        KREW="krew-${OS}_${ARCH}" &&
        curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
        tar -zxvf "${KREW}.tar.gz" &&
        ./$KREW install krew

        echo '
            Adding $HOME/.krew/bin to PATH (at this shell only). 
            To persist, add the statement in ~/.bashrc :

                export PATH="$HOME/.krew/bin:$PATH"

        '
        export PATH="$HOME/.krew/bin:$PATH"

        kubectl krew search
    )
}
ok || exit $?

ok(){
    kubectl krew install ns ctx get-all resource-capacity oomd tail stern whoami rbac-tool who-can deprecations
}
ok || exit $?

ok(){
    # Inspektor Gadget : Install
    # https://github.com/inspektor-gadget/inspektor-gadget
    
    kubectl version >/dev/null || exit 100
    kubectl krew version >/dev/null || exit 101
    
    kubectl krew install gadget
    kubectl gadget deploy
    #kubectl gadget run trace_open:latest
}
ok || exit $?

exit $? 
#######

kubectl krew list           # Installed
kubectl krew search         # Available
kubectl krew info $plugin   # Info regarding that plugin

# Inspektor Gadget : Install 
# https://github.com/inspektor-gadget/inspektor-gadget 
kubectl krew install gadget
kubectl gadget deploy
kubectl gadget --help

########################
## Air-gap environment
########################
name=neat
## Muster the artifacts
kubectl krew list ## All installed : Lists : PLUGIN VERSION, e.g., who-can  v0.4.0
## - Archive using `k krew list`` to extact "URI:" value of each
curl -fsSLO $(kubectl krew info $name |grep URI |cut -d' ' -f2-)
## Form : https://github.com/$owner/$name/releases/download/v0.4.1/kubectl-${name}_v${ver}_${os}_${arch}.tar.gz
## E.g. : https://github.com/vladimirvivien/ktop/releases/download/v0.4.1/kubectl-ktop_v0.4.1_linux_amd64.tar.gz
## - Manifest of installs are located at : ~/.krew/index/default/plugins/$name.yaml

## Install 
kubectl krew install --manifest=$plugin_yaml_path --archive=$plugin_archive_path

## Reference : Location when installed by `kubectl krew install $plugin` 
☩ ls ~/.krew/bin/
total 0

lrwxrwxrwx 1 x1 x1 44 Oct 24 16:25 kubectl-neat -> /home/u1/.krew/store/neat/v2.0.4/kubectl-neat
lrwxrwxrwx 1 x1 x1 36 Sep 21 19:54 kubectl-ns -> /home/u1/.krew/store/ns/v0.9.5/kubens
lrwxrwxrwx 1 x1 x1 47 Oct 24 17:16 kubectl-rbac_tool -> /home/u1/.krew/store/rbac-tool/v1.20.0/rbac-tool