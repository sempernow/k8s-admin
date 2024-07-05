#!/usr/bin/env bash
###############################################################################
# Provision NFSv4.2 client having AD integration and Kerberos authentication.
#
# https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_different_types_of_servers/deploying-an-nfs-server_deploying-different-types-of-servers
#
# ARGs: SERVER_FQDN_OR_IPv4  SERVER_MOUNT  LOCAL_MOUNT  DOMAIN_CONTROLLER_FQDN
###############################################################################
nfs_srv=$1
nfs_mnt=$2
local_mnt=$3
dc=$4

# Prerequisites
[[ "$4" ]] || exit 1
[[ "$1" =~ $(hostname) ]] && exit 2
[[ "$(id -un)" == 'root' ]] || exit 3
systemctl is-active sssd.service || exit 4 

# Installs
systemctl is-active nfs-client.target || {
    systemctl disable --now nfs-client.target rpc-gssd rpcbind nfs-idmapd chronyd
    dnf -y update &&
        dnf install -y nfs-utils rpcbind krb5-workstation chrony authselect
        # NFSv4 : nfs-idmapd required if using names instead of UID:GID
        # NFSv3 : rpcbind required by RPC services (dependencies)
}
# Add nfsanon (matching server options anonuid,anongid) as UID:GID of all orphaned dirs/files.
# NFSv4 does not support anonuid/anongid, and Kerberos does not allow anonymous
id=50000
name=nfsanon
getent group $name || groupadd -g $id $name
id $name || useradd -u $id -g $name -s /sbin/nologin -d /dev/null $name

# Add NFS-server export (once)
umount $local_mnt
sec='sec=krb5p:krb5i:krb5:sys'  # Server setting allows any
sec='sec=sys'                   # Downgrade that as needed
mkdir -p $local_mnt
# Temporarily
#mount -t nfs4 -o vers=4.2 $nfs_srv:$nfs_mnt/ $local_mnt/
# Persistently
# NFSv4 : Does *not* abide server's anonymous UID:GID settings (anonuid,anongid)
sed -i "\,$nfs_srv:$nfs_mnt,d" /etc/fstab
grep "$nfs_srv:$nfs_mnt" /etc/fstab ||
    echo "$nfs_srv:$nfs_mnt $local_mnt nfs4 defaults,vers=4.2,$sec,_netdev,auto 0 0" |tee -a /etc/fstab

# Time synch with DC is essential for Kerberos
cat /etc/chrony.conf |grep $dc ||
    echo "server $dc iburst" |sudo tee -a /etc/chrony.conf

authselect current |grep sssd &&
    authselect current |grep with-mkhomedir || {
        authselect select sssd with-mkhomedir --backup pre-nfs-client-config &&
            authselect check || exit 33
     } 

systemctl daemon-reload
systemctl enable --now nfs-client.target rpc-gssd rpcbind nfs-idmapd chronyd

mount -a

systemctl is-active firewalld &&
    firewall-cmd --add-service={mountd,nfs,ntp,rpc-bind} --permanent &&
        firewall-cmd --reload

