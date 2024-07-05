
# Network Security : firewalld v. CNI plugin

The two overlap a lot in terms of what they provide, 
but each has super-powers the other fundamentally lacks.


| Capability                                 | firewalld (nftables/iptables) | Calico (iptables mode) | Calico (eBPF mode) | Cilium (eBPF) | Who wins? |
|--------------------------------------------|---------------------------------------|------------------------|--------------------|---------------|---------------|
| Zone-based policies (interface → policy)   | Excellent                             | No                     | No                 | No            | firewalld |
| Rich services (port + protocol names)         | Excellent                             | Basic                  | Basic              | Basic         | firewalld |
| Easy host-level allow/deny for non-k8s services| Excellent                            | No                     | No                 | No            | firewalld |
| Per-pod granularity (apply rules to specific pod) | Impossible                          | Yes (via NetworkPolicy) | Yes               | Yes           | CNI plugins |
| L7 (HTTP, gRPC, Kafka, DNS) policy             | No                                    | No                     | Very limited       | Excellent     | Cilium |
| Identity-based policy (not IP-based)          | No                                    | No                     | Yes (limited)      | Excellent     | Cilium/Calico eBPF |
| Visibility / flow logs at L7                  | No                                    | No                     | Basic              | Excellent     | Cilium |
| Zero-trust enforcement inside the cluster     | No                                    | Yes (NetworkPolicy)    | Yes                | Yes           | CNI plugins |
| Replace kube-proxy entirely                   | No                                    | No                     | No                 | Yes           | Cilium |
| Enforce policy without kube-proxy side-effects| No                                    | No                     | Yes                | Yes           | Cilium/Calico eBPF |
| Performance (bypasses netfilter entirely)     | Slow (netfilter hook)                 | Slow                   | Fast               | Extremely fast| eBPF CNIs |
| Host firewall for node itself (SSH, NTP, etc.)| Yes                                   | Usually not            | Usually not        | Usually not   | firewalld |
| Integration with cloud security groups        | Manual                                | Manual                 | Manual             | Native (some clouds) | Tie |


### Real-world conclusion most clusters reach today (2025)

| Cluster type                                 | Typical setup                                                                                   |
|----------------------------------------------|-------------------------------------------------------------------------------------------------|
| Simple clusters, bare-metal, or small clouds | firewalld (or nftables directly) for host protection + Calico/Flannel + Kubernetes NetworkPolicy |
| Medium clusters that want zero-trust         | firewalld only for host ports + Calico eBPF or Cilium for all pod-to-pod and ingress/egress policy |
| High-security or high-performance clusters   | Turn firewalld completely off on worker nodes → let Cilium (or Calico eBPF) own the entire stack (host policies + pod policies + kube-proxy replacement) |
| Regulated environments that must lock down nodes | firewalld stays on and manages node ports (22, 9099, node-exporter, etc.) while Cilium/Calico enforce pod isolation |

### Bottom line

- firewalld → unbeatable for simple, host-level, zone-based firewalling of the node itself  
- Modern eBPF CNI plugins (Cilium >> Calico eBPF) → unbeatable for per-pod, identity-aware, L7-aware, high-performance Kubernetes-native security

They are **complementary**, not subsets.  
Most mature clusters run both: firewalld (or equivalent) for the node, and Cilium/Calico for the workloads.  
A growing number of Cilium clusters disable firewalld completely on workers because Cilium’s Host Policies now cover everything firewalld used to do — and faster.

---

# Cloud Environments

In cloud environments (AWS, GCP, Azure, etc.), **subnet-level routing, security groups and such network-security rules are a very strong and offer complete replacement for firewalld on the nodes themselves** — especially for worker nodes running only Kubernetes workloads.

Here is the practical comparison in 2025:

