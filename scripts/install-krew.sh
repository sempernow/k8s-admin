#!/usr/bin/env bash
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

    kubectl krew list
)

exit $? 
#######

# Inspektor Gadget : Install 
# https://github.com/inspektor-gadget/inspektor-gadget 
kubectl krew install gadget
kubectl gadget deploy
kubectl gadget --help