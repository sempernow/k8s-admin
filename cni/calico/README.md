# [Calico : On-prem K8s](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)

## TL;DR

Tigera Operator is unstable under Hyper-v and perhaps other hypervisors. 
It spawns hundreds of pods having status `ContainerStatusUnknown`, 
perhaps per reboot of parent OS.

## Download | [`calico-pull.sh`](calico-pull.sh)

```bash
ok(){
    DIR=calico
    VER='v3.29.3' # v3.29.1
    BASE=https://raw.githubusercontent.com/projectcalico/calico/$VER/manifests

    # Manifest Method
    ok(){
        dir="$DIR/manifest-method"
        file=calico.yaml
        [[ -f $dir/$file ]] && return 0
        mkdir -p $dir
        pushd $dir
        curl -sSLO $BASE/$file || return 100
        popd
    }
    ok || return $?

    # Operator Method
    ok(){
        dir="$DIR/operator-method"
        mkdir -p $dir

        # Operator
        file=tigera-operator.yaml
        [[ -f $dir/$file ]] || {
            pushd $dir
            curl -sSLO $BASE/$file || return 200
            popd
        }

        # CRDs
        file=custom-resources.yaml
        [[ -f $dir/$file ]] || {
            pushd $dir
            curl -sSLO $BASE/$file || return 300
            popd
        }
    }
    ok || return $?

    # CLI
    ok(){
        # calicoctl
        # https://docs.tigera.io/calico/latest/operations/calicoctl/install
        dir="$DIR/cli"
        url=https://github.com/projectcalico/calico/releases/download/$VER/calicoctl-linux-amd64 
        file=calicoctl
        [[ -f $dir/$file ]] && return 0
        mkdir -p $dir
        pushd $dir
        curl -sSL -o $file $url 
        sudo install $file /usr/local/bin/
        sudo ln -s /usr/local/bin/$file /usr/local/bin/kubectl-calico
        popd
        chmod 0755 $dir/$file && $dir/$file version |grep $VER || return 404
    }
    ok || return $?
    
    # Calico CNI plugin binaries : See Mamual Recovery of Pod Network
    ok(){
        url=https://github.com/projectcalico/cni-plugin/releases/download/$VER/calico-cni-$VER.tgz
        curl -sSLfO $url && tar zxvf calico-cni-$VER.tgz
    }
    ok || return $?
}
ok || echo "ERR: $?"

```

## Install 

### `calicoctl` CLI 

```bash
bin=/usr/local/bin/calicoctl
sudo mv calico $bin &&
    sudo chown root:root $bin &&
        sudo chmod 0755 $bin ||
            echo "ERROR : $?"

```


```bash
☩ calicoctl get ippools -o wide
NAME                  CIDR            NAT    IPIPMODE   VXLANMODE   DISABLED   DISABLEBGPEXPORT   SELECTOR
default-ipv4-ippool   10.244.0.0/24   true   Never      Never       false      false              all()


☩ calicoctl ipam show --show-blocks
+----------+-----------------+-----------+------------+-----------+
| GROUPING |      CIDR       | IPS TOTAL | IPS IN USE | IPS FREE  |
+----------+-----------------+-----------+------------+-----------+
| IP Pool  | 10.244.0.0/24   |       256 | 11 (4%)    | 245 (96%) |
| Block    | 10.244.0.128/26 |        64 | 8 (12%)    | 56 (88%)  |
| Block    | 10.244.0.192/26 |        64 | 1 (2%)     | 63 (98%)  |
| Block    | 10.244.0.64/26  |        64 | 2 (3%)     | 62 (97%)  |
+----------+-----------------+-----------+------------+-----------+

☩ calicoctl ipam show --show-configuration
+--------------------+-------+
|      PROPERTY      | VALUE |
+--------------------+-------+
| StrictAffinity     | false |
| AutoAllocateBlocks | true  |
| MaxBlocksPerHost   |     0 |
+--------------------+-------+

☩ calicoctl ipam show --ip=10.244.0.142
IP 10.244.0.142 is in use
Attributes:
  namespace: kube-system
  node: a1
  pod: coredns-76f75df574-fsxvc
  timestamp: 2024-12-14 21:44:05.795537491 +0000 UTC


```