| What to protect / control              | firewalld per node (classic way) | Cloud subnet + SG/NSG/NACL (modern way) | Who wins in cloud-native k8s? |
|-----------------------------------------------|-------------------------------------|------------------------------------------|-------------------------------|
| Block SSH / unauthorized access to the node   | Yes                                 | Yes (Security Group rule)                | Cloud wins (centralized, immutable) |
| Allow only Prometheus / node-exporter / metrics| Yes                                | Yes (SG rule 0.0.0.0/0 → 9100 only from monitoring VPC) | Cloud wins |
| Prevent nodes from talking to the internet    | Yes (default deny egress)           | Yes (no route to IGW + deny-all SG egress or NACL) | Cloud wins (harder to tamper with) |
| Prevent nodes from talking to metadata service| Yes (iptables drop to 169.254.169.254)| Yes (SG or route table blackhole)       | Cloud wins |
| Allow only VXLAN/BGP/WireGuard between workers| Yes (open 4789, 179, etc.)          | Yes (SG allowing only worker subnet ↔ worker subnet on those ports) | Cloud wins |
| Protect non-Kubernetes services running on node (rare)| Yes                              | Sometimes painful                        | firewalld wins |
| Auditability & change management              | Local, easy to drift                | Centralized in cloud console / IaC       | Cloud wins decisively |
| Survivability if node is compromised          | Attacker can flush iptables         | Attacker cannot modify SG or route table (if IAM is correct) | Cloud wins decisively |
| Performance impact                            | Small, but still netfilter          | Zero (rules enforced in VPC silicon)     | Cloud wins |

### What almost all cloud-native clusters actually do in 2025

| Provider | Typical pattern for worker nodes                                                                 |
|----------|--------------------------------------------------------------------------------------------------|
| **EKS**  | - Nodes in private subnets<br>- No public IP<br>- Security group: inbound only from control-plane SG + monitoring SG + intra-worker SG (for CNI)<br>- Egress: either NAT GW or VPC endpoint for ECR/API<br>- firewalld completely disabled or set to trusted/public with no extra rules |
| **GKE**  | - Private cluster → nodes in private subnet<br>- Alias IP or VPC-native routing<br>- Firewall rules instead of node firewalld<br>- firewalld disabled |
| **AKS**  | - VNet integration or Azure CNI<br>- NSG applied directly on subnet or NIC<br>- firewalld disabled |
| **DigitalOcean, Linode, Civo, etc.** | Same idea — VPC firewall rules + private networking → firewalld off |

### When you still keep firewalld (or equivalent) running

Only in these minority cases:

1. **Bare-metal or hybrid clusters** (no cloud security groups)
2. **Very strict compliance** that requires a local host firewall even when cloud controls exist (defense, some finance)
3. You run **non-container workloads** directly on the nodes (databases, message queues, etc.) that are not managed by Kubernetes
4. You use a CNI that still requires certain host ports open in a very dynamic way that is hard to express in static cloud rules

### Bottom line for cloud Kubernetes in 2025

For worker nodes that only run Kubernetes components + pods:

**Subnet-perimeter security (Security Groups / Network Security Rules + route tables) completely and superiorly replaces firewalld.**

Most mature organizations now:

- Disable firewalld (or set it to `target=ACCEPT` / `trusted`)
- Manage all node-level access via cloud security groups and route tables
- Let Cilium or Calico eBPF handle the per-pod / zero-trust layer inside the cluster

The only place firewalld usually stays enabled is on bastions, control-plane nodes (if self-hosted), or in air-gapped/on-prem environments.

---

# SOCKS5 : Public Access by Nodes on Private Subnet

Forcing a private Kubernetes node (or any private host) to reach NTP (or any other UDP/TCP service) **only via a SOCKS5 proxy on a bastion** 
is a **very secure and defense-in-depth–friendly topology**. 
More so if combined with the usual cloud security-group / route-table controls.

It is used successfully in high-security environments (banks, defense contractors, some government Kubernetes clusters).

### Why this topology is strong for NTP (and similar services)

| Threat / requirement                              | How “private host → bastion SOCKS5 only” solves it                                                                 | Strength |
|-----------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------|----------|
| Direct internet access from nodes             | Completely impossible — no route to 0.0.0.0/0, no NAT GW                                                            | Excellent |
| Attackers on a compromised node phoning home  | They can only reach the internet via authenticated + logged SOCKS5 on the bastion                                 | Excellent |
| NTP amplification / reflection attacks        | Node never sends raw UDP to the internet — all NTP traffic is TCP-wrapped inside authenticated SOCKS5               | Excellent |
| Malicious or misconfigured pods syncing time from fake NTP servers | Pods/nodes can only reach the NTP servers you explicitly allow in the bastion to allow                               | Excellent |
| Credential theft for the proxy                | Use short-lived client certificates or one-time SSH keys (-D with -N -W) instead of passwords                        | Excellent |
| Logging & audit                                       | Every single NTP request (src IP, dst IP:port, bytes, timestamp) is logged on the bastion                            | Excellent |
| Performance / latency                         | Negligible for NTP (one packet every few minutes)                                                                  | Excellent |

