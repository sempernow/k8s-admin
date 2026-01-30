#  K8s `hostPath` type mount of the host's CIFS type mount 

## TL;DR

Success! With the SMB share mounted at each node.

## SMB/CIFS Access from Kubernetes via `hostPath`

### 1. Install the required tools

```bash
dnf install cifs-utils krb5-workstation
```

### 2. Provision Kerberos user (`keytab`), tickets (`kinit`) and renewal (`systemd`)

Reference:

- __`smb-krb5-rhel-and-k8s`__ ([MD](../smb-krb5-rhel-and-k8s.md)|[HTML](../smb-krb5-rhel-and-k8s.html))
- [__`csi-driver-smb.sh`__](../csi-driver-smb.sh)

### 3. Host mount 

Use utilities of `cifs-utils` and `krb5-workstation` 
package utilities to mount the SMB/CIFS share at each node 
by service account (AD user) via Kerberos AuthN.

Mount (manually or by `/etc/fstab` entry)
   
```bash
mount -t cifs //dc1.lime.lan/SMBData /mnt/smb-data-01 \
    -o sec=krb5,vers=3.0,cruid=322203108,uid=1001,gid=1001,file_mode=0640,dir_mode=0775
```
- UID/GID nedn't match its AD user;  
  there are no SID-UID mappings here;  
  only the Kerberos user, `cruid`, matters for AuthN/AuthZ.

### 4. Apply the Pod spec

```bash
kubectl apply -f smb-via-hostpath-pod.yaml
```
- [__`smb-via-hostpath-pod.yaml`__](./smb-via-hostpath-pod.yaml)