### [__Calico monitoring__ commands](https://chatgpt.com/share/68117571-ed50-8009-9a59-2b918038e3cc) 

Summary 

```bash
# Run as sudo per node : Checks local Calico/node service
echo a1 a2 a3 |xargs -n1 /bin/bash -c 'ssh $1 sudo calicoctl node status' _

# Run felix per node : full dump for forensics 
kubectl exec -n kube-system calico-node-$name -c calico-node -- calico-node -felix

# Run remote, unprivileged
calicoctl ipam show --show-blocks
calicoctl ipam show --show-configuration

# calico-node
pod=$(kubectl get pods -n kube-system -l k8s-app=calico-node -o name |head -n1)
kubectl exec -n kube-system $pod -c calico-node -- calico-node --help
kubectl exec -n kube-system $pod -c calico-node -- calico-node --show-status
# calico-node : Felix/BIRD live/ready status per node
kubectl get pods -n kube-system -l k8s-app=calico-node -o name \
    |xargs -I{} kubectl exec -n kube-system {} -c calico-node -- sh -c '
        echo "=== {}"
        /bin/calico-node -felix-live  && echo "Felix live: OK"  || echo "Felix live: FAIL"
        /bin/calico-node -felix-ready && echo "Felix ready: OK" || echo "Felix ready: FAIL"
        /bin/calico-node -bird-live   && echo "BIRD live: OK"   || echo "BIRD live: FAIL"
        /bin/calico-node -bird-ready  && echo "BIRD ready: OK"  || echo "BIRD ready: FAIL"
        echo
    '
```
```log
...
=== pod/calico-node-gp7tl
Felix live: OK
Felix ready: OK
BIRD live: OK
2025-04-30 00:54:30.895 [INFO][63657] node/health.go 202: Number of node(s) with BGP peering established = 2
BIRD ready: OK
...
```
- __Felix__ is the node-local Calico brain that reacts to cluster state and enforces networking and policy rules in the kernel.
- __BIRD__ is a userspace BGP routing daemon; the optional Calico routing announcer used in BGP mode (bare-metal clusters, no overlay tunnels).

### `calicoctl` CLI as `kubctl` plugin 

At admin node:

```bash
# Install
bin=/usr/local/bin/kubectl-calico
url=https://github.com/projectcalico/calico/releases/download/v3.29.1/calicoctl-linux-amd64
sudo curl -sSL $url -o $bin &&
    sudo chmod +x $bin &&
        echo ok

# Use
#kubectl calico -h
kubectl calico get node
kubectl calico get ippool
#kubectl calico ipam check
kubectl calico ipam show --show-blocks
kubectl calico ipam show --show-configuration
kubectl calico ipam show --ip=$podIP


```

### CNI by Operator Method

` calico/node` runs three daemons:

1. Felix : the Calico per-node daemon
2. BIRD : speaks the BGP protocol to distribute 
   routing information to other nodes
3. confd : watches the Calico datastore 
   for config changes and updates BIRD's config files

[__Install/Configure for On-prem deployments__](https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises)

#### 1. Intall CRDs and then CRs

```bash
crd=tigera-operator.yaml
cr=custom-resources-bpf-bgp.yaml
kubectl create -f $crd
kubectl apply -f $cr

```

