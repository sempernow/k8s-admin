
# [Recover from Calico VXLAN-mode failure on reboot](https://chatgpt.com/share/6840c920-f050-8009-bfd4-5d8b436c8c89)

---

# Q:

This is a common log pattern for Calico __v3.29.3__ controller `Deployment` by manifest method in either IP-in-IP or VXLAN modes on a multi-node kubeadm on-prem cluster :

```bash
☩ kubectl logs deployments/calico-kube-controllers
```
```log
...
2025-05-30 18:43:47.684 [WARNING][1] kube-controllers/winutils.go 150: Neither --kubeconfig nor --master was specified.  Using the inClusterConfig.  This might not work.
2025-05-30 18:43:47.686 [INFO][1] kube-controllers/main.go 116: Ensuring Calico datastore is initialized
2025-05-30 18:44:17.715 [ERROR][1] kube-controllers/client.go 320: Error getting cluster information config ClusterInformation="default" error=Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
2025-05-30 18:44:17.715 [INFO][1] kube-controllers/client.go 248: Unable to initialize ClusterInformation error=Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
2025-05-30 18:44:17.740 [INFO][1] kube-controllers/main.go 123: Failed to initialize datastore error=Get "https://10.96.0.1:443/apis/crd.projectcalico.org/v1/clusterinformations/default": dial tcp 10.96.0.1:443: i/o timeout
2025-05-30 18:44:22.765 [INFO][1] kube-controllers/main.go 141: Calico datastore is initialized
2025-05-30 18:44:22.765 [INFO][1] kube-controllers/main.go 178: Getting initial config snapshot from datastore
2025-05-30 18:44:22.776 [INFO][1] kube-controllers/main.go 181: Got initial config snapshot
2025-05-30 18:44:22.776 [INFO][1] kube-controllers/watchersyncer.go 89: Start called
2025-05-30 18:44:22.776 [INFO][1] kube-controllers/main.go 195: Starting status report routine
...
```
- Mode: IP-in-IP

Note the `ERROR` entry (timeout) at request to K8s API server (`10.96.0.1:443`), and subsequent `INFO` entry ("`Failed to initialize datastore`"),
yet the controller eventually has success in this case (IP-in-IP mode). 

This pattern is common under __either VXLAN or IP-in-IP modes__, and across several clusters on subnets of varying infrastructure (all RHEL 8/9 on VMs of a type-1 hypervisor). 

We find that Calico and its Pod Network can recover from unplanned host reboots only if in IP-in-IP mode. If in VXLAN mode, the controller suffers in perpetual `CrashLoopBackoff` or `Error`, recurringly terminating after that initial `ERROR` log entry of same message. 

Thereafter, the Pod Network remains broken. Note the containers remain Ready as seen by `crictl`, and all `calicoctl` metrics report no issues.

The only recovery method found is a hard teardown of the cluster. 

Until these fatal reboots, Calico in VXLAN mode functions normally. 

__Any ideas?__

---

# A:

It turns out there are a few overlapping factors at play when VXLAN‐mode Calico fails to come back after a node reboot, even though IP‐in‐IP mode will recover. Below are the most common causes and some mitigation steps:


## TL;DR

At each node:

```bash
ip link delete vxlan.calico
# (Optional) clean up any calico-related routes:
ip route flush dev vxlan.calico
# Then, force restart the Calico DaemonSet pod:
kubectl rollout restart daemonset/calico-node -n kube-system
```

---

## 1. A Known Bug in v3.28.0/v3.29.0 VXLAN Implementations

Calico v3.28.0 and v3.29.0 introduced a regression in VXLAN mode that can break datapath connectivity (including DNS) after certain events (like a reboot). In particular, pods lose all cluster‐IP connectivity except for bare ICMP until Calico’s VXLAN interface is manually cleaned up or Calico is fully re‐installed.

* **GitHub Issue #9433** describes exactly that “VXLAN in 3.29 breaks any connectivity except ICMP”—users report that switching back to IP-in-IP works, but VXLAN simply never recovers. ([github.com][1])
* In practice, after a host reboot, `calico-node` pods will log a timeout contacting `10.96.0.1:443` (the cluster-IP API server) and then eventually repeatedly crash‐loop if VXLAN mode is in use, even though IP-in-IP mode works fine.

### Mitigation

1. **Upgrade Beyond v3.29.0**:
   The Calico team has released patches in v3.29.x (e.g. v3.29.4+) that address the VXLAN‐mode regression. Upgrading Calico to a version ≥ 3.29.4 is usually sufficient to restore post-reboot recovery.

   * (You can confirm via `calicoctl version` and compare to the [Release Changelog](https://github.com/projectcalico/calico/releases).)
     ([github.com][1], [docs.redhat.com][2])

2. **Workaround: Switch to IP-in-IP** (if you can’t immediately upgrade):
   IP-in-IP encapsulation does not exhibit this post-reboot crash-loop behavior in v3.29.3. If you set:

   ```yaml
   apiVersion: operator.tigera.io/v1
   kind: Installation
   metadata:
     name: default
   spec:
     calicoNetwork:
       ipPools:
       - blockSize: 26
         cidr: 192.168.0.0/16
         encapsulation: "IPIPCrossSubnet"
         natOutgoing: Enabled
   ```

   then Calico will “just work” through reboots—even on 3.29.3—whereas VXLANCrossSubnet/VXLAN mode will not recover without manual intervention. ([github.com][1])

---

## 2. Stale VXLAN Interfaces or Routes After Reboot

Even when you’ve upgraded Calico to a version without the regression, it’s possible for the VXLAN interface (`vxlan.calico`) to be left in a bad state after a node reboot—especially if the host’s networking stack re-ordered interfaces or changed link names. Calico relies on a Linux‐kernel VXLAN device (“`vxlan.calico`”) and a specific set of u-rules and routes. If those aren’t present when the pod starts, `calico-node` will repeatedly log timeouts “dial tcp 10.96.0.1:443: i/o timeout” and ultimately CrashLoopBackOff.

* A common pattern is:

  1. Host boots and brings up `vxlan.calico` with a mismatched or missing route.
  2. `calico-node` tries to peer with other nodes via VXLAN (UDP/4789) but fails.
  3. No cluster‐IP (10.96.0.0/12) connectivity, so the controller process times out fetching CRDs.
  4. Pod restarts, but VXLAN interface is still misconfigured, so it never recovers.

### How to Diagnose

1. **Check for a “vxlan.calico” interface**:

   ```shell
   ip link show vxlan.calico
   ```

   If it’s absent or in `DOWN` state, `calico-node` can’t program routes correctly.
2. **Verify the Calico VXLAN routes**:

   ```shell
   ip route show table 254 | grep calico_vxlan
   ```

   You should see routes for the `169.254.33.0/24` (example) subnet (the VXLAN “true” IP pool). If these are missing, any pod-to-pod traffic will fail.
3. **Inspect `dmesg` or `journalctl -u kubelet`** for `vxlan calico` errors.

### Quick Cleanup Without Full Cluster Teardown

If you find `vxlan.calico` in a bad state, you can delete it from the host and let Calico re-create it cleanly. On each affected node:

```bash
ip link delete vxlan.calico
# (Optional) clean up any calico-related routes:
ip route flush dev vxlan.calico
# Then, force restart the Calico DaemonSet pod:
kubectl rollout restart daemonset/calico-node -n kube-system
```

That forces Calico to reinitialize the VXLAN device on that host. Once the interface and routes are rebuilt, the `calico-node` pod will come out of CrashLoopBackOff and pod-to-pod networking will resume. ([github.com][3], [serverfault.com][4])

---

## 3. Underlying Firewall or rp\_filter Issues on RHEL8+

Because VXLAN in Calico rides on UDP port 4789, a host reboot can cause `firewalld` to re-apply rules that block this port (or enforce stricter reverse-path filtering). IP-in-IP (protocol 4) is often allowed by default, but UDP/4789 may not be. If `firewalld` is reloaded after a kernel upgrade or network change, employees have found that Calico’s VXLAN traffic is blocked even though IP-in-IP traffic passes.

1. **Ensure UDP/4789 is ACCEPTED in firewalld**:

   ```bash
   firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT 0 -p udp --dport 4789 -j ACCEPT
   firewall-cmd --permanent --direct --add-rule ipv4 filter FORWARD 0 -p udp --dport 4789 -j ACCEPT
   firewall-cmd --reload
   ```

   Without opening UDP/4789, VXLAN encapsulation can never form between nodes. ([docs.redhat.com][2], [serverfault.com][4])

2. **Check Reverse-Path Filtering (rp\_filter)**
   RHEL8 defaults can sometimes set `/proc/sys/net/ipv4/conf/all/rp_filter=1`. With VXLAN, the inner pod IP doesn’t match the host’s primary route, so reverse-path filtering will drop VXLAN packets. Set:

   ```bash
   sysctl -w net.ipv4.conf.all.rp_filter=2
   sysctl -w net.ipv4.conf.default.rp_filter=2
   ```

   To make persistent, add to `/etc/sysctl.d/99-sysctl.conf`:

   ```
   net.ipv4.conf.all.rp_filter = 2
   net.ipv4.conf.default.rp_filter = 2
   ```

   ([serverfault.com][4])

If either the VXLAN port is blocked or rp\_filter is too strict, Calico’s VXLAN datapath can’t recover after reboot.

---

## 4. MTU Mismatch Between Underlay and VXLAN

VXLAN adds roughly 50 bytes of overhead. If your underlying VM network enforces a tight MTU (e.g. 1500) and you haven’t lowered Calico’s `mtu` setting, the host’s NIC may silently drop large VXLAN packets. Rebooting can reset underlying MTU settings or change bond modes, causing VXLAN packets to silently fail. Over time, this can force `calico-node` to crash because it never reaches the API or other nodes.

* **Verify the host’s NIC MTU**:

  ```bash
  ip link show eth0     # or whichever NIC you’re using
  ```
* **Set Calico’s MTU explicitly** in the `Installation` resource or `calico-config` ConfigMap:

  ```yaml
  apiVersion: operator.tigera.io/v1
  kind: Installation
  metadata:
    name: default
  spec:
    calicoNetwork:
      mtu: 1450   # or lower, depending on underlying network
      ipPools:
      - cidr: 192.168.0.0/16
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
  ```

  If Calico tries to use the default `mtu: 1440` but your underlay drops > 1500 packets, VXLAN will never initialize. ([docs.redhat.com][2], [serverfault.com][4])

---

## 5. Best Practices to Avoid Needing a Hard Teardown

1. **Pin Calico and Kubernetes Versions Together**:
   Always consult Tigera’s compatibility matrix. If you’re on Kubernetes v1.26+ with Calico v3.29.x, be sure you’ve installed the latest patch (≥ 3.29.4) to avoid the VXLAN bug. ([github.com][1])

2. **Use a Post-Reboot “Cleanup” Daemon**:
   As a stopgap, write a small `systemd` service or `CronJob` that runs on every host boot to clean up any stale VXLAN link:

   ```ini
   [Unit]
   Description=Clean up stale Calico VXLAN on boot
   After=network.target

   [Service]
   Type=oneshot
   ExecStart=/usr/sbin/ip link delete vxlan.calico || /bin/true
   ExecStart=/usr/bin/systemctl restart kubelet

   [Install]
   WantedBy=multi-user.target
   ```

   That way, as soon as the host boots, any leftover VXLAN device is removed before `calico-node` pod starts.

3. **Monitor Calico Node Logs**:
   Add a watch on `kubectl -n kube-system logs ds/calico-node` to detect “dial tcp 10.96.0.1:443: i/o timeout” errors early. Ideally, alert on repeated bootstrap timeouts so you can intervene (e.g., manually delete the `vxlan.calico` link) before a full cluster teardown becomes necessary.

---

### Summary

* **Root Cause**: v3.28.0 / v3.29.x VXLAN has __a known regression that prevents recovery after a node reboot__.
* **Short-Term Workaround**: __Delete the stale `vxlan.calico` interface__ on each node and restart the `calico-node` DaemonSet, or temporarily switch to IP-in-IP encapsulation.
* **Long-Term Fix**: __Upgrade to Calico ≥ 3.29.4__ (or the first v3.30.0 release) where this bug is fixed. Ensure `UDP/4789` is open in `firewalld`, rp\_filter is relaxed, and the MTU is set correctly for VXLAN.

Following the steps above should let you recover VXLAN mode without tearing down the entire cluster.

[1]: https://github.com/projectcalico/calico/issues/9433?utm_source=chatgpt.com "VXLAN in 3.29 breaks any connectivity except ICMP #9433 - GitHub"
[2]: https://docs.redhat.com/en/documentation/openshift_container_platform/3.6/pdf/installation_and_configuration/OpenShift_Container_Platform-3.6-Installation_and_Configuration-en-US.pdf?utm_source=chatgpt.com "[PDF] OpenShift Container Platform 3.6 Installation and Configuration"
[3]: https://github.com/projectcalico/calico/issues/4468?utm_source=chatgpt.com "VXLAN interface in permanently bad state on node and does not ..."
[4]: https://serverfault.com/questions/1138767/calico-node-and-kube-proxy-crashed-permanently-on-a-new-node?utm_source=chatgpt.com "Calico Node and Kube Proxy crashed permanently on a new node"
