# NetApp ONTAP dual-protocol share having NTFS-first security

Window and Linux Access

---

# Q:

Regarding a NetApp export that allows both smb and nfs protocols on a domain having Windows Server as the domain controller for both Windows and RHEL 8 hosts, users and groups, and network security forbidding insecure Windows authentication schemes, how would we mount the share from a RHEL host and authenticate for access by a domain-scoped service account?

# A:

This is a classic enterprise scenario combining NetApp, Active Directory, and Linux—with the added constraint of Kerberos-only authentication (no NTLM). You have two viable approaches: NFSv4 with Kerberos or CIFS/SMB with Kerberos. Both require the RHEL host to participate in the AD realm and use a keytab for non-interactive service account authentication.

## Prerequisites (Both Approaches)

**1. Join RHEL to AD Domain**

```bash
# Install required packages:
# 1. AD join
dnf install -y realmd sssd oddjob oddjob-mkhomedir adcli krb5-workstation

# 2. Then add one of:
dnf install -y nfs-utils            # for NFSv4
dnf install -y cifs-utils keyutils  # for CIFS

# Discover and join domain by realm/sssd
realm discover YOURDOMAIN.COM
realm join -U admin_user YOURDOMAIN.COM

# Verify
realm list
id somedomainuser@yourdomain.com
```
- If AD join by `winbind` instead of `sssd`, 
  then install `samba-common-tools` also.

**2. Create a Keytab for the Service Account**

On the Windows DC (or via AD admin tools), create a keytab using `ktpass`:

```powershell
ktpass -princ svc_netapp@YOURDOMAIN.COM -mapuser YOURDOMAIN\svc_netapp -pass 'ServiceAccountPassword' -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -out svc_netapp.keytab
```

Transfer `svc_netapp.keytab` securely to the RHEL host (e.g., `/etc/krb5.keytab.svc_netapp`) with restrictive permissions:

```bash
chmod 600 /etc/krb5.keytab.svc_netapp
chown root:root /etc/krb5.keytab.svc_netapp
```

---

## Option 1: NFSv4 with Kerberos (Recommended for Linux-native workflows)

This is generally cleaner for Linux hosts and provides strong security with `sec=krb5p` (encryption + integrity).

**RHEL Configuration:**

```bash
# Install NFS utilities
dnf install -y nfs-utils

# Enable and start required services
systemctl enable --now nfs-client.target
systemctl enable --now gssproxy
```

**Configure gssproxy for the service account** (`/etc/gssproxy/99-nfs-service.conf`):

```ini
[service/nfs-client]
  mechs = krb5
  cred_store = keytab:/etc/krb5.keytab.svc_netapp
  cred_store = ccache:FILE:/var/lib/gssproxy/clients/krb5cc_nfs
  allow_any_uid = yes
  euid = 0
```

```bash
systemctl restart gssproxy
```

**Mount the share:**

```bash
# Obtain initial ticket (or let gssproxy handle it)
kinit -k -t /etc/krb5.keytab.svc_netapp svc_netapp@YOURDOMAIN.COM

# Mount with Kerberos security
mount -t nfs4 -o sec=krb5p,vers=4.1 netapp-server:/export/share /mnt/netapp
```

**For persistent mounts** (`/etc/fstab`):

```
netapp-server:/export/share  /mnt/netapp  nfs4  sec=krb5p,vers=4.1,_netdev  0 0
```

You'll need a systemd service or cron job to refresh the ticket before expiration:

```bash
# /etc/cron.d/krb5-refresh
0 */4 * * * root kinit -k -t /etc/krb5.keytab.svc_netapp svc_netapp@YOURDOMAIN.COM
```

---

## Option 2: CIFS/SMB with Kerberos

If you need SMB semantics or the export is primarily CIFS-oriented:

```bash
dnf install -y cifs-utils keyutils
```

**Configure request-key for CIFS** (`/etc/request-key.d/cifs.spnego.conf`):

```
create  cifs.spnego  *  *  /usr/sbin/cifs.upcall -c %k
```

**Mount with Kerberos:**

```bash
# Get ticket first
kinit -k -t /etc/krb5.keytab.svc_netapp svc_netapp@YOURDOMAIN.COM

# Mount - note sec=krb5 (no NTLM)
mount -t cifs -o sec=krb5,cruid=0,multiuser //netapp-server/share /mnt/netapp
```

**For persistent mounts with credentials** (`/etc/fstab`):

```
//netapp-server/share  /mnt/netapp  cifs  sec=krb5,cruid=0,multiuser,_netdev  0 0
```

---

## Key Points for Your Security Requirements

Since insecure auth is forbidden, ensure `/etc/krb5.conf` enforces strong crypto:

```ini
[libdefaults]
    default_realm = YOURDOMAIN.COM
    dns_lookup_realm = true
    dns_lookup_kdc = true
    default_tgs_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
    default_tkt_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
    permitted_enctypes = aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96
```

Also verify the NetApp export policy allows your host's IP and the appropriate auth flavors (`krb5`, `krb5i`, `krb5p` for NFS; Kerberos for CIFS).


---

# Q: 

`cifs-utils` vs. `samba-common-tools`

# A:

**What actually needs what:**

| Component | Required For |
|-----------|--------------|
| `realmd`, `adcli`, `sssd` | AD domain join and identity mapping |
| `krb5-workstation` | Kerberos tools (`kinit`, `klist`, `ktutil`) |
| `nfs-utils`, `gssproxy` | NFSv4 + Kerberos |
| `cifs-utils`, `keyutils` | CIFS + Kerberos |

`samba-common-tools` provides the `net` command, which is useful if you're doing `net ads join` (the older Samba-based join method) or want diagnostic commands like `net ads testjoin` or `net ads info`. But with the modern `realmd`/`adcli` approach, it's unnecessary for the join itself.

You'd only need it if you were running an actual Samba server (file sharing from the RHEL host) or preferred winbind over SSSD for identity resolution—neither of which applies here.

So for a minimal install:

```bash
# AD join
dnf install -y realmd sssd oddjob oddjob-mkhomedir adcli krb5-workstation

# Then add one of:
dnf install -y nfs-utils            # for NFSv4
dnf install -y cifs-utils keyutils  # for CIFS
```

---

# Q:

What is the most fitting K8s CSI provider here for dynamic PV provisioning of this ONTAP share?

# A:

**NetApp Trident** is the clear choice &mdash;it's NetApp's own CSI driver purpose &mdash;built for ONTAP and supports dynamic NFS provisioning with full integration into NetApp features (snapshots, clones, QoS, storage efficiency).

```bash
# Install via Helm
helm repo add netapp-trident https://netapp.github.io/trident-helm-chart
helm install trident netapp-trident/trident-operator -n trident --create-namespace
```

## Backend Configuration

```yaml
apiVersion: trident.netapp.io/v1
kind: TridentBackendConfig
metadata:
  name: ontap-nas
  namespace: trident
spec:
  version: 1
  storageDriverName: ontap-nas
  managementLIF: 10.0.0.1
  dataLIF: 10.0.0.2
  svm: your_svm
  credentials:
    name: ontap-credentials  # Secret with username/password
```

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: netapp-nfs
provisioner: csi.trident.netapp.io
parameters:
  backendType: ontap-nas
reclaimPolicy: Retain
allowVolumeExpansion: true
```

## The Kerberos Wrinkle

Here's the catch: Trident provisions volumes and manages exports, but **Kerberos authentication in pods is a separate challenge**. Trident itself authenticates to ONTAP's management plane (via credentials in a Secret), but the *pod-to-NFS* data path security is different.

Your options:

| Approach | Trade-off |
|----------|-----------|
| `sec=sys` with tight export policies | Simpler; relies on network/IP trust within cluster |
| `sec=krb5*` with per-pod keytabs | Complex; each pod needs keytab injection + ticket refresh sidecar |
| Node-level Kerberos | Nodes authenticate; pods inherit via UID mapping |

For most internal K8s clusters, the pragmatic path is `sec=sys` with ONTAP export policies restricting access to your pod/node CIDR, since the cluster network is already a trust boundary. Full per-pod Kerberos is doable but operationally heavy—you'd need an init container or sidecar handling `kinit` with mounted keytabs.

Is the Kerberos requirement specifically for pod-level auth, or would node-level trust with strict export policies satisfy your security model?

---

# Q: 

A particular use case is for RHEL/K8s/gitlab-runner access to  an existing production store on Windows, which is the NetApp share discussed above. That is, this is a simpler, static provisioning that neither needs nor would be allowed the admin level service account into ONTAP. The concern there (Trident CSI) is that it requires much more RBAC than is needed for this one static, pre-existing store. In that case, which would be the best Kubernetes CSI provisioner?

# A:

For a single static, pre-existing share, you likely don't need a CSI driver at all. Native Kubernetes NFS volumes handle this cleanly with zero additional cluster components.

## Simplest: Static PV/PVC (No CSI)

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: gitlab-runner-store
spec:
  capacity:
    storage: 100Gi  # Informational; not enforced for NFS
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  nfs:
    server: netapp-server.yourdomain.com
    path: /export/gitlab-share
  mountOptions:
    - nfsvers=4.1
    - sec=krb5p  # if node-level Kerberos is configured
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: gitlab-runner-store
  namespace: gitlab
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  volumeName: gitlab-runner-store  # Binds directly to the PV
```