```bash
☩ k api-resources |grep calico |wc -l
37

☩ k get tigerastatuses
NAME        AVAILABLE   PROGRESSING   DEGRADED   SINCE
apiserver   True        False         False      57m
calico      True        False         False      22m
ippools     True        False         False      58m

☩ k -n calico-system logs -l k8s-app=calico-node

☩ k -n calico-system get ds calico-node -o yaml \
    |yq .spec.template.spec.containers[].env
```
```yaml
- name: DATASTORE_TYPE
  value: kubernetes
- name: WAIT_FOR_DATASTORE
  value: "true"
- name: CLUSTER_TYPE
  value: k8s,operator,bgp
- name: CALICO_DISABLE_FILE_LOGGING
  value: "false"
- name: FELIX_DEFAULTENDPOINTTOHOSTACTION
  value: ACCEPT
- name: FELIX_HEALTHENABLED
  value: "true"
- name: FELIX_HEALTHPORT
  value: "9099"
- name: NODENAME
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: spec.nodeName
- name: NAMESPACE
  valueFrom:
    fieldRef:
      apiVersion: v1
      fieldPath: metadata.namespace
- name: FELIX_TYPHAK8SNAMESPACE
  value: calico-system
- name: FELIX_TYPHAK8SSERVICENAME
  value: calico-typha
- name: FELIX_TYPHACAFILE
  value: /etc/pki/tls/certs/tigera-ca-bundle.crt
- name: FELIX_TYPHACERTFILE
  value: /node-certs/tls.crt
- name: FELIX_TYPHAKEYFILE
  value: /node-certs/tls.key
- name: FIPS_MODE_ENABLED
  value: "false"
- name: NO_DEFAULT_POOLS
  value: "true"
- name: FELIX_TYPHACN
  value: typha-server
- name: CALICO_MANAGE_CNI
  value: "true"
- name: CALICO_NETWORKING_BACKEND
  value: bird
- name: IP
  value: autodetect
- name: IP_AUTODETECTION_METHOD
  value: first-found
- name: IP6
  value: none
- name: FELIX_IPV6SUPPORT
  value: "false"
- name: KUBERNETES_SERVICE_HOST
  value: 192.168.11.101
- name: KUBERNETES_SERVICE_PORT
  value: "6443"
```

Not all `calicoctl` commands can be run under `kubectl calico`.
Some require sudo:

```bash
☩ ansibash sudo calicoctl node status
=== u1@a1
Connection to 192.168.11.101 closed.
Calico process is running.

IPv4 BGP status
+----------------+-------------------+-------+----------+-------------+
|  PEER ADDRESS  |     PEER TYPE     | STATE |  SINCE   |    INFO     |
+----------------+-------------------+-------+----------+-------------+
| 192.168.11.102 | node-to-node mesh | up    | 11:35:46 | Established |
| 192.168.11.100 | node-to-node mesh | up    | 11:35:41 | Established |
+----------------+-------------------+-------+----------+-------------+

IPv6 BGP status
No IPv6 peers found.
...
```

#### 2. [Configure BGP peering](https://docs.tigera.io/calico/latest/networking/configuring/bgp)

