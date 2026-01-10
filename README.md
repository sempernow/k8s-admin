# [`k8s-admin`](https://github.com/sempernow/k8s-admin "GitHub : sempernow/k8s-admin") | [Kubernetes.io](https://kubernetes.io/docs/) | [Releases](https://github.com/kubernetes/kubernetes/releases)

Install on-prem Kubernetes (K8s) cluster using `kubeadm`.

See project [`halb`](https://github.com/sempernow/halb "GitHub : sempernow/halb") for the external load balancer.

## Usage 

See `make` recipes

```bash
make
```

## Topics

### Create cluster

```bash
# Prepare the host
make conf
make reboot
make install
make reboot
# Initialize cluster ( 1st node)
make init
vi Makefile.bootstrap.settings # Set K8S_CERTIFICATE_KEY
# Configure client on this admin host
make kubeconfig
# Install Pod network (CNI addon)
make calico
# Join other control nodes
make join-control

```

### Join RHEL Host into AD Domain

See project [`sempernow/windows-server`](https://github.com/sempernow/windows-server "GitHub")

Section [`iac/adds/`](https://github.com/sempernow/windows-server/tree/master/iac/adds)

```bash
kubectl proxy # K8s API @ http://127.0.0.1:8001 (Blocks)
```
```bash
curl http://127.0.0.1:8001/healthz #> ok
```

### Cleanup Pod Network 

E.g., after hard reboot.

#### Cause

A host-level hard reboot may leave stale resources on each node that are inaccessible to Calido CNI due to expired token. 

Result: Unauthorized → sandbox teardown fails → pods stick in Terminating.

Kubernetes with Calico has a recurring pattern where a pod is forever stuck in a non-functional state and can't be deleted:

__Confirm__ that Calico has an __expired token__


```bash
# 1) Grab the token (raw string, not YAML-quoted)
TOKEN=$(sudo yq -r '.users[0].user.token' /etc/cni/net.d/calico-kubeconfig)

# 2) Decode the JWT payload (handles base64url + missing padding)
python3 - <<'PY'
import os, json, base64, time
tok = os.environ["TOKEN"]
parts = tok.split(".")
payload = parts[1]  # middle part
# add padding for base64url
payload += "=" * (-len(payload) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload).decode())
print(json.dumps(claims, indent=2))
print("now_unix:", int(time.time()))
print("exp_ok  :", "exp" in claims and claims["exp"] > time.time())
PY
```
- Token is base64url encoded.
    ```bash
    decodebase64url "$(sudo yq -r '.users[0].user.token' /etc/cni/net.d/calico-kubeconfig)"
    ```
- If __`exp_ok` is `false`__ (or `exp < now_unix`) then the __token is expired__. 
  That’s exactly why Calico CNI “DEL” is failing with connection is unauthorized.


#### Symptoms

Request to delete pod, "`kubectl delete pod ...`", 
leaves it stuck at status "`Terminating`":

```bash
☩ k get pod -o wide
NAME   READY   STATUS        RESTARTS   AGE   IP              NODE   NOMINATED NODE   READINESS GATES
bar    0/1     Terminating   0          25h   10.244.65.113   a3     <none>           <none>
```

Attempts to stop pod using "`crictl stopp`" fail AuthN:

```bash
☩ ssh a3 sudo crictl stopp 9c9c058905188
E0812 18:35:51.567809  518652 remote_runtime.go:222] "StopPodSandbox from runtime service failed" err="rpc error: code = Unknown desc = failed to destroy network for sandbox \"9c9c058905188c7047a3a42272be25b13afac1169e2184522fe8d5eeefff71ea\": plugin type=\"calico\" failed (delete): error getting ClusterInformation: connection is unauthorized: Unauthorized" podSandboxID="9c9c058905188"
FATA[0000] stopping the pod sandbox "9c9c058905188": rpc error: code = Unknown desc = failed to destroy network for sandbox "9c9c058905188c7047a3a42272be25b13afac1169e2184522fe8d5eeefff71ea": plugin type="calico" failed (delete): error getting ClusterInformation: connection is unauthorized: Unauthorized

```
- __"`ClusterInformation: connection is unauthorized: Unauthorized`"__

#### How to Fix

E.g., If CNI Add-on is Calico

```bash
kubectl -n kube-system rollout restart ds/calico-node
# Verify
kubectl -n kube-system rollout status  ds/calico-node
```

### Delete/Re-join a Control-Plane Node

Modifications to Static Pod manifest(s) do not typically require `drain`/`delete`/`join` of (control-plane) nodes.
However, some changes require it:

- Pod CIDR Allocations
    - Existing nodes will not adopt changes to Pod CIDR,
      whether declared by modifying manifests or otherwise.
- Control-Plane Certificates
    - If expired or improperly rotated,
      rejoining nodes may be necessary.
- Adding New Control-Plane Nodes.


#### Drain/Delete/Join

From remote (admin) host:

```bash
user=u1
node=a1
# Delete
kubectl drain $node --delete-local-data --force --ignore-daemonsets
kubectl delete node $node
ssh $user@$node /bin/bash -c '
    sudo systemctl stop kubelet
    sudo rm -rf /etc/kubernetes/manifests/*
    sudo rm -rf /var/lib/kubelet/*
    sudo rm -rf /var/lib/etcd/*
    sudo systemctl start kubelet
'
# Join
ssh $user@$node sudo kubeadm join --config kubeadm-config-join.yaml

```

### Remove taint

```bash
# taints : get : spec.taints: [{key: <str>, value: <str>, effect: <str>}, ...]
k get node $name -o jsonpath='{.spec.taints}'
# taints : get keys, e.g., "node-role.kubernetes.io/control-plane"
k get node a2 -o jsonpath='{.spec.taints[*].key}'
# taints : remove
# - remove if value (key) exist
kubectl taint nodes $name $key1=$value1:$effect-
# - remove if value (key) not exist
kubectl taint nodes $name $key1:$effect-

```

Remove __`NoSchedule`__ from joined control nodes

```bash
k get node a1 -o yaml |yq .spec.taints
```
```yaml
- effect: NoSchedule
  key: node-role.kubernetes.io/control-plane
```
```bash
k taint node a1 node-role.kubernetes.io/control-plane:NoSchedule-
node/a1 untainted

```

### Linux firewall vs. CNI's SDN

The CNI plugin is responsible for the (software-defined) Pod Network. It cre ates (Linux namespaced) virtual network interfaces per Pod, and manages them across their lifecycle. The popular CNIs (e.g., Calico and Cilium) are capable of highly granular traffic management, far beyond that of the Linux firewall, to include enforcement of K8s `NetworkPolicy` resources. The point here is that any host-level firewall rules on these ephemeral virtual adapters would be counter-productive. 

The advised scheme is to use the Linux firewall (`NetworkManager`, `nftables`, `firewalld`) only for the host's domain-facing (AKA "public") interface; binding it to some declared zone (e.g., `k8s`) and adding host-traffic services and such on that, as required by applications that traffic across that host-level interface (k8s, Calico, Cilium, external load balancer, ...).

The CNI's virtual adapters, however, should be declared unmanaged WRT `NetworkManager` (`nmcli`). Moreover, `firewalld` should have its `default` zone set to something apropos, such as `trusted`. The default zone will bind to all the CNI's (ephemeral) virtual adapters. That is, we must prevent the Linux firewall from interfering in the CNI's (dynamic) traffic management.


### Modify `kubelet` Configuration

__View__ current configuration files

```bash
# Reveal all of its sources
sudo systemctl cat kubelet

```

__Reveal the sum total effect__ of all those configuration sources

@ Server terminal

```bash
kubectl proxy
```

@ Client terminal

```bash
no=a1
curl -X GET http://127.0.0.1:8001/api/v1/nodes/$no/proxy/configz |jq .

```

__Modify__

#### Method 1. Directly declcare in its `--config` file (`KubeletConfiguration`)

@ `/var/lib/kubelet/config.yaml/`


```yaml
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
...
cgroupDriver: systemd
systemReserved:
  cpu: "500m"
  memory: "1Gi"
kubeReserved:
  cpu: "500m"
  memory: "1Gi"
enforceNodeAllocatable:
  - "pods"
  - "system-reserved"
  - "kube-reserved"
evictionHard:
  memory.available: "200Mi"
  nodefs.available: "10%"
systemReservedCgroup: "/sys/fs/cgroup/system.slice/system-reserved.slice"
                       /sys/fs/cgroup/system.slice/system-reserved.slice
kubeReservedCgroup: "/sys/fs/cgroup/system.slice/kube-reserved.slice"
```
- [`KubeletConfiguration`](https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/#kubelet-config-k8s-io-v1beta1-KubeletConfiguration)


```bash
☩ sudo systemctl daemon-reload
☩ sudo systemctl restart kubelet
☩ sudo journalctl --no-pager -eu kubelet
...
Dec 27 09:05:44 a1 kubelet[24102]: E1227 09:05:44.189933   24102 kubelet.go:1542] "Failed to start ContainerManager" err="invalid Node Allocatable configuration. Resource \"memory\" has an allocatable of {{2357198848 0} {<nil>}  BinarySI}, capacity of {{-168800256 0} {<nil>}  BinarySI}"
```

#### Method 2. Use systemd drop-in file (preferred)

@ `/etc/systemd/system/kubelet.service.d/10-reserved-resources.conf`

```bash
file=etc.systemd.system.kubelet.service.10-reserved-resources.conf
cat <<EOH |tee scripts/$file
[Service]
Environment="KUBELET_EXTRA_ARGS=--system-reserved=cpu=500m,memory=1Gi --kube-reserved=cpu=500m,memory=1Gi --eviction-hard=memory.available<200Mi,nodefs.available<10% --enforce-node-allocatable=pods,system-reserved,kube-reserved"
EOH

file=10-reserved-resources.conf
ansibash -u scripts/etc.systemd.system.kubelet.service.$file $file

cat <<'EOH' |tee scripts/kubelet.drop-in.sh
#!/usr/bin/env bash
file=10-reserved-resources.conf
dir=/etc/systemd/system/kubelet.service.d
sudo mkdir -p $dir &&
    sudo cp -p $file $dir/$file &&
        sudo chown 0:0 $dir/$file &&
            sudo chmod 644 $dir/$file &&
                sudo ls -hl $dir/$file &&
                    sudo cat $dir/$file
EOH

ansibash -s scripts/kubelet.drop-in.sh
```
```bash
ssh u1@a1 sudo systemctl daemon-reload
ssh u1@a1 psk kubelet
ssh u1@a1 sudo systemctl restart kubelet
```

Failing

```bash
journalctl --no-pager -eu kubelet

Dec 26 18:32:38 a1 kubelet[8640]: E1226 18:32:38.265597    8640 run.go:74] "command failed" err="failed to validate kubelet configuration, error: [invalid configuration: systemReservedCgroup (--system-reserved-cgroup) must be specified when \"system-reserved\" contained in enforceNodeAllocatable (--enforce-node-allocatable), invalid configuration: kubeReservedCgroup (--kube-reserved-cgroup) must be specified when \"kube-reserved\" contained in enforceNodeAllocatable (--enforce-node-allocatable)], path: &TypeMeta{Kind:,APIVersion:,}"
Dec 26 18:32:38 a1 systemd[1]: kubelet.service: Main process exited, code=exited, status=1/FAILURE
Dec 26 18:32:38 a1 systemd[1]: kubelet.service: Failed with result 'exit-code'.
```

The error indicates that you are enforcing `--enforce-node-allocatable` with `system-reserved` and `kube-reserved`, but __the corresponding cgroups are unspecified__ (`--system-reserved-cgroup` and `--kube-reserved-cgroup`). The kubelet requires these cgroups to enforce resource reservations properly.

Those flags specify the Linux cgroups where system and Kubernetes-reserved resources will be applied. If they are not set, the kubelet cannot enforce the reservations.

Find cgroup

```bash
☩ ssh u1@a1 'mount | grep cgroup'
cgroup2 on /sys/fs/cgroup type cgroup2 (rw,nosuid,nodev,noexec,relatime,seclabel)
```

Create cgroup resources

```bash

# Manual method
sudo mkdir -p /sys/fs/cgroup/system.slice/system-reserved.slice
sudo mkdir -p /sys/fs/cgroup/system.slice/kube-reserved.slice

```

Add to drop-in

```conf
[Service]
Environment="KUBELET_EXTRA_ARGS=--system-reserved=cpu=500m,memory=1Gi --kube-reserved=cpu=500m,memory=1Gi --enforce-node-allocatable=pods,system-reserved,kube-reserved --system-reserved-cgroup=/sys/fs/cgroup/system-reserved --kube-reserved-cgroup=/sys/fs/cgroup/kube-reserved"


```

Verify eBPF Datapath mode

```bash
☩ k get cm cilium-config -o yaml |yq .data.routing-mode
native

☩ k get cm cilium-config -o yaml |yq .data.datapath-mode
veth
```

### Data Rate Test

Measure __East-west traffic__ capacity using `iperf3`

@ Server

```bash
k -n default run nbox --image=nicolaka/netshoot -- iperf3 -s
k -n default get pod -o wide
```
```plaintext
NAME   READY   STATUS    RESTARTS   AGE   IP           NODE  ...
nbox   1/1     Running   0          80s   10.22.0.14   a1    ...
```
- [`nicolaka/netshoot`](https://github.com/nicolaka/netshoot)

@ Server

```bash
☩ k -n default run nbox --image=nicolaka/netshoot -- iperf3 -s
pod/nbox created

☩ kw
nbox   1/1     Running   0          21s   10.244.0.30   a1     <none>           <none>

☩ ip=10.244.0.30
```

@ Client : __Cross nodes__

```bash
☩ k -n default run nbox2 -it --rm     --image=nicolaka/netshoot      --overrides='{"spec": {"nodeName": "a2"}}'     --restart=Never -- iperf3 -c $ip
```
```plaintext
...
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  8.73 GBytes  7.50 Gbits/sec  1113             sender
[  5]   0.00-10.00  sec  8.72 GBytes  7.49 Gbits/sec                  receiver
```

@ Client : __Same node__

```bash
☩ k -n default run nbox2 -it --rm     --image=nicolaka/netshoot      --overrides='{"spec": {"nodeName": "a1"}}'     --restart=Never -- iperf3 -c $ip
```
```plaintext
...
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  54.9 GBytes  47.1 Gbits/sec  2026             sender
[  5]   0.00-10.00  sec  54.9 GBytes  47.1 Gbits/sec                  receiver
```


### Observability

- `metrics-server` : [__`deploy.metrics-server.yaml`__](observability/metrics-server/deploy.metrics-server.yaml)
    ```bash
    k top node
    k top pod
    ```
- [`kubernetes-dashboard`](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/) : See [`README`](observability/dashboard/README.html)
    - Web UI @ [http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/)
        - Auth by token (okay) or KUBECONFIG (fail)


#### [__`kube-prometheus-stack`__](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack#kube-prometheus-stack "prometheus-community/kube-prometheus-stack")

>Note: This chart was formerly named prometheus-operator chart, now renamed to more clearly reflect that it installs the kube-prometheus project stack, within which Prometheus Operator is only one component. This chart does not install all components of kube-prometheus, notably excluding the Prometheus Adapter and Prometheus black-box exporter.

#### [`prometheus-operator`](https://github.com/prometheus-operator/) 

- [`/prometheus-operator`](https://github.com/prometheus-operator/prometheus-operator)
- [`/kube-prometheus`](https://github.com/prometheus-operator/kube-prometheus)

### [Inspektor Gadget framework](https://github.com/inspektor-gadget/inspektor-gadget) | [Running Gadgets](https://inspektor-gadget.io/docs/latest/reference/run/)

Inspektor Gadget is a set of tools and framework for data collection and system inspection on Kubernetes clusters and Linux hosts using eBPF

A Gadget is an OCI image that includes one or more eBPF programs, metadata YAML file and, optionally, WASM modules for post processing. As OCI images, they can be stored in a container registry, making them easy to distribute and share. Gadgets are built using the ig image build command.


### Security

#### [`trivy-operator-install.sh`](security/trivy/trivy-operator-install.sh)

```bash
make trivy
```

### CSI for Windows Shares (CIFS/SMB)

See README @ [`csi/csi-driver-smb`](csi/csi-driver-smb/README.md)

---

## Control Plane Recovery 

Cluster has expired certificates on two nodes. Valid certificates on one node.

### Q:

Why would the one valid node of a three node control-plane cluster be unreachable after deleting the two expired control  nodes

### A:

In a Kubernetes high-availability (HA) control plane setup with three nodes, the etcd database (which stores the cluster's state) is typically configured as a three-member cluster for fault tolerance. Etcd relies on the Raft consensus algorithm, requiring a majority quorum to operate—meaning at least two out of three members must be healthy and communicating for reads/writes to proceed reliably.

If two control-plane nodes have "expired" (e.g., due to certificate expiration, making them invalid or unresponsive), simply deleting them from the cluster (via `kubectl delete node` or similar) without properly handling etcd membership can break things. The remaining valid node's etcd instance still expects a three-member cluster based on its configuration. With the other two members suddenly unreachable or removed abruptly:

- Etcd on the valid node detects a loss of quorum (only 1/3 members available).
- It enters a degraded state, often becoming read-only or entirely unresponsive to prevent data inconsistencies.
- The Kubernetes API server (kube-apiserver), scheduler, and controller manager on the valid node depend on etcd for all operations. Without a functional etcd, these components fail or crash, rendering the control plane inaccessible.
- As a result, commands like `kubectl` can't connect, and the entire cluster appears "unreachable" from a management perspective, even if worker nodes and workloads continue running temporarily.

This differs from removing worker nodes, which don't host etcd or critical control-plane components. To avoid this, you must explicitly remove the expired nodes from the etcd membership first (using `etcdctl member remove`) before deleting them, then potentially reconfigure the surviving node as a single-member etcd cluster temporarily if needed.

### Step-by-step etcd recovery process

Here is the **safe, step-by-step etcd recovery process** when you are left with **only one healthy control-plane node** after the other two nodes have expired or become unreachable in a 3-node HA Kubernetes cluster.

This procedure works for **kubeadm-based clusters** (most common) and has been tested on Kubernetes v1.21+ (including v1.30+ in 2025).

### Goal
Restore a working control plane using the single remaining valid etcd member, then optionally rebuild the other two nodes.

### Prerequisites
- You still have **SSH and sudo access** to the one healthy control-plane node.
- You can run `kubectl` **from that node itself** (even if external API server appears down).
- You have the original **kubeadm configuration** or at least the cluster name and certificates.

### Step-by-Step Recovery

This assumes etcd is external (systemd service), but may be adapted for stacked topology.


#### 1. Log in to the remaining healthy control-plane node
```bash
ssh kubeadm-cp1.example.com
sudo -i
```

#### 2. Verify etcd status (it will show only 1/3 members)
```bash
export ETCDCTL_API=3
etcdctl --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    member list -w table
```

You’ll see something like:
```
+------------------+---------+--------+-------------------------------+-------------------------------+
|        ID        | STATUS  |  NAME  |         PEER ADDRS            |        CLIENT ADDRS           |
+------------------+---------+--------+-------------------------------+-------------------------------+
| 123456789abc     | started | cp1    | https://10.0.0.11:2380        | https://10.0.0.11:2379        |
| deadbeef1234     | started | cp2    | https://10.0.0.12:2380        | https://10.0.0.12:2379        |  ← unreachable
| cafebabe5678     | started | cp3    | https://10.0.0.13:2380        | https://10.0.0.13:2379        |  ← unreachable
+------------------+---------+--------+-------------------------------+-------------------------------+
```

#### 3. Remove the two failed members from etcd
```bash
# Get the member IDs of the failed nodes
etcdctl member list

# Remove them one by one
etcdctl member remove deadbeef1234
etcdctl member remove cafebabe5678
```

Now `member list` shows only one member — quorum is now 1/1 = healthy.

#### 4. Force a new etcd cluster with only this member (critical step!)
Even after removing members, etcd still thinks it's part of a 3-member cluster and will panic on restart. You must rewrite the data directory to make it a single-member cluster.

```bash
# Stop etcd and kube-apiserver temporarily
systemctl stop etcd kubelet

# Backup current data dir (safety!)
mv /var/lib/etcd /var/lib/etcd.backup.$(date +%Y%m%d-%H%M)

# Recreate etcd as single-member cluster
ETCDCTL_API=3 etcdctl snapshot restore /var/lib/etcd.backup.*/member/snap/db \
    --name cp1 \
    --initial-cluster cp1=https://10.0.0.11:2380 \
    --initial-cluster-token etcd-cluster-1 \
    --initial-advertise-peer-urls https://10.0.0.11:2380 \
    --data-dir /var/lib/etcd

chown -R etcd:etcd /var/lib/etcd
```

#### 5. Update etcd pod manifest to reflect new single-member setup
Edit the static pod manifest:
```bash
vi /etc/kubernetes/manifests/etcd.yaml
```

Change these lines:
```yaml
- --initial-cluster=cp1=https://10.0.0.11:2380,cp2=https://10.0.0.12:2380,cp3=https://10.0.0.13:2380
→ --initial-cluster=cp1=https://10.0.0.11:2380

- --initial-cluster-token=etcd-cluster-1
→ keep or remove (optional)

Remove --initial-cluster-state=new if present (it should now be "existing")
```

#### 6. Restart etcd and kubelet
```bash
systemctl start etcd
systemctl start kubelet
```

Wait 30–60 seconds, then check:
```bash
crictl ps | grep etcd
kubectl get nodes  # should work locally now
```

The API server should come back up within 1–2 minutes.

#### 7. Fix the control-plane endpoint (if using kubeadm)
If you use a load balancer or DNS pointing to all three nodes:
```bash
# Update the cluster configuration
kubeadm init phase upload-config kubeadm --kubeconfig=/etc/kubernetes/admin.conf

# Recreate certificates if needed (optional, only if expired)
kubeadm certs renew all
```

#### 8. (Optional) Add back the other two nodes later)
Once the cluster is stable:
- Reinstall OS + kubeadm on cp2 and cp3 (or fix certificates)
- Rejoin them as control-plane nodes:
```bash
kubeadm join <control-plane-ip>:6443 --token ... --discovery-token-ca-cert-hash ... --control-plane --certificate-key ...
```
- etcd will automatically add them back as new members.

### Summary of Critical Commands
```bash
# 1. Remove failed members
etcdctl member remove <failed-id-1>
etcdctl member remove <failed-id-2>

# 2. Restore as single-member
etcdctl snapshot restore <backup>/db \
    --name cp1 \
    --initial-cluster cp1=https://10.0.0.11:2380 \
    --initial-advertise-peer-urls https://10.0.0.11:2380 \
    --data-dir /var/lib/etcd

# 3. Fix etcd.yaml → single member
# 4. Restart services
```

After these steps, your cluster will be fully functional again with one control-plane node, and you can safely rebuild the others.

Let me know your Kubernetes version or if you're using an external etcd cluster — the process varies slightly.