No RBAC beyond standard PV/PVC permissions. No operator. No CRDs.

## If You Prefer CSI Consistency

The **kubernetes-csi/csi-driver-nfs** is minimal and doesn't touch ONTAP management APIs—it just mounts NFS like the in-tree driver but via CSI:

```bash
helm repo add csi-driver-nfs https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
helm install csi-driver-nfs csi-driver-nfs/csi-driver-nfs -n kube-system
```

Then static provisioning:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: gitlab-runner-store
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  csi:
    driver: nfs.csi.k8s.io
    volumeHandle: gitlab-runner-store  # Unique identifier
    volumeAttributes:
      server: netapp-server.yourdomain.com
      share: /export/gitlab-share
  mountOptions:
    - nfsvers=4.1
```

The CSI driver's RBAC is scoped to node-level mount operations—no cluster-admin style permissions like Trident needs for provisioning.

## Recommendation

For one static share with GitLab Runner, the native NFS PV is the right fit. It's declarative, auditable, and adds no moving parts. The CSI driver only adds value if you anticipate managing multiple NFS shares and want a uniform CSI interface across storage backends.

# Q:

All attempts to mount at host (RHEL 8) by NFS failed to achieve read/write access. Kubernetes nfs provisioner had same failure to access.

# A:
This is a common pain point with dual-protocol NetApp shares—especially when the volume was originally provisioned for Windows/CIFS. A few likely culprits:

## Most Probable: Volume Security Style

If the volume/qtree uses **NTFS security style** (typical for Windows-first shares), NFS clients hit permission issues because access is evaluated via Windows ACLs, and Unix UID/GID don't map to AD SIDs without explicit configuration.

Check on the NetApp (via CLI or System Manager):

```
volume show -vserver <svm> -volume <vol> -fields security-style
qtree show -vserver <svm> -fields security-style
```

If it shows `ntfs`, NFS will struggle without name-mapping rules.

## Diagnostic Steps from RHEL

```bash
# Basic mount test (as root)
mount -t nfs4 -o vers=4.1,sec=sys netapp-server:/export/share /mnt/test

# Check what you get
ls -ln /mnt/test        # Note numeric UID/GID
touch /mnt/test/probe   # Test write

# If mount works but write fails, it's permissions/mapping
# If mount fails entirely, it's export policy or network
```

What error are you seeing exactly? Likely one of:
- `Permission denied` on write → ownership/ACL mapping issue
- `access denied by server` on mount → export policy
- `nobody:nobody` ownership on files → ID mapping failure

## Quick Workarounds to Test

**1. Check export policy allows rw:**
```
export-policy rule show -vserver <svm> -policyname <policy>
```
Ensure your client IP/subnet has `rw` access and appropriate `superuser` setting (e.g., `sys` or `any`).

**2. Test with anon mapping (temporary diagnostic):**
On NetApp, if the export rule has `-anon` set to a Unix UID that has write access, root-squashed clients map there.

**3. The real fix for dual-protocol:**
Either change security style to `mixed`/`unix` (disruptive if Windows ACLs are in use), 
or configure **name-mapping** on the SVM so Unix UIDs resolve to AD users:

```
vserver name-mapping create -vserver <svm> -direction unix-win -position 1 -pattern root -replacement DOMAIN\\Administrator
```

---

What's the actual error message or behavior you're seeing? 
And do you have visibility into the NetApp export policy and volume security style?

---

# Q:

Mounting that Windows-first share at RHEL  host was successful using the `cifs-utils` package, and by `sys=krb5`, but the test was a regular domain user. Attempting same with that domain-scoped service account  failed by the lack of ticket. Might it be best here to pursue the `csi-driver-smb` scheme for Kubernetes PV?

FIPS and STIG requirements of the private (RFC-1918) network forbid NTLM outright. NetApp SMEs are unable to provide access to that particular share at Linux hosts by NFS. Hence the CIFS/SMB considerations.

# A:

That's a hard constraint then—Kerberos is the only path, which means __node-level ticket management__ is unavoidable for CSI-based mounts.

## Practical Architecture

```
┌─────────────────────────────────────────────────────┐
│  K8s Node                                           │
│  ┌─────────────────┐    ┌────────────────────────┐  │
│  │ DaemonSet       │    │ /etc/krb5.keytab.svc   │  │
│  │ (kinit refresh) │───▶│ /tmp/krb5cc_svc        │  │
│  └─────────────────┘    └───────────┬────────────┘  │
│                                     │               │
│  ┌─────────────────┐    ┌───────────▼────────────┐  │
│  │ csi-driver-smb  │───▶│ mount.cifs sec=krb5    │  │
│  │ (node plugin)   │    │ uses node ccache       │  │
│  └─────────────────┘    └───────────┬────────────┘  │
│                                     │               │
│  ┌─────────────────┐                │               │
│  │ GitLab Runner   │◀───────────────┘               │
│  │ Pod             │   (mounted PV)                 │
│  └─────────────────┘                                │
└─────────────────────────────────────────────────────┘
```

## Implementation

**1. Keytab Secret**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: krb5-keytab
  namespace: kube-system
type: Opaque
data:
  svc.keytab: <base64-encoded-keytab>
```