This is advised as best of [__Networking Options__](https://docs.tigera.io/calico/latest/networking/determine-best-networking#on-prem) for __On-prem__

>The most common network setup for Calico on-prem is non-overlay mode using BGP to peer with the physical network ... to make pod IPs routable outside of the cluster. ...This setup provides a rich range of advanced Calico features, including the ability to advertise Kubernetes service IPs (cluster IPs or external IPs), and the ability to control IP address management at the pod, namespace, or node level, to support a wide range of possibilities for integrating with existing enterprise network and security requirements.

___Fantasically tedious configuration___.

Calico offers no single or few manifests having the supposedly-advised configuration. Instead, it's an almost key-by-key configuration.

### by Manifest method

```bash
kubectl apply -f calico.yaml
```

## [Enable __eBPF__ dataplane](https://docs.tigera.io/calico/latest/operations/ebpf/enabling-ebpf)

- [Configure Calico to talk directly to K8s API server](https://docs.tigera.io/calico/latest/operations/ebpf/enabling-ebpf#configure-calico-to-talk-directly-to-the-api-server)

@ Operator method

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubernetes-services-endpoint
  namespace: tigera-operator
data:
  KUBERNETES_SERVICE_HOST: 'K8S_CONTROL_IP'
  KUBERNETES_SERVICE_PORT: 'K8S_CONTROL_PORT'
```

@ Manifest method

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kubernetes-services-endpoint
  namespace: kube-system
data:
  KUBERNETES_SERVICE_HOST: 'K8S_CONTROL_IP'
  KUBERNETES_SERVICE_PORT: 'K8S_CONTROL_PORT'
```

```bash
sed -i "s,K8S_CONTROL_IP,$K8S_CONTROL_IP,g" $cm
sed -i "s,K8S_CONTROL_PORT,$K8S_CONTROL_PORT,g" $cm
kubectl apply -f $cm
kubectl delete pod -n kube-system -l k8s-app=calico-node
kubectl delete pod -n kube-system -l k8s-app=calico-kube-controllers
```


In eBPF mode Calico __replaces `kube-proxy`__, 
so disable it by adding a node selector to `kube-proxy`'s DaemonSet 
that matches no nodes:

```bash
kubectl patch ds -n kube-system kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico": "true"}}}}}'

```


## Fix Pod Network

### Case 1 : Failed pod(s)

```bash
# Delete all pods of phase Failed
kubectl delete pod -A --field-selector=status.phase=Failed
```

### Case 2 : AuthN fail at `crictl ...`

A host-level hard reboot leaves a bunch of "half-torn-down" state on each node, and when kubelet/CRI tries to clean it up on boot the Calico CNI DEL path needs a valid K8s token,but the file it uses (`/etc/cni/net.d/calico-kubeconfig`) often contains an expired bound-SA token. 

Result: Unauthorized → sandbox teardown fails → pods stick in Terminating.

Kubernetes with Calico has a recurring pattern where a pod is forever stuck in a non-functional state and can't be deleted.

__Fix__:

```bash
## Rolling restart
kubectl -n kube-system rollout restart ds/calico-node
# Verify
kubectl -n kube-system rollout status  ds/calico-node
```
- See LOG @ 2025-08-12 for details of cause, symtoms and confirmation


## Manual Recovery of Pod Network

It's true that once Calico (or any CNI) is completely broken, deleting leftover sandboxes (and getting kubelet & containerd to "un‐stick" themselves) can feel impossible. In most cases, however, you can recover without resorting to `kubeadm reset`, provided you restore Calico's CNI binaries/config for containerd and then force‐remove the orphaned sandboxes. Below are the key points and an ordered set of steps that have worked on kubeadm‐built clusters (even when the pod network is down):

---

## 1. Why reapplying Calico alone sometimes "looks" like it can't help

1. **kubelet refuses to create or tear down network namespaces** if it can't find a valid CNI plugin on disk.

   * When Calico is gone, there is no `/etc/cni/net.d/10-calico.conflist` (or equivalent) on each node, and no `/opt/cni/bin/calico` executable.
   * As a result, any attempt to start or stop a pod will fail at "NetworkPlugin cni failed to set up pod netns." Likewise, `crictl stopp <podID>` will hang or error out because containerd tries to invoke the CNI plugin in that pod's "tear-down" path and cannot find it.

2. **Orphaned sandboxes persist** because containerd (and therefore `crictl`) can't do the netns‐cleanup phase without a CNI.

   * These sandboxes live in containerd's CRI namespace (usually `k8s.io`) and hold a Linux netns under `/proc` (or `/var/run/netns`). Without the CNI binary present, containerd cannot complete the "DeleteNetwork" step, so the sandbox (and its netns) remain around.
   * From Kubernetes' point of view, the Pod object keeps being "Terminating" or "Unknown," and from containerd's point of view `crictl ps -a` still shows "Exited" or "ContainerCreating" sandboxes.

In other words, **reapplying the usual Calico YAML** (which simply creates DaemonSets/Deployments/CRDs inside Kubernetes) often fails to "fix" nodes because kubelet can't even start the calico-node DaemonSet pods—they never get to run the CNI plugin. As a result, the network never comes back, and you remain stuck in a catch-22.

---

## 2. The "two-step" approach: restore just enough CNI bits so containerd can delete sandboxes

To recover without wiping the entire cluster, you need to:

1. **Manually drop Calico's CNI binaries + CNI JSON** back onto each node's filesystem.
2. **Restart containerd/kubelet** so that "`crictl stopp/rmp`" can actually tear down the netns.
3. **Delete all orphaned sandboxes with crictl**.
4. **Reapply the full Calico manifest** (DaemonSet + Deployment + RBAC + CRDs).
5. **Confirm pods re-acquire IPs and the network heals**.

Below is a concrete sequence of commands. Adjust paths/versions for your particular Kubernetes + Calico version.

---

### 2.1 Identify where Calico's CNI DLLs go

By default, kubeadm + containerd expect:

* **CNI "plugin binaries"** in:

  ```
  /opt/cni/bin/
  ```
* **CNI ".conflist" or ".conf"** in:

  ```
  /etc/cni/net.d/
  ```

When Calico was running, you probably had something like:

```
/opt/cni/bin/calico
/opt/cni/bin/calico-ipam
…
/etc/cni/net.d/10-calico.conflist
```

Those were installed by the `calico-node` DaemonSet's init or by a previous manual installation. Now that Calico is gone, they're deleted, so containerd's teardown of any pod sandbox fails.

---

### 2.2 Download the "bare‐minimum" CNI artifacts on one control-plane node

1. **Fetch the Calico CNI plugins tarball.**
   You can get the CNI binaries directly from the Calico GitHub release for your version. For example, if you were on Calico v3.26—and you only need the CNI bits—you can do:

   ```bash
   cd /tmp
   curl -LfO https://github.com/projectcalico/cni-plugin/releases/download/v3.26.0/calico-cni-v3.26.0.tgz
   tar zxvf calico-cni-v3.26.0.tgz
   # This unpacks files like 'calico' and 'calico-ipam' and 'calico-iptables' etc.
   ```

2. **Fetch a "sample" Calico CNI conflist.**
   A minimal `10-calico.conflist` for VXLAN mode looks like this:

   ```jsonc
   {
     "name": "k8s-pod-network",
     "cniVersion": "0.3.1",
     "plugins": [
       {
         "type": "calico",
         "datastore_type": "kubernetes",
         "nodename": "__KUBERNETES_NODE_NAME__",
         "mtu": 1440,
         "ipam": {
           "type": "calico-ipam"
         },
         "policy": {
           "type": "k8s"
         },
         "kubernetes": {
           "kubeconfig": "/etc/cni/net.d/calico-kubeconfig"
         }
       },
       {
         "type": "portmap",
         "snat": true,
         "capabilities": { "portMappings": true }
       }
     ]
   }
   ```

   Save that as `/tmp/10-calico.conflist` (but leave the `__KUBERNETES_NODE_NAME__` placeholder for now).

---

### 2.3 Copy the CNI bits onto each node

For each node (control-plane and workers), do:

1. **Become root (or use `sudo`).**

   ```bash
   sudo -i
   ```

2. **Create the CNI directories if they're gone.**

   ```bash
   mkdir -p /opt/cni/bin
   mkdir -p /etc/cni/net.d
   mkdir -p /etc/cni/net.d/calico-kubeconfig.d  # where the kubeconfig for Calico lives
   ```

3. **Copy the plugin binaries** (`calico`, `calico-ipam`, etc.) to `/opt/cni/bin/`.

   ```bash
   cp /tmp/calico /opt/cni/bin/
   cp /tmp/calico-ipam /opt/cni/bin/
   cp /tmp/calico-iptables /opt/cni/bin/
   # (and any other files from the tarball: calico-cnidep, calico-ipam-dep, etc.)
   chmod +x /opt/cni/bin/calico*
   ```

4. **Drop in the conflist file.**
   Edit `/etc/cni/net.d/10-calico.conflist` and replace `__KUBERNETES_NODE_NAME__` with that node's actual `hostname -s` (or whatever `NODE_NAME` the DaemonSet would have used). For example, if your node's name is `node-01`:

   ```bash
   sed -e "s/__KUBERNETES_NODE_NAME__/node-01/" /tmp/10-calico.conflist \
       > /etc/cni/net.d/10-calico.conflist
   ```

5. **Create a "Calico kubeconfig"** at `/etc/cni/net.d/calico-kubeconfig.d/calico-kubeconfig` that points to the API server and uses the correct ServiceAccount token.
   You can borrow from the old DaemonSet's YAML (if you still have it). A minimal kubeconfig might look like:

   ```yaml
   apiVersion: v1
   kind: Config
   clusters:
   - cluster:
       certificate-authority: /etc/kubernetes/pki/ca.crt
       server: https://<API_SERVER_IP>:6443
     name: kubernetes
   contexts:
   - context:
       cluster: kubernetes
       user: calico-node
     name: calico-context
   current-context: calico-context
   users:
   - name: calico-node
     user:
       tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
   ```

   Place that file at:

   ```
   /etc/cni/net.d/calico-kubeconfig.d/calico-kubeconfig
   ```

   As long as `/etc/kubernetes/pki/ca.crt` and the `/var/run/secrets/kubernetes.io/serviceaccount` directory exist (they will, because kubelet is still running), containerd can call out to the API server to create or remove network namespaces.

6. **Restart containerd** (so it picks up the new plugin directory):

   ```bash
   systemctl restart containerd
   ```

7. **Restart kubelet** (so it registers the CNI as available):

   ```bash
   systemctl restart kubelet
   ```

---

### 2.4 Delete all orphaned sandboxes with `crictl`

Now that the CNI plugin is back on disk, containerd can complete any pending "DeleteNetwork" calls. On each node:

1. **Point `crictl` at the correct socket** (if you haven't already in `/etc/crictl.yaml`):

   ```bash
   export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock
   ```

2. **Run as root** so you can talk to the socket:

   ```bash
   sudo crictl ps -a
   ```

   You should now see the leftover sandboxes (even those in "ContainerCreating" or "Exited" state) listed.

3. **Stop + remove each sandbox/container**:

   ```bash
   for ID in $(sudo crictl ps -a -q); do
     sudo crictl stopp $ID   || true
     sudo crictl rmp   $ID   || true
   done
   ```

   If any individual `stopp` or `rmp` hangs, open a second terminal, find the exact PID of containerd (`ps aux | grep containerd`), and kill it. Then restart containerd—this often "unsticks" a container that was endlessly waiting to call CNI.

4. **Verify nothing remains**:

   ```bash
   sudo crictl ps -a
   ```

   It should return no containers (or only those for system pods like `kube-apiserver` if you're on a control-plane node). If it's empty, you have successfully removed the "cruft."

---

## 3. Now reapply the full Calico manifest

With the old sandboxes gone and the CNI files in place, kubelet is again able to launch pods that invoke Calico's plugin. Proceed to:

1. **Fetch the correct Calico YAML for your k8s version** (example for v3.26 on Kubernetes 1.26):

   ```bash
   curl -O https://docs.projectcalico.org/manifests/calico-v3.26.yaml
   ```

2. **(Optional) Edit the ConfigMap** inside `calico-v3.26.yaml` if you have a custom IP pool, MTU, or different etcd/datastore configuration. Otherwise, leave it as-is.

3. **Apply it**:

   ```bash
   kubectl apply -f calico-v3.26.yaml
   ```

4. **Watch the DaemonSet + Deployment** come up:

   ```bash
   kubectl -n kube-system get ds,deploy | grep calico
   ```

   You should see:

   ```
   daemonset.apps/calico-node               3   3   3   30s
   deployment.apps/calico-kube-controllers  1   1   1   30s
   ```

   If any pod stays in `ContainerCreating` or `CrashLoopBackOff`, describe it and check logs:

   ```bash
   kubectl -n kube-system describe ds/calico-node
   kubectl -n kube-system logs ds/calico-node -c calico-node
   kubectl -n kube-system describe deploy/calico-kube-controllers
   kubectl -n kube-system logs deploy/calico-kube-controllers
   ```

5. **Once `calico-node` is Running**, verify the VXLAN interface on each node:

   ```bash
   ip link show vxlan.calico
   ```

   It should be `UP` with the correct VXLAN ID (usually 4096) and pointing to the node's PodCIDR.

6. **Confirm that CoreDNS & any Pending pods now get IPs**:

   ```bash
   kubectl -n kube-system get pods -l k8s-app=kube-dns
   ```

   They should move from `Pending` → `ContainerCreating` → `Running`.

---

## 4. Will you ever be able to delete the "cruft" once the pod network is lost?

Yes—once you restore the minimal CNI binaries (so that containerd can successfully call the CNI "DEL" plugin), `crictl stopp/rmp` will complete. In short:

* **The sandboxes are not locked away forever.**
  They were only "stuck" because containerd could not invoke the CNI binary to tear down that pod's network namespace. As soon as the plugin reappears, containerd can finish the cleanup.

* **You do not need to wipe `/var/lib/containerd` or do a full `kubeadm reset`.**
  As long as containerd restarts cleanly, it will re‐sync existing pods—but the orphans can now be removed. A full `kubeadm reset` is only required if the control plane's etcd data is irrecoverable or you don't care about preserving anything at all.

* **If containerd still shows sandboxes that refuse `rmp`, you can forcibly remove them via `ctr`.**
  As a fallback, use the `ctr` command (which speaks directly to containerd's API) to list and remove sandbox objects in the `k8s.io` namespace:

  ```bash
  sudo ctr --namespace k8s.io containers list
  sudo ctr --namespace k8s.io containers delete <containerID>
  sudo ctr --namespace k8s.io sandboxes list
  sudo ctr --namespace k8s.io sandboxes delete  <sandboxID>
  ```

  But, in almost every case, once the CNI plugin is back and containerd has been restarted, `crictl rmp` will succeed.

---

## 5. In practice: answering your questions

1. **"Will we ever recover by reapplying Calico?"**

   * **Yes**, provided you first restore the minimal CNI binaries and conflist so containerd can tear down the broken netns and let kubelet start new pods. Once those orphans are gone, applying the full Calico manifest will let kubelet spin up `calico-node` DaemonSet pods, rebuild VXLAN interfaces and iptables rules, and finally restore pod networking.
   * If you simply rerun `kubectl apply -f calico.yaml` on a node where `/opt/cni/bin/calico` is missing, the `calico-node` Pod will stay stuck in `ContainerCreating` and never fix anything.

2. **"Can we delete the leftover sandboxes (the ‘cruft')?"**

   * **Yes**—as soon as containerd can see the CNI plugin again, `crictl stopp <ID> && crictl rmp <ID>` will succeed.
   * If necessary, you can also restart containerd (or, in the very worst case, use `ctr` to manually delete sandboxes). None of these sandboxes are "locked away for all eternity."

3. **When is a full `kubeadm reset` actually required?**

   * Only if your etcd data is so corrupted that you cannot rebuild or re-bootstrap the control plane. If you still have a healthy etcd and kube-apiserver, you can recover by repairing the CNI bits and deleting the orphans.
   * In most VXLAN/CNI outages, restoring the plugin binaries and doing a forced sandbox cleanup is enough.

---

### 6. Quick Recipe (Summary)

```bash
# On each node, as root:

# 1) Stop kubelet & containerd
systemctl stop kubelet
systemctl stop containerd

# 2) Put Calico CNI binaries back on disk
mkdir -p /opt/cni/bin /etc/cni/net.d/calico-kubeconfig.d
cp /tmp/calico         /opt/cni/bin/
cp /tmp/calico-ipam    /opt/cni/bin/
cp /tmp/calico-iptables /opt/cni/bin/
chmod +x /opt/cni/bin/calico*

# 3) Drop in the conflist (replace NODE_NAME accordingly)
sed -e "s/__KUBERNETES_NODE_NAME__/$(hostname -s)/" /tmp/10-calico.conflist \
    > /etc/cni/net.d/10-calico.conflist

# 4) Drop in a minimal kubeconfig for Calico at /etc/cni/net.d/calico-kubeconfig.d/calico-kubeconfig
#    (make sure it points to your API server's IP and uses the serviceaccount token path)

# 5) Start containerd, then delete all sandboxes
systemctl start containerd
export CONTAINER_RUNTIME_ENDPOINT=unix:///run/containerd/containerd.sock

for ID in $(crictl ps -a -q); do
  crictl stopp $ID || true
  crictl rmp   $ID || true
done

# 6) Start kubelet
systemctl start kubelet

# Repeat on every node. Then, from any control-plane that still has kubectl access:

kubectl apply -f calico-v3.26.yaml   # reapply full Calico manifest
kubectl -n kube-system get pods -l k8s-app=calico --watch
kubectl -n kube-system get pods -l k8s-app=kube-dns --watch
```

If everything goes well, you'll see:

1. All orphaned containerd sandboxes vanish.
2. Calico's DaemonSet (`calico-node`) schedules on each node → VXLAN comes up.
3. Calico controllers (`calico-kube-controllers`) start → IPAM is reconstructed.
4. CoreDNS (and all pending pods) begin to receive IP addresses → your cluster network is back.

After that, there is no need to do a `kubeadm reset`. The cluster is salvageable as long as etcd + API server remain healthy.