### Most common secure implementations in 2025

| Variant                         | How it is usually deployed in hardened clusters    | Tools used      |
|---------------------------------|----------------------------------------------------|-----------------|
| SSH dynamic SOCKS (-D)          | Node runs `ssh -f -N -D 127.0.0.1:1080 bastion` with key-based auth and `ProxyCommand` / `Match exec` restrictions            | OpenSSH + chrony/ntpd configured with `socks5-hostname 127.0.0.1:1080` |
| Dedicated SOCKS5 proxy          | Dante, 3proxy, or tinyproxy running only on the bastion with client-certificate authentication                               | Dante-server + client certs                                                |
| Corporate proxy integration     | SOCKS5 wrapper → corporate Zscaler / BlueCoat / Netskope that already enforces DLP and allow-lists                     | Zscaler Private Access (ZPA) or similar                                    |
| Cilium + egress gateway         | Cilium eBPF enforces that all egress traffic (including NTP) must go via a specific egress-gateway pod that runs the SOCKS5 client | Cilium EgressGateway + Envoy or Dante                                      |

### Example: OpenSSH + chrony (most popular in air-gapped/high-sec clusters)

On every worker node (in immutable image or DaemonSet):

1. Start the SOCKS5 proxy

```bash
# 1. SSH key that can only port-forward, no shell
ssh -f -N -D 127.0.0.1:1080 \
    -o StrictHostKeyChecking=yes \
    -o ExitOnForwardFailure=yes \
    -i /etc/ssh/ntp_key bastion.ntp-proxy.corp

```

2. Configure crony time synch to use SOCKS5 proxy

```bash
# Install chrony if not present
sudo apt update && sudo apt install chrony   # Debian/Ubuntu
# or
sudo dnf install chrony                      # RHEL/Rocky/Alma

# Tell chrony to use SOCKS5 proxy (replace 127.0.0.1:1080 with your proxy)
sudo tee /etc/chrony/chrony.conf > /dev/null <<EOF
# Use reliable HTTPS time servers (all return JSON or plain text)
server time.cloudflare.com iburst nts
server worldtimeapi.org iburst nts port 443
server time.google.com iburst nts
server time.apple.com iburst nts

# Force all outbound traffic through SOCKS5 proxy
proxy socks5h://127.0.0.1:1080

# Optional: higher polling, better for slow proxies
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF

# Restart and verify
sudo systemctl restart chrony
sudo systemctl enable chrony

# Check it’s working through the proxy
sudo tail -f /var/log/chrony/measurements.log | grep -E "(time.cloudflare|worldtimeapi)"
chronyc sources
chronyc tracking
```

An example request by client on worker node using that tunnel:

```bash

# GET list of timezones as JSON
curl -sSf --socks5 127.0.0.1:8080 https://worldtimeapi.org/api/timezone

# GET response JSON from echo server
curl --sSf -socks5 127.0.0.1:8080 https://echo.free.beeceptor.com
```

At dedicated service account (system user) on bastion (`authorized_keys` restriction):

@ `/var/lib/ntp-proxy/.ssh/authorized_keys`

```bash
command="echo 'SOCKS5 only'",no-pty,no-agent-forwarding,no-X11-forwarding,permitopen="pool.ntp.org:123",permitopen="time.cloudflare.com:123"
ssh-rsa AAAAB3Nz...
```

That is, &hellip;

```bash
# 1. Create a dedicated, non-login service account
sudo adduser --system --home /var/lib/ntp-proxy --shell /usr/sbin/nologin ntp-proxy

# 2. Create .ssh directory with correct (tight) permissions
sudo mkdir -p /var/lib/ntp-proxy/.ssh
sudo touch /var/lib/ntp-proxy/.ssh/authorized_keys
sudo chown -R ntp-proxy: /var/lib/ntp-proxy/.ssh
sudo chmod 700 /var/lib/ntp-proxy/.ssh
sudo chmod 600 /var/lib/ntp-proxy/.ssh/authorized_keys

# 3. Put the restricted key in the file
sudo tee /var/lib/ntp-proxy/.ssh/authorized_keys <<EOF
command="echo 'SOCKS5 proxy only – no shell'",\
no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding,\
permitopen="pool.ntp.org:123",\
permitopen="time.cloudflare.com:123",\
permitopen="time.windows.com:123"
ssh-ed25519 AAAAC3NzaC... k8s-ntp-client-key

```

