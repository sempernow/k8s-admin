#!/usr/bin/env bash
#####################################################
# Calico : Manifests and CLI :
# - Pull manifest-method manifests
# - Pull operator-method manifests
# - Pull, install, and integrate CLI
#####################################################
set -euo pipefail

ok(){
    DIR=.
    VER='v3.29.3' # v3.29.1
    BASE=https://raw.githubusercontent.com/projectcalico/calico/$VER/manifests

    # Pull manifest method
    ok(){
        dir="$DIR/manifest-method"
        file=calico.yaml
        #[[ -f $dir/$file ]] && return 0
        mkdir -p $dir
        pushd $dir
        curl -sSL $BASE/$file -o calico.$VER.yaml || return 100
        popd
    }
    ok || return $?

    # Pull operator method
    ok(){
        dir="$DIR/operator-method"
        mkdir -p $dir

        # Operator
        file=tigera-operator.yaml
        [[ -f $dir/$file ]] || {
            pushd $dir
            curl -sSLO $BASE/$file || return 200
            popd
        }

        # CRDs
        file=custom-resources.yaml
        [[ -f $dir/$file ]] || {
            pushd $dir
            curl -sSLO $BASE/$file || return 300
            popd
        }
    }
    ok || return $?

    # Pull and install CLI, and integrate it into kubectl
    ok(){
        # calicoctl docs : https://docs.tigera.io/calico/latest/operations/calicoctl/install
        url=https://github.com/projectcalico/calico/releases/download/$VER/calicoctl-linux-amd64
        file=calicoctl
        [[ -f $file ]] && return 0
        curl -sSL $url -o $file
        sudo install $file /usr/local/bin/ && rm $file || return $?
        # Enable: kubectl calico ...
        sudo ln -fs /usr/local/bin/$file /usr/local/bin/kubectl-calico
    }
    ok || return $?

    # Calico CNI plugin binaries : See Mamual Recovery of Pod Network
    ok(){
        url=https://github.com/projectcalico/cni-plugin/releases/download/$VER/calico-cni-$VER.tgz
        curl -sSLfO $url && tar zxvf calico-cni-$VER.tgz
    }
    #ok || return $?
}

pushd "${BASH_SOURCE%/*}" || pushd . || return 1
ok || echo "ERR: $?"
popd