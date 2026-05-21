# Kubernetes : STIG vs. firewalld

To achieve STIG-compliant firewalld results on a RHEL-based `kubeadm` cluster using Red Hat tools, use Ansible and the official **Red Hat System Roles**.

## Step-by-Step: The Red Hat Way for Kubeadm (Ansible)

Instead of a MachineConfig (OpenShift), Red Hat provides a built-in, STIG-compliant infrastructure-as-code solution called **Red Hat System Roles**. The rhel-system-roles.firewall role cleanly manages firewalld configurations programmatically.

### 1. Install the System Roles on your Admin/Ansible Host

On your control machine running RHEL, install the system roles package:

```bash
sudo dnf install rhel-system-roles -y
```

### 2. Create the Inventory File (`inventory.yml`)

Group your kubeadm nodes by their respective control plane and worker roles:

```yaml
---
all:
  children:
    kube_cluster:
      children:
        control_plane:
          hosts:
            example.com:
            example.com:
        workers:
          hosts:
            192.168.1.50:  # Raw IP addresses work perfectly too
            192.168.1.51:
```

### 3. Create the Ansible Playbook (`secure-k8s-firewall.yml`)

This playbook configures firewalld using Red Hat's native variables, opening the exact ports needed for a standard kubeadm cluster while maintaining a restrictive host posture. [6, 8] 

```yaml
---
- name: Configure STIG-Compliant Firewalld for Kubeadm Cluster
  hosts: kube_cluster
  become: true
  vars:
    # Ensure firewalld is running and enabled per STIG requirements
    firewall_service: firewalld
    firewall_state: started
    firewall_enabled: true
    
  tasks:
    - name: Apply common Kubernetes node firewall settings
      include_role:
        name: rhel-system-roles.firewall
      vars:
        firewall:
          - zone: public
            state: enabled
            permanent: true
            # Common ports required by ALL nodes in the cluster
            port:
              - 10250/tcp  # Kubelet API
              - 10256/tcp  # kube-proxy health check
              - 4789/udp   # VXLAN overlay (Calico/Flannel default)
              - 6081/udp   # Geneve overlay (if using OVN)

    - name: Apply Control-Plane specific firewall settings
      include_role:
        name: rhel-system-roles.firewall
      vars:
        firewall:
          - zone: public
            state: enabled
            permanent: true
            # Master/Control-Plane exclusive ports
            port:
              - 6443/tcp   # Kubernetes API Server
              - 2379/tcp   # etcd client
              - 2380/tcp   # etcd peer
              - 10257/tcp  # kube-controller-manager
              - 10259/tcp  # kube-scheduler
      when: "'control_plane' in group_names"
```

### 4. Execute the Playbook

Run the playbook against your cluster hosts to apply and lock down the settings:

```yaml
ansible-playbook -i inventory.ini secure-k8s-firewall.yml
```

---

## If You Absolutely Need an "Operator" Experience (Declarative Node Config)

If your goal was to have a Kubernetes operator natively manage host-level settings inside your kubeadm cluster (similar to how OpenShift MCO behaves), you must use alternative cloud-native open-source tools:

* **Systemd/File management**: Use the Kubernetes Node Tuning Operator (NTO) or open-source equivalents like the Tinkerbell hooks or Cluster API (CAPI) bootstrap providers if you are building an automated infrastructure lifecycle.
* **Network-level security**: Instead of relying strictly on host OS firewalld zones to control inner-cluster traffic, deploy Cilium or Calico NetworkPolicies. They bypass host-level daemon configurations and enforce zero-trust pod-to-pod filtering natively inside the Linux kernel via eBPF or iptables. [6] 

[1] [https://github.com](https://github.com/openshift/machine-config-operator)
[2] [https://docs.okd.io](https://docs.okd.io/latest/post_installation_configuration/day_2_core_cnf_clusters/troubleshooting/troubleshooting-mco.html)
[3] [https://xphyr.net](https://xphyr.net/post/machine_configs_and_mcp/)
[4] [https://www.redhat.com](https://www.redhat.com/en/blog/openshift-container-platform-4-how-does-machine-config-pool-work)
[5] [https://purplecarrot.co.uk](https://purplecarrot.co.uk/post/2021-12-19-machineconfigoperator/)
[6] [https://oneuptime.com](https://oneuptime.com/blog/post/2026-03-04-how-to-install-a-kubernetes-cluster-with-kubeadm-on-rhel/view)
[7] [https://kubernetes.io](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/)
[8] [https://developer.ibm.com](https://developer.ibm.com/tutorials/set-up-kubernetes-on-rhel-running-on-power/)



---

<!-- 

… ⋮ ︙ • ● – — ™ ® © ± ° ¹ ² ³ ¼ ½ ¾ ÷ × ₽ € ¥ £ ¢ ¤ ♻ ⚐ ⚑ ✪ ❤  \ufe0f
☢ ☣ ☠ ¦ ¶ § † ‡ ß µ Ø ƒ Δ ☡ ☈ ☧ ☩ ✚ ☨ ☦ ☓ ♰ ♱ ✖  ☘  웃 𝐀𝐏𝐏 🡸 🡺 ➔
ℹ️ ⚠️ ✅ ⌛ 🚀 🚧 🛠️ 🔧 🔍 🧪 👈 ⚡ ❌ 💡 🔒 📊 📈 🧩 📦 🥇 ✨️ 🔚

# Markdown Cheatsheet

[Markdown Cheatsheet](https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet "Wiki @ GitHub")

# README HyperLink

README ([MD](__PATH__/README.md)|[HTML](__PATH__/README.html)) 

# Bookmark

- Target
<a name="foo"></a>

- Reference
[Foo](#foo)

-->
