# `csi-driver-smb` : Pod-managed Kerberos  

This solution has some ticket management remaining at the node level.

##### Practical Architecture

```text
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
│  │ PV-Consumer     │◀───────────────┘               │
│  │ Pod             │   (mounted PV)                 │
│  └─────────────────┘                                │
└─────────────────────────────────────────────────────┘
```


##### Implementation

**1. Keytab Secret**

Create a keytab file for the AD service account 
(`svc-smb-rw`) used to mount the CIFS share,
and then create a K8s Secret for it:

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

Nodes need `/etc/request-key.conf` or `/etc/request-key.d/cifs.spnego.conf` pointing to the right ccache. This typically requires node-level config (MachineConfig on OpenShift, or baked into your RHEL image):

```
create cifs.spnego * * /usr/sbin/cifs.upcall -k %k
```

And in __`/etc/krb5.conf`__:

```ini
[libdefaults]
    default_ccache_name = FILE:/tmp/krb5cc_0
```

**4. PV with `sec=krb5`**

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
      source: //server.adomain.com/share
```

Note: no `nodeStageSecretRef` needed—auth comes from the node's credential cache.

##### Caveats

- Node-level state makes this less "pure" K8s but it's the only viable path with your constraints
- The DaemonSet needs to start before any pod tries to mount
- Ticket lifetime vs. refresh interval needs tuning
- If nodes aren't domain-joined, DNS/Kerberos realm resolution must still work