→ The node can **never** open a raw socket to the internet, only to the four NTP endpoints you explicitly allowed.

### Remaining (tiny) risks and how to close them

| Risk                            | Mitigation                                                                 |
|---------------------------------|----------------------------------------------------------------------------|
| Bastion itself compromised      | Harden bastion like a fortress (minimal OS, 2FA, central logging, eBPF monitoring) |
| DNS spoofing inside SOCKS5      | Use TLS-wrapped NTP (nts) or at least restrict permitopen to exact hosts/ports |
| SOCKS5 implementation bugs      | Prefer OpenSSH dynamic port-forwarding (battle-tested) over third-party daemons |

### Bottom line

**Private host → bastion-only SOCKS5 internet access is one of the most secure topologies you can build for NTP (and for package downloads, DNS, etc.) in 2025**.  
It is stronger than “just open UDP/123 in the security group” and is actively used in many zero-trust Kubernetes deployments.

---

## Common command options and usage of __`authorized_keys`__ file

Though most people only ever see plain public keys in `authorized_keys`, that file is __one of the most powerful access-control files in all of Unix__, not just a key dump.  
Every zero-trust or air-gapped Kubernetes fleet exploits this heavily.

The magic is that **every line in `authorized_keys` is actually a full set of options followed by the key**, and OpenSSH has supported this since ~2002. You can put very powerful restrictions in front of every single key.

### What an `authorized_keys` line is really made of

```
options... ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD... comment
↑              ↑                                        ↑
options     public key blob                       optional comment
```

Everything before the key type (`ssh-rsa`, `ssh-ed25519`, etc.) is zero or more comma-separated options.

### The options most commonly used in hardened Kubernetes/air-gapped environments

| Option                              | What it does                                                                 | Typical use in bastion setups |
|-------------------------------------|------------------------------------------------------------------------------|-------------------------------|
| `command="cmd"`                     | Forces this command to run instead of a shell, no matter what the client asks | `command="echo no shell"` |
| `no-pty`                            | Prevents allocation of a pseudo-tty                                          | Always used |
| `no-agent-forwarding`               | Blocks ssh-agent forwarding                                                  | Always used |
| `no-X11-forwarding`                 | Blocks X11 forwarding                                                        | Always used |
| `no-port-forwarding`                | Blocks -L, -R, and -D (all port forwarding)                                 | Used when you want no tunnels |
| `permitopen="host:port"`            | With -D or -L, only allows forwarding to exactly these destinations         | **The key one for SOCKS5-only** |
| `from="pattern"`                    | Restricts source IP(s) or hostnames the key may connect from                 | `from="10.0.0.0/8"` |
| `restrict`                          | Shortcut that enables all the “no-*” restrictions in one word                | Very common now |

### Real-world examples from production clusters (2024–2025)

```ini
# 1. Absolutely no shell, no forwarding at all
restrict ssh-ed25519 AAAAC3N... k8s-emergency-key

# 2. SOCKS5 only, but only to specific NTP servers
command="echo 'SOCKS5 only'",no-pty,no-agent-forwarding,no-X11-forwarding,
permitopen="pool.ntp.org:123",permitopen="time.nist.gov:123"
ssh-ed25519 AAAAC3N... k8s-ntp-key

# 3. Git clone only (common for image building)
command="/usr/local/bin/git-shell-wrapper",no-pty,no-agent-forwarding,no-X11-forwarding,no-port-forwarding
ssh-ed25519 AAAAC3N... k8s-builder-key
```

### Quick test you can do right now

On any Linux box:

```bash
mkdir -p ~/.ssh
cat >> ~/.ssh/authorized_keys <<EOF
command="echo You shall not pass; false" ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... test-key
EOF

# Now try to log in with that key → instant disconnect with the message
```

