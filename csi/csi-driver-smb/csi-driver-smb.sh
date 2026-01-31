#!/usr/bin/env bash
########################################################################
# Kubernetes CSI : CSI Driver SMB : Install by Helm
# - A CSI driver to access SMB Server on both Linux and Windows nodes.
# - Access any SMB/CIFS share : NetApp, Samba, Windows Server, ... .
# - https://github.com/kubernetes-csi/csi-driver-smb 
########################################################################

installTools(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    dnf install -y cifs-utils krb5-workstation openldap-clients
}

chart=csi-driver-smb
ver=1.19.1
archive=${chart}-$ver.tgz
base=https://github.com/kubernetes-csi/csi-driver-smb/raw/refs/heads/master/charts
url=$base/v$ver/$archive
release=$chart
template=helm.template
ns=smb

values=values.mod.yaml

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
    kubectl -n $ns get secret,pod,pvc,pv -l smb
}
manifestTeardown(){
    # Deploy with defaults first
    kubectl delete -f $template.yaml
    kubectl delete ns $ns
}

## Usage: krbKeytabInstall <username>  
## Configure host for SMB-user AuthN by Kerberos (sec=krb5)
## - Idempotent
krbKeytabInstall(){
    ## Requires the (AD) provisioned SMB user, and their keytab file at ~/$user.keytab
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $1 ]] || return 2
    [[ -f ${1}.keytab ]] || return 3
    id -u $1 || return 4
    user="$1"
    target=/etc/${user}.keytab
    ls -hl $target 2>/dev/null && {
        echo "ℹ️ NO CHANGE : keytab file '$target' was ALREADY installed."
        
        return 0
    }
    cp ${user}.keytab $target
    chown $user: $target
    chmod 600 $target
    ls -hl $target 
}
## Usage: krbTktService <username> <realm_fqdn> [OVERWRITE(regardless of status)]
## Creates systemd service and timer for periodic Kerberos ticket (cache) renewals.
## - No changes if timer status is "active", unless OVERWRITE param (*any* $3) is set.
krbTktService() {
    local user="$1"
    local realm="$2"
    local overwrite="$3"
    
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $realm ]] || return 2
    systemctl is-active ${user}-kinit.timer && [[ ! $overwrite ]] && {
        echo "ℹ️ NO CHANGE : ${user}-kinit.timer is ALREADY active"

        return 0
    }
    ## Destroy KCM-based cache of declared AD user
    sudo -u $user kdestroy
    ## Destroy file-based cache of declared AD user
    kdestroy -c /var/lib/kubelet/kerberos/krb5cc_$(id $user -u)

    ## Uncomment `sudo ...` statements to acquire now, else wait OnActiveSec (See timer).
    # Acquire KCM-based ticket for declared AD user:
    #sudo -u $user kinit -k -t /etc/$user.keytab $user@LIME.LAN
    # List all ticket cache of declared user
    #sudo -u $user klist

    echo -e "\nℹ️ Creating ${user}-kinit.service + .timer (systemd) so that user '$user' has periodic Kerberos ticket renewal"

    systemctl disable --now ${user}-kinit.timer

    ## Service is static : Do *not* enable
	tee /etc/systemd/system/${user}-kinit.service <<-EOH
	# /etc/systemd/system/${user}-kinit.service
	[Unit]
	Description=Renew Kerberos ticket for ${user}
	After=network-online.target

	[Service]
	Type=oneshot
	User=$user
	# 1. Refresh file cache for Linux Kernel (CIFS/SMB client) integration with K8s CSI Driver 
	Environment=KRB5CCNAME=FILE:/var/lib/kubelet/kerberos/krb5cc_$(id $user -u)
	ExecStart=/usr/bin/kinit -k -t /etc/${user}.keytab ${user}@$realm

	# 2. Refresh KCM cache of SSSD's KCM (Kerberos Credential Manager) for Host-level tools (klist, ldapsearch, ssh) 
	ExecStartPost=/bin/bash -c 'KRB5CCNAME=KCM: /usr/bin/kinit -k -t /etc/${user}.keytab ${user}@$realm'
	EOH

    ## Timer : Do enable
	tee /etc/systemd/system/${user}-kinit.timer <<-EOH
	# /etc/systemd/system/${user}-kinit.timer 
	[Unit]
	Description=Renew Kerberos ticket every 3 hours

	[Timer]
	# Trigger shortly after timer is enabled
	OnActiveSec=1min
	# Trigger shortly after boot
	OnBootSec=1min
	# Renew every 3 hours after last run : Kerberos ticket (cache) expiry is 10 hrs.
	OnUnitActiveSec=3h
	# Catch up missed runs after restart, sleep, shutdown, etc.
	Persistent=true

	[Install]
	WantedBy=timers.target
	EOH
    
    systemctl daemon-reload
    systemctl enable --now ${user}-kinit.timer

    ## Allow Pod (cruid) access : Should not be necessary : proper file owner set by "User" param of service unit file.
    #group=ad-smb-admins # *** HARD CODED *** 
    #chown $user:$group /var/lib/kubelet/kerberos/krb5cc_$(id $user -u)
    #chown $user: /var/lib/kubelet/kerberos/krb5cc_$(id $user -u)
    #chmod 600 /var/lib/kubelet/kerberos/krb5cc_$(id $user -u)
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

## Usage: smbTest apply|delete
## Test Pod access to csi-driver-smb mount : PVC to PV of cifs/smb mount
smbtestns=default #$ns
smbTest(){
    ## hostPath
    kubectl $1 -f smb-via-hostpath/pod.yaml 
    ## csi-driver-smb
    #kubectl -n $smbtestns $1 -f csi-krb5-host-managed.yaml
}
smbTestGet(){
    # Deploy with defaults first
    kubectl -n $smbtestns get secret,pod,pvc,pv -l smb
    kubectl -n $smbtestns logs -l smb ||
        kubectl -n $smbtestns describe pod -l smb
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

[[ $1 ]] || {
    cat $BASH_SOURCE
    exit
}
pushd "${BASH_SOURCE%/*}" >/dev/null 2>&1 || pushd . >/dev/null 2>&1 || return 1
"$@" || echo "❌  ERR: $?"
popd >/dev/null 2>&1

