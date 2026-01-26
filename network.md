# Kubernetes Cluster Network Diagram

```
                              ┌─────────────────────────────────────────────────────────────────────┐
                              │                         EXTERNAL NETWORK                            │
                              │                      192.168.11.0/24 (lime.lan)                     │
                              └─────────────────────────────────┬───────────────────────────────────┘
                                                                │
                                                                │
                              ┌─────────────────────────────────▼───────────────────────────────────┐
                              │           HA LOAD BALANCER (HAProxy + Keepalived)                   │
                              │                                                                     │
                              │   Virtual IP: 192.168.11.11 (kube.lime.lan)                         │
                              │   IPv6 VIP:   fd00:11::100                                          │
                              │                                                                     │
                              │   Ports:  :8443  → K8s API Server                                   │
                              │           :30080 → Ingress HTTP  (NodePort)                         │
                              │           :30443 → Ingress HTTPS (NodePort)                         │
                              │           :8404  → HAProxy Stats                                    │
                              └───────┬─────────────────────┬─────────────────────┬─────────────────┘
                                      │                     │                     │
             ┌────────────────────────┼─────────────────────┼─────────────────────┼────────────────────────┐
             │                        │                     │                     │                        │
             │    ┌───────────────────▼──┐  ┌───────────────▼──────┐  ┌───────────────▼──────┐             │
             │    │   CONTROL PLANE #1   │  │   CONTROL PLANE #2   │  │   CONTROL PLANE #3   │             │
             │    │        (a1)          │  │        (a2)          │  │        (a3)          │             │
             │    │   a1.lime.lan        │  │   a2.lime.lan        │  │   a3.lime.lan        │             │
             │    │   192.168.11.101     │  │   192.168.11.102     │  │   192.168.11.103     │             │
             │    │   (K8S_NODE_INIT)    │  │                      │  │                      │             │
             │    │                      │  │                      │  │                      │             │
             │    │  ┌────────────────┐  │  │  ┌────────────────┐  │  │  ┌────────────────┐  │             │
             │    │  │ kube-apiserver │  │  │  │ kube-apiserver │  │  │  │ kube-apiserver │  │             │
             │    │  │ (port 6443)    │  │  │  │ (port 6443)    │  │  │  │ (port 6443)    │  │             │
             │    │  └────────────────┘  │  │  └────────────────┘  │  │  └────────────────┘  │             │
             │    │  ┌────────────────┐  │  │  ┌────────────────┐  │  │  ┌────────────────┐  │             │
             │    │  │ etcd           │  │  │  │ etcd           │  │  │  │ etcd           │  │             │
             │    │  └────────────────┘  │  │  └────────────────┘  │  │  └────────────────┘  │             │
             │    │  ┌────────────────┐  │  │  ┌────────────────┐  │  │  ┌────────────────┐  │             │
             │    │  │ kube-scheduler │  │  │  │ kube-scheduler │  │  │  │ kube-scheduler │  │             │
             │    │  └────────────────┘  │  │  └────────────────┘  │  │  └────────────────┘  │             │
             │    │  ┌────────────────┐  │  │  ┌────────────────┐  │  │  ┌────────────────┐  │             │
             │    │  │ controller-mgr │  │  │  │ controller-mgr │  │  │  │ controller-mgr │  │             │
             │    │  └────────────────┘  │  │  └────────────────┘  │  │  └────────────────┘  │             │
             │    │                      │  │                      │  │                      │             │
             │    │  eth0 (k8s-external) │  │  eth0 (k8s-external) │  │  eth0 (k8s-external) │             │
             │    └──────────┬───────────┘  └──────────┬───────────┘  └──────────┬───────────┘             │
             │               │                         │                         │                         │
             │    FIREWALL ZONES:                                                                          │
             │    ├─ k8s-external (eth0): Drop by default, allows K8s/Calico traffic                       │
             │    └─ k8s-internal (CNI):  Internal pod traffic                                             │
             │                                                                                             │
             │               │                         │                         │                         │
             │    ┌──────────▼─────────────────────────▼─────────────────────────▼──────────┐              │
             │    │                       CNI POD NETWORK                                   │              │
             │    │                                                                         │              │
             │    │   Options: Calico (BGP) │ Cilium (eBPF) │ Kube-Router                   │              │
             │    │   Pod CIDR:     10.244.0.0/16                                           │              │
             │    │   Pod CIDR v6:  fd00:244::/64                                           │              │
             │    │   Node Mask:    /24 per node                                            │              │
             │    └─────────────────────────────────────────────────────────────────────────┘              │
             │                                                                                             │
             │    ┌─────────────────────────────────────────────────────────────────────────┐              │
             │    │                       SERVICE NETWORK                                   │              │
             │    │                                                                         │              │
             │    │   Service CIDR:    10.96.0.0/12                                         │              │
             │    │   Service CIDR v6: fd00:96::/48                                         │              │
             │    └─────────────────────────────────────────────────────────────────────────┘              │
             │                                                                                             │
             │    KUBERNETES CLUSTER: lime (v1.29.6)                                                       │
             │    CRI: containerd (unix:///var/run/containerd/containerd.sock)                             │
             │    Cgroup Driver: systemd                                                                   │
             │    Hosts: RHEL 8+ / SELinux Enforcing                                                       │
             └─────────────────────────────────────────────────────────────────────────────────────────────┘

    ┌───────────────────────────────────────────────────────────────────────────────────────────────────────┐
    │                                     CLUSTER COMPONENTS                                                │
    ├───────────────────────────────────────────────────────────────────────────────────────────────────────┤
    │                                                                                                       │
    │  INGRESS                    STORAGE (CSI)              OBSERVABILITY           LOGGING                │
    │  ─────────                  ─────────────              ─────────────           ───────                │
    │  ingress-nginx              csi-driver-nfs             metrics-server          Vector + ES + Kibana   │
    │  :30080 (HTTP)              csi-driver-smb (Kerberos)  K8s Dashboard           EFK Stack              │
    │  :30443 (HTTPS)             local-path-provisioner     Prometheus/Grafana      Loki                   │
    │                             Rook/Ceph                                                                 │
    │                                                                                                       │
    └───────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

## Summary

| Component | Value |
|-----------|-------|
| **Domain** | lime.lan |
| **K8s FQDN** | kube.lime.lan |
| **Control Plane VIP** | 192.168.11.11:8443 |
| **Control Nodes** | a1 (.101), a2 (.102), a3 (.103) |
| **Worker Nodes** | None configured (K8S_NODES_WORKER is empty) |
| **Host Network** | 192.168.11.0/24 |
| **Pod Network** | 10.244.0.0/16 |
| **Service Network** | 10.96.0.0/12 |
| **K8s Version** | v1.29.6 |
| **CNI** | Calico (default), Cilium, or Kube-Router |
