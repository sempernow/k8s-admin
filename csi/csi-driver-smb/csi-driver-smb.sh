#!/usr/bin/env bash
########################################################################
# Kubernetes CSI : CSI Driver SMB : Install by Helm
# - A CSI driver to access SMB Server on both Linux and Windows nodes.
# - Access any SMB/CIFS share : NetApp, Samba, Windows Server, ... .
# - https://github.com/kubernetes-csi/csi-driver-smb 
########################################################################

chart=csi-driver-smb
ver=1.19.1
archive=${chart}-$ver.tgz
base=https://github.com/kubernetes-csi/csi-driver-smb/raw/refs/heads/master/charts
url=$base/v$ver/$archive
release=$chart
template=helm.template
ns=smb

values=values.yaml

chartPrep(){
    # 1. Pull the chart and extract values.yaml
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
        helm -n $ns template $url --values $values |
            tee $template.yaml # Remote chart
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

chartNodePrep(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 2
    # Match values setting at: .linux.krb5CacheDirectory  
    # Directory of Kerberos credential cache
    target=/var/lib/kubelet/kerberos 
    echo "ℹ️ Creating krb5CacheDirectory: $target"
	chmod o+x /var/lib/kubelet
	mkdir -p  $target
	chown $1: $target
    chmod 755 $target
}

## Install by Helm 
chartUp(){
    # Chart (URL) version is implicit
    helm upgrade $release $url --install --values $values --namespace $ns --create-namespace --debug
}
chartGet(){
    kubectl -n $ns get deploy,ds,pod,cm,secret,pvc,pv -l app.kubernetes.io/name=csi-driver-smb
}
chartDown(){
    helm -n $ns uninstall $release
}

## Install by Manifest (kubectl)
manifestInstall(){
    # Deploy with defaults first
    kubectl create ns $ns 
    kubectl apply -f $template.yaml
}
manifestGet(){
    kubectl -n $ns get secret,pod,pvc,pv -l cifs
}
manifestTeardown(){
    # Deploy with defaults first
    kubectl delete -f $template.yaml
    kubectl delete ns $ns
}

## Test SMB PV/PVC by mount in Pod (container)
smbTest(){
    # hostPath
    kubectl $1 -f hostpath-method/hostpath-cifs-pod.yaml 
    # csi-driver-smb
    #kubectl $1 -f smb.test.node-managed-ticket.yaml 
}
smbTestGet(){
    # Deploy with defaults first
    kubectl -n default get secret,pod,pvc,pv -l cifs
    kubectl -n default logs -l cifs
}

## Configure host for SMB-user AuthN by NTLMSSP (sec=ntlmssp)
smbSetCreds(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    ## SMB domain ($3) is in NetBIOS format, not SPN; EXAMPLE not EXAMPLE.COM 
    [[ $3 ]] || echo "  USAGE: $FUNCNAME user pass realm 2>&"
    [[ $3 ]] || return 2
    
	tee /etc/$1.creds <<-EOH
	username=$1
	password=$2
	domain=$3
	EOH
    chmod 600 /etc/$1.creds
}

## Configure host for SMB-user AuthN by Kerberos (sec=krb5)
krbKeytabInstall(){
    # Requires the (AD) provisioned SMB user ($1), and their keytab file at ~/$1.keytab
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 2
    [[ -f ${1}.keytab ]] || return 3
    id -u $1 || return 4

    target=/etc/${1}.keytab
    ls -hl $target && {
        echo "ℹ️ NO CHANGE : $target was ALREADY installed."
        
        return 0
    }
    cp ${1}.keytab $target
    chown $1: $target
    chmod 600 $target
}
krbTktService(){
	## User ($1), REALM FQDN ($2)
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $2 ]] || return 2
    systemctl is-active ${1}-kinit.timer && {
        echo "ℹ️ NO CHANGE : ${1}-kinit.timer is ALREADY active"

        return 0
    }
    # Destroy existing KCM-based cache of AD user $1
    sudo -u $1 kdestroy
    # Destroy existing declared cache 
    kdestroy -c /var/lib/kubelet/kerberos/krb5cc_$(id $1 -u)
    # Acquire KCM-based ticket for AD user:
    #sudo -u $1 kinit -k -t /etc/$1.keytab $1@LIME.LAN
    # List all ticket cache of declared user
    sudo -u $1 klist

    echo -e "\nℹ️ Creating ${1}-kinit.service + .timer (systemd) so that user '$1' has periodic Kerberos ticket renewal"

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
	User=$1
	Environment=KRB5CCNAME=FILE:/var/lib/kubelet/kerberos/krb5cc_$(id $1 -u)
	ExecStart=/usr/bin/kinit -k -t /etc/${1}.keytab ${1}@$2

	# 1. Refresh KCM cache for host-level tools : KCM (Kerberos Credential Manager) is of SSSD
	ExecStartPost=/bin/bash -c 'KRB5CCNAME=KCM: /usr/bin/kinit -k -t /etc/${1}.keytab ${1}@$2'

	# 2. Fix permissions so the CSI Driver pod can read the file
	ExecStartPost=+/usr/bin/chmod 644 /var/lib/kubelet/kerberos/krb5cc_$(id $1 -u)
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
    echo -e "\nℹ️ systemd : Status of Kerberos ticket renewal (service and timer) for user '$1'"

    # Check timer is active and scheduled
    echo -e "\n🔍 Timer : Want 'active'"
    systemctl status ${1}-kinit.timer --no-pager --full

    # Check last service run
    echo -e "\n🔍 Service (static) : Want 'inactive'"
    systemctl status ${1}-kinit.service --no-pager --full

    echo -e "\nℹ️ klist : KCM ticket cache for user '$1'"
	sudo -u $1 klist

    # Verify ticket exists
    echo -e "\nℹ️ klist : File-based Kerberos ticket cache for user '$1'"
	ls -ahl /var/lib/kubelet/kerberos/
	sudo klist -c /var/lib/kubelet/kerberos/krb5cc_$(id $1 -u)

}

