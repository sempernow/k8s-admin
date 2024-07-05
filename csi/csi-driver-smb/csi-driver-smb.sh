#!/usr/bin/env bash
########################################################################
# Kubernetes CSI : CSI Driver SMB : Install by Helm
# - A CSI driver to access SMB Server on both Linux and Windows nodes.
# - Access any SMB/CIFS share : NetApp, Samba, Windows Server, ... .
# - https://github.com/kubernetes-csi/csi-driver-smb 
########################################################################

prep(){
    # 1. Pull the chart and extract values.yaml
    base=https://github.com/kubernetes-csi/csi-driver-smb/raw/refs/heads/master/charts
    ver=v1.9.0
    chart=csi-driver-smb-$ver.tgz
    release=csi-driver-smb
    template=helm.template
    ns=smb
    [[ -f values.yaml ]] || {
        [[ -f $chart ]] || {
            echo "ℹ️ Pull the chart : '$chart' from '$base/$ver/'"
            wget $base/$ver/$chart ||
                echo "❌ ERR : $?"
        }
        echo "ℹ️ Extract values file"
        # Extract values.yaml to PWD
        tar -xaf $chart $release/values.yaml &&
            mv $release/values.yaml . &&
                rm -rf $release ||
                    echo "⚠️ values.yaml is *not* extracted."
    }
    # 2. Generate the K8s-resource manifests (helm template) from chart (local|remote)
    [[ -f helm.template.yaml ]] || {
        echo "ℹ️ Generate the chart-rendered K8s resources : helm template ..."
        #helm -n $ns template $chart |tee $template.yaml            # Local chart
        helm -n $ns template $base/$ver/$chart |tee $template.yaml  # Remote chart
    }
    # 3. Extract a list of all images required to install the chart
    [[ -f helm.template.images ]] || {
        echo "ℹ️ Extract images list to '$template.images'."
        tmp="$(mktemp)"
        for kind in DaemonSet Deployment StatefulSet; do
            yq '
                select(.kind == "'$kind'") 
                |.spec.template.spec.containers[].image
            ' $template.yaml >> $tmp
            sort -u $tmp > $template.images
        done
    }
}

mountCIFS(){ 
    # For access to Windows share from a RHEL host:
    echo "ℹ️ Mount a CIFS share from RHEL host ($(hostname -f))."
    
    # 1. Install CIFS (SMB) utilities
    sudo dnf -y install cifs-utils ||
        echo "❌ ERR : $?"
    
    # 2. Mount a Windows SMB share (regardless of its local filesystem format)
    realm=LIME
    server=192.168.11.100
    share=/NTFS002share
    mnt=/mnt/100-ntfs002
    user=CIFS_SVC_ACCT_USERNAME
    pass=CIFS_SVC_ACCT_PASSWORD

    sudo mount -t cifs //$server/$share $mnt \
        -o username=$user,password=$pass,vers=3.0,domain=$realm ||
            echo "❌ ERR : $?"
}

pushd "${BASH_SOURCE%/*}" || pushd . || return 1
"$@" || echo "ERR: $?"
popd