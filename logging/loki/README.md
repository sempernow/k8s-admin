# [Grafana : Loki](https://github.com/grafana/loki/tree/main/production/helm/loki)

## TL;DR

Loki default install is __broken by design__. 
It presumes a completely configured cloud-storage backend.

Yet **Grafana Loki + Fluent Bit** as a lighter alternative to EFK. 
oki indexes *labels only* (not full log content), so it’s cheaper and easier to run.


## Helm `grafana/loki`

- https://github.com/grafana/helm-charts : Helm chart
- https://github.com/grafana/loki
- https://grafana.com/oss/loki/
- https://artifacthub.io/packages/helm/grafana/loki


```bash
v=6.29.0 # App Version: 3.4.2
repo=grafana
chart=loki
values=values.on-prem-nfs-minimal.yaml
helm repo add $repo https://grafana.github.io/helm-charts --force
helm upgrade $chart $repo/$chart --install --version $v -f $values

```
- [`values.on-prem-nfs-minimal.yaml`](values.on-prem-nfs-minimal.yaml)
    - From ChatGPT. Isn't valid (see below)
__ERR__

```bash
☩ helm template $repo/$chart --values $values

Error: execution error at (loki/templates/validate.yaml:19:4): Cannot run scalable targets (backend, read, write) or distributed targets without an object storage backend.

```
- …means that your `values.on-prem-nfs-minimal.yaml` is enabling scalable mode (distributed components: read, write, backend) but does not define an object storage backend like S3, GCS, Azure, or even a local MinIO.

The error: 

```
Cannot run scalable targets (backend, read, write) or distributed targets without an object storage backend.
```

means that our values file, 
[`values.on-prem-nfs-minimal.yaml`](values.on-prem-nfs-minimal.yaml), 
is enabling **scalable mode** 
(distributed components: `read`, `write`, `backend`),
but **does not define an object-storage backend** 
(such as S3, GCS, Azure, or even a __local MinIO__).

---

### 🔧 Solution: Disable Scalable Mode (Enable Monolithic Mode)

We're running **on-prem with NFS** and want 
a **minimal, single-binary Loki deployment**, 
so **disable** the scalable components entirely.

__Modify the values__ file:

```yaml
loki:
  isDefault: true

  # Disable distributed mode
  commonConfig:
    replication_factor: 1

  storage:
    type: filesystem
    filesystem:
      directory: /var/loki/chunks

  schemaConfig:
    configs:
      - from: 2020-10-15
        store: boltdb-shipper
        object_store: filesystem
        schema: v11
        index:
          prefix: index_
          period: 24h

singleBinary:
  enabled: true

write:
  enabled: false
read:
  enabled: false
backend:
  enabled: false

# PVC (optional if using NFS-backed volume)
persistence:
  enabled: true
  storageClassName: "nfs-client"
  accessModes:
    - ReadWriteOnce
  size: 10Gi
```

---

### ✅ Validate

After updating the values file, validate with:

```bash
helm template $chart $repo/$chart --version $v -f $values
```

If it renders cleanly, proceed to install or upgrade:

```bash
helm upgrade $chart $repo/$chart --install --version $v -f $values
```