**2. DaemonSet for Ticket Refresh**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: krb5-ticket-refresher
  namespace: kube-system
spec:
  selector:
    matchLabels:
      app: krb5-ticket-refresher
  template:
    metadata:
      labels:
        app: krb5-ticket-refresher
    spec:
      hostPID: false
      containers:
        - name: kinit
          image: registry.access.redhat.com/ubi8/ubi-minimal:latest
          command:
            - /bin/sh
            - -c
            - |
              dnf install -y krb5-workstation && \
              cp /secrets/svc.keytab /host-keytab/svc.keytab && \
              chmod 600 /host-keytab/svc.keytab && \
              while true; do
                kinit -k -t /host-keytab/svc.keytab svc_gitlab@YOURDOMAIN.COM -c /host-ccache/krb5cc_0
                chmod 644 /host-ccache/krb5cc_0
                sleep 14400  # 4 hours; adjust to ticket lifetime
              done
          volumeMounts:
            - name: keytab-secret
              mountPath: /secrets
              readOnly: true
            - name: host-keytab
              mountPath: /host-keytab
            - name: host-ccache
              mountPath: /host-ccache
          securityContext:
            privileged: false
            runAsUser: 0
      volumes:
        - name: keytab-secret
          secret:
            secretName: krb5-keytab
        - name: host-keytab
          hostPath:
            path: /etc/krb5-gitlab
            type: DirectoryOrCreate
        - name: host-ccache
          hostPath:
            path: /tmp
            type: Directory
```

**3. Configure `cifs.upcall` on Nodes**

Nodes need `/etc/request-key.conf` or `/etc/request-key.d/cifs.spnego.conf` pointing to the right ccache. 
This typically requires node-level config (MachineConfig on OpenShift, or baked into your RHEL image):

```
create cifs.spnego * * /usr/sbin/cifs.upcall -k %k
```

And in `/etc/krb5.conf`:

```ini
[libdefaults]
    default_ccache_name = FILE:/tmp/krb5cc_0
```

**4. PV with sec=krb5**

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: gitlab-runner-store
spec:
  capacity:
    storage: 100Gi
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  mountOptions:
    - sec=krb5
    - dir_mode=0775
    - file_mode=0664
  csi:
    driver: smb.csi.k8s.io
    volumeHandle: gitlab-runner-store
    volumeAttributes:
      source: //netapp-server.yourdomain.com/share
```

Note: no `nodeStageSecretRef` needed—auth comes from the node's credential cache.

---

## Caveats

- Node-level state makes this less "pure" K8s but it's the only viable path with your constraints
- The DaemonSet needs to start before any pod tries to mount
- Ticket lifetime vs. refresh interval needs tuning
- If nodes aren't domain-joined, DNS/Kerberos realm resolution must still work

Is this a standard RHEL 8 K8s cluster, 
or OpenShift (where MachineConfig would be the cleaner path for node-level krb5.conf)?