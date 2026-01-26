#  K8s hostPath mount of host CIFS mount 

1. Use utilities of `cifs-utils` and `krb5-workstation` packages 
to mount the SMB/CIFS share at each node 
by service account (AD user) via Kerberos AuthN.

2. Have Pods mount that using `hostPath`

## TL;DR

Success 

## SMB/CIFS Access from Kubernetes via `hostPath`

Success! With the SMB share mounted at each node, 
have pod mount it as `hostPath`:


### Prerequisites (each node)

1. **Directory permissions**
   ```bash
   chmod 0701 /var/lib/kubelet
   ```

2. **Kerberos ticket cache for CSI** (even though we're using hostPath, keep this for future CSI attempts)
   ```bash
   mkdir -p /var/lib/kubelet/kerberos
   chown svc-smb-rw: /var/lib/kubelet/kerberos
   ```

3. **systemd service** `/etc/systemd/system/svc-smb-rw-kinit.service`
   ```ini
   [Unit]
   Description=Renew Kerberos ticket for svc-smb-rw
   After=network-online.target

   [Service]
   Type=oneshot
   User=svc-smb-rw
   Environment=KRB5CCNAME=FILE:/var/lib/kubelet/kerberos/krb5cc_322203108
   ExecStart=/usr/bin/kinit -k -t /etc/svc-smb-rw.keytab svc-smb-rw@LIME.LAN
   ExecStartPost=/bin/bash -c 'KRB5CCNAME=KCM: /usr/bin/kinit -k -t /etc/svc-smb-rw.keytab svc-smb-rw@LIME.LAN'
   ```

4. **Host mount** (fstab or manual)
   ```bash
   mount -t cifs //dc1.lime.lan/SMBData /mnt/smb-data-01 \
       -o sec=krb5,vers=3.0,cruid=322203108,uid=322203108,gid=322200513,file_mode=0640,dir_mode=0775
   ```
   - Consider changing `uid` and `gid` to `1001`; needn't match AD configuration; there is no SID-UID mappings here; it's the `cruid` alone that matters.

### Pod spec

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: smb-pod
  namespace: smb
spec:
  containers:
    - name: app
      image: busybox
      command: ["sleep", "3600"]
      volumeMounts:
        - name: smb-data
          mountPath: /data
      securityContext:
        runAsUser: 322203108
        runAsGroup: 322200513
  volumes:
    - name: smb-data
      hostPath:
        path: /mnt/smb-data-01
        type: Directory
```
