#!/usr/bin/env bash
###############################################################################
# Provision NFSv4.2 server having AD integration and Kerberos authentication. 
#
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_different_types_of_servers/deploying-an-nfs-server_deploying-different-types-of-servers
#
# ARGs: SERVER_MOUNT  CLIENT_CIDR  DOMAIN_CONTROLLER_FQDN
###############################################################################
[[ "$3" ]] || exit 1
[[ "$(id -un)" == 'root' ]] || exit 3
share="$1"
cidr="$2"
dc=$3
systemctl is-active nfs-server.service || {
    systemctl disable --now rpcbind nfs-server nfs-mountd rpc-statd chronyd
    dnf update &&
        dnf install -y nfs-utils rpcbind krb5-workstation chrony authselect
        # NFSv3 : rpcbind required by RPC services (dependencies)
}

authselect current |grep sssd &&
    authselect current |grep with-mkhomedir || {
        authselect select sssd with-mkhomedir --backup pre-nfs-server-config &&
            authselect check || exit 33
     } 

# Configure to serve only NFSv3 and NFSv4.2 (idempotent)
sedfile=/tmp/etc.nfs.conf.sed
cat <<EOH |tee $sedfile
/vers3=/c\vers3=y
/vers4=/c\# vers4=y
/vers4.0=/c\vers4.0=n
/vers4.1=/c\vers4.1=n
/vers4.2=/c\vers4.2=y
EOH
sed -i -f $sedfile /etc/nfs.conf
rm -f $sedfile

# Disable NFSv3 : May also disable NFSv4 at clients 
#systemctl mask --now rpc-statd.service rpcbind.service rpcbind.socket
# Undo the mask
#systemctl unmask rpc-statd.service rpcbind.service rpcbind.socket

# if NFSv4 *only*, then configure rpc.mountd (once) to not listen for NFSv3 mount requests.
# dir=/etc/systemd/system/nfs-mountd.service.d/
# [[ -f $dir/v4only.conf ]] || {
# 	mkdir -p $dir
# 	cat <<-EOH |tee $dir/v4only.conf
# 	[Service]
# 	ExecStart=
# 	ExecStart=/usr/sbin/rpc.mountd --no-tcp --no-udp
# 	EOH
# }

# Configuring idmap is not necessary if joined to domain using realm and sssd
# @ /etc/idmapd.conf : Uncomment/Re-declare Domain
#sed -i '/^\(#\)\?Domain = /c\Domain = '$(hostname -d) /etc/idmapd.conf

# Configure the share
mkdir -p "$share"
[[ -d $share ]] || exit 11
umount $share # Should not have been mounted anyway.
chgrp 'ad-linux-users' $share

user=nfsanon
group=ad-nfsanon
chown -R "$user:$group" "$share"

# Set ACLs and such so that owner:group of all current and new dirs/files 
# have same access, and are owned by whichever user created it.
# And deny any access to other.
# (directory mode 2770, and file mode 0660)
chmod -R 2770 $share
setfacl -m d:u::rwx $share
setfacl -m d:g::rwx $share
setfacl -m d:o::--- $share

# Set proper SELinux fcontext for R/W access at container mounts, if applicable.
command -v getenforce >/dev/null 2>&1 &&
    semanage fcontext -a -t public_content_rw_t "${share}(/.*)?" &&
        restorecon -Rv "$share"

# Add nfsanon for server options anonuid,anongid as the UID:GID of all orphaned dirs/files.
# Client hosts should have the matching UID:GID, yet these are *not* mount options of nfs client.
# NFSv4 does not support anonuid/anongid, and Kerberos does not allow anonymous
id=50000
name=nfsanon
getent group $name || groupadd -g $id $name
id $name || useradd -u $id -g $name -s /sbin/nologin -d /dev/null $name
anonid=",anonuid=$id,anongid=$id"
unset anonid # if NFSv4 or Kerberos
opts="rw,sync,sec=krb5p:krb5i:krb5:sys,root_squash,no_subtree_check$anonid"
opts='rw,sync,no_root_squash,no_subtree_check'
sed -i "\,$cidr,d" /etc/exports
cat <<EOH |tee /etc/exports
$share    $cidr($opts)
EOH

# Allow through Linux firewall
systemctl enable --now firewalld &&
    firewall-cmd --add-service={mountd,nfs,ntp,rpc-bind} --permanent &&
        firewall-cmd --reload

# Time synch with DC is essential for Kerberos
cat /etc/chrony.conf |grep $dc ||
    echo "server $dc iburst" |sudo tee -a /etc/chrony.conf

# Apply the NFS configuration
exportfs -ra
systemctl daemon-reload
systemctl enable --now rpcbind nfs-server nfs-mountd rpc-statd chronyd

# Verify (have v. want)
vers="$(cat /proc/fs/nfsd/versions)"
[[ "$vers" =~ '+3 +4 -4.0 -4.1 +4.2' ]] &&
    echo ok ||
        echo "/proc/fs/nfsd/versions : $vers"

# Inspect the running configuration
exportfs -v
find "$share" -type d -execdir stat --format="%04a  %A  %n" {} \;
ls -halZ $share
