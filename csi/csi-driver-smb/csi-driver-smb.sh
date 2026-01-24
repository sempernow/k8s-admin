#!/usr/bin/env bash
########################################################################
# Kubernetes CSI : CSI Driver SMB : Install by Helm
# - A CSI driver to access SMB Server on both Linux and Windows nodes.
# - Access any SMB/CIFS share : NetApp, Samba, Windows Server, ... .
# - https://github.com/kubernetes-csi/csi-driver-smb 
########################################################################

prep(){
    # 1. Pull the chart and extract values.yaml
    chart=csi-driver-smb
    ver=1.19.1
    archive=${chart}-$ver.tgz
    base=https://github.com/kubernetes-csi/csi-driver-smb/raw/refs/heads/master/charts
    url=$base/v$ver/$archive
    release=$chart
    template=helm.template
    ns=smb

    # 1. Get the values file of this version
    [[ -f values.yaml ]] || {
        [[ -f $archive ]] || {
            echo "ℹ️ Pull the chart : $url"
            wget $url ||
                echo "❌ ERR : $?"
        }
        echo "ℹ️ Extract values file"
        # Extract values.yaml to PWD
        tar -xaf $archive $release/values.yaml &&
            mv $chart/values.yaml . &&
                rm -rf $chart ||
                    echo "⚠️ values.yaml is *not* extracted."
    }
    # 2. Generate the K8s-resource manifests (helm template) from chart (local|remote)
    [[ -f helm.template.yaml ]] || {
        echo "ℹ️ Generate the chart-rendered K8s resources : helm template ..."
        #helm -n $ns template $chart |tee $template.yaml # Local chart
        helm -n $ns template $url |tee $template.yaml # Remote chart
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
    
	tee /etc/$1.creds <<-EOH
	username=$1
	password=$2
	domain=$3
	EOH
    chmod 600 /etc/$1.creds
}
keytabInstall(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 1
    cp ${1}.keytab /etc/${1}.keytab
    chown $1: /etc/${1}.keytab
    chmod 600 /etc/${1}.keytab
}
krbTktSetup(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 2

    systemctl disable --now ${1}-kinit.timer
    sleep 2

    # Service is static : Do NOT enable
	tee /etc/systemd/system/${1}-kinit.service <<-EOH
	# /etc/systemd/system/${1}-kinit.service
	[Unit]
	Description=Renew Kerberos ticket for ${1}
	After=network-online.target

	[Service]
	Type=oneshot
	User=${1}
	ExecStart=/usr/bin/kinit -k -t /etc/${1}.keytab ${1}@LIME.LAN
	EOH

    # Timer : Enable
	tee /etc/systemd/system/${1}-kinit.timer <<-EOH
	# /etc/systemd/system/${1}-kinit.timer 
	[Unit]
	Description=Renew Kerberos ticket every 4 hours

	[Timer]
	OnBootSec=1min
	OnUnitActiveSec=4h

	[Install]
	WantedBy=timers.target
	EOH
    
    systemctl daemon-reload
    systemctl enable --now ${1}-kinit.timer
}
krbTktStatus(){
    [[ $1 ]] || return 1

    # Check timer is active and scheduled
    systemctl status ${1}-kinit.timer

    # Check last service run
    systemctl status ${1}-kinit.service --no-pager --full

    # Verify ticket exists
    sudo -u $1 klist
}

mountCIFS(){ 
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 2
    svc=$1
    mode=${2:-service} # service|group|unmount
   
    # 2. Mount a Windows SMB share (regardless of its local filesystem format)
    realm=LIME
    server=dc1.lime.lan
    share=SMBdata
    mnt=/mnt/smb-data-01
    ## Creds only if sec=ntlmssp 
    creds=/etc/$svc.creds
    mkdir -p $mnt || return 4
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
            -o sec=ntlmssp,vers=3.0,credentials=$creds,uid=$uid,gid=$gid,file_mode=0640,dir_mode=0775 ||
                return 5
    }
    
    # Allow R/W access by all members of AD Group 'ad-smb-admins'
    gid="$(getent group ad-smb-admins |cut -d: -f3)"
    [[ $mode == group ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=ntlmssp,vers=3.0,credentials=$creds,uid=$uid,gid=$gid,file_mode=0660,dir_mode=0775 ||
                return 6
    }
    
    return 0
}

mountCIFSkrb5(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 2
    svc=$1
    mode=${2:-service} # service|group|unmount

    realm=LIME
    server=dc1.lime.lan
    share=SMBdata
    mnt=/mnt/smb-data-01
    mkdir -p $mnt || return 3
    uid="$(id -u $svc)"

    [[ $mode == unmount ]] && {
        umount $mnt
        ls -hl $mnt
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
   
    ls -hl $mnt
    
    return 0

}
verifyAccess(){
    [[ $1 ]] || return 1
    sudo -u $1 bash -c '
        target=/mnt/smb-data-01/$(date -Id)-$(id -un)-at-$(hostname -f).txt
        echo $(date -Is) : Hello from $(id -un) @ $(hostname -f) |tee -a $target
        ls -hl $target 
        cat $target 
    '
}

[[ $1 ]] || {
    cat $BASH_SOURCE
    exit
}
pushd "${BASH_SOURCE%/*}" >/dev/null 2>&1 || pushd . >/dev/null 2>&1 || return 1
"$@" || echo "❌  ERR: $?"
popd >/dev/null 2>&1

