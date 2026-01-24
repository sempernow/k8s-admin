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

setCreds(){
    [[ $3 ]] || echo "  USAGE: $FUNCNAME user pass realm 2>&"
    [[ $3 ]] || return 1
    
	mkdir -p /etc/cifs || return 2
	tee /etc/cifs/svc-smb-rw.creds <<-EOH
	username=$1
	password=$2
	domain=$3
	EOH
      chmod 600 /etc/cifs/svc-smb-rw.creds
}
mountCIFS(){ 
    [[ "$(id -u)" -ne 0 ]] && return 1
    mode=${1:-service} # service|group|unmount

    # 1. Install CIFS (SMB) utilities
    dnf list installed cifs-utils ||
        dnf -y install cifs-utils ||
            return 2
    
    # 2. Mount a Windows SMB share (regardless of its local filesystem format)
    realm=LIME
    server=dc1.lime.lan
    share=SMBdata
    mnt=/mnt/smb-data-01
    svc=svc-smb-rw
    ## Creds only if sec=ntlmssp 
    creds=/etc/cifs/$svc.creds
    mkdir -p $mnt || return 3
    uid="$(id -u $svc)"

    [[ $mode == unmount ]] && {
        umount $mnt
        return $?
    }
    echo "ℹ️ Mount a CIFS share from RHEL host ($(hostname -f)) for '$mode' access."
 
    # Allow R/W access by only AD User 'svc-smb-rw' 
    gid="$(id -g svc-smb-rw)"
    [[ $mode == service ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=ntlmssp,credentials=$creds,vers=3.0,uid=$uid,gid=$gid,file_mode=0640,dir_mode=0775 ||
                return 4
    }
    
    # Allow R/W access by all members of AD Group 'ad-smb-admins'
    gid="$(getent group ad-smb-admins |cut -d: -f3)"
    [[ $mode == group ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=ntlmssp,credentials=$creds,vers=3.0,uid=$uid,gid=$gid,file_mode=0660,dir_mode=0775 ||
                return 5
    }
    
    return 0
}

mountCIFSkrb5(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    mode=${1:-service} # service|group|unmount

    realm=LIME
    server=dc1.lime.lan
    share=SMBdata
    mnt=/mnt/smb-data-01
    svc=svc-smb-rw
    mkdir -p $mnt || return 3
    uid="$(id -u $svc)"

    [[ $mode == unmount ]] && {
        umount $mnt
        return $?
    }
    echo "ℹ️ Mount a CIFS share from RHEL host ($(hostname -f)) for '$mode' access using Kerberos for AuthN."
 
    # Allow R/W access by only AD User 'svc-smb-rw' 
    gid="$(id -g $svc)"
    [[ $mode == service ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=krb5,vers=3.0,cruid=$uid,uid=$uid,gid=$gid,file_mode=0640,dir_mode=0775 ||
                return 4
    }
    
    # Allow R/W access by all members of AD Group 'ad-smb-admins'
    gid="$(getent group ad-smb-admins |cut -d: -f3)"
    [[ $mode == group ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=krb5,vers=3.0,cruid=$uid,uid=$uid,gid=$gid,file_mode=0660,dir_mode=0775 ||
                return 5
    }
    
    return 0

}

[[ $1 ]] || {
    cat $BASH_SOURCE
    exit
}
pushd "${BASH_SOURCE%/*}" >/dev/null 2>&1 || pushd . >/dev/null 2>&1 || return 1
"$@" || echo "❌  ERR: $?"
popd >/dev/null 2>&1