# Mount functions : Mount a Windows SMB share at Linux 
# - Node and Pod users have access per UID:GID and dir/file mode settings,
#   which vary per mount mode (service|group).
# - The cruid regards only Kerberos AuthN user (on mount).

## Mount SMB share as user $1 using NTLMSSP for AuthN
mountCIFSntlmssp(){ 
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 2
    svc=$1
    mode=${2:-service} # service|group|unmount
   
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
    echo "ℹ️ Mount SMB share as user '$1' for mode '$mode' access to $(hostname):$mnt using NTLMSSP for AuthN."
 
    # Restrict R/W access to (AD) user $1
    gid="$(id -g $1)"
    [[ $mode == service ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=ntlmssp,vers=3.0,credentials=$creds,uid=$uid,gid=$gid,file_mode=0640,dir_mode=0775 ||
                return 5
    }
    
    # Allow R/W access by all members of the declared (AD) group (g)
    g=ad-smb-admins
    gid="$(getent group $g |cut -d: -f3)"
    [[ $mode == group ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=ntlmssp,vers=3.0,credentials=$creds,uid=$uid,gid=$gid,file_mode=0660,dir_mode=0775 ||
                return 6
    }
    
    ls -ahl $mnt
    
    return 0
}
## Mount SMB share as user $1 using Kerberos for AuthN
mountCIFSkrb5(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 2
    svc=$1
    mode=${2:-service} # service|group|unmount

    server=dc1.lime.lan
    share=SMBdata
    mnt=/mnt/smb-data-01
    mkdir -p $mnt || return 3
    cruid="$(id -u $svc)"
    uid=1001

    [[ $mode == unmount ]] && {
        umount $mnt
        ls -hl $mnt
        return $?
    }
    echo "ℹ️ Mount SMB share as user '$1' for mode '$mode' access to $(hostname):$mnt using Kerberos for AuthN."

    # Allow R/W access by only AD User '$1' 
    #gid="$(id -g $svc)"
    gid=$uid
    [[ $mode == service ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=krb5,vers=3.0,cruid=$cruid,uid=$uid,gid=$gid,file_mode=0640,dir_mode=0775 ||
                return 4
    }
    
    # Allow R/W access by all members of AD Group 'ad-smb-admins'
    gid="$(getent group ad-smb-admins |cut -d: -f3)"
    [[ $mode == group ]] && {
        mount -t cifs //$server/$share $mnt \
            -o sec=krb5,vers=3.0,cruid=$cruid,uid=$uid,gid=$gid,file_mode=0660,dir_mode=0775 ||
                return 5
    }
    
    ls -ahl $mnt
    
    return 0
}
verifyAccess(){
    [[ $1 ]] || return 1
    echo "ℹ️ Verify access by $1@$(hostname -f) : $(id $1)"
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

