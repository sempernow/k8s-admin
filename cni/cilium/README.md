# [Cilium](https://github.com/cilium/cilium)  | [ArtifactHUB.io](https://artifacthub.io/packages/helm/cilium/cilium/)

## Features

- [eBPF Datapath](https://docs.cilium.io/en/stable/network/ebpf/intro/)
- [LB IPAM](https://docs.cilium.io/en/stable/network/lb-ipam/) : Allows Cilium to assign IP addresses to `Service`s of type `LoadBalancer`. This functionality is __usually left up to a cloud provider__, however, when deploying in a private cloud environment, these facilities are not always available. This feature is always enabled, yet dormant until controller is awoken when the first IP Pool (`CiliumLoadBalancerIPPool`) is added to the cluster. See "`kubectl get ippools`"
    - [BGP Control Plane](https://docs.cilium.io/en/stable/network/bgp-control-plane/bgp-control-plane-v2/#bgp-cluster-configuration)
    - [L2 Announcements / L2 Aware LB](https://docs.cilium.io/en/stable/network/l2-announcements/#l2-announcements) (Beta)

Validate `KubeProxyReplacement`

```bash
kubectl -n kube-system exec ds/cilium -- cilium-dbg status \
    |grep KubeProxyReplacement
```
- `--verbose`

## TL;DR 

The driver for Cilium is eBPF AKA DirectPath mode, yet properly configuring that is a labyrinth of methods, protocols and parameters.

## Download : `download` of [cilium.sh](cilium.sh)

## Routing

Direct (__eBPF Datapath__; L3) v. Encapsulated (Overlay/VXLAN)

For the best performance on east-west traffic in a single-subnet cluster, the Direct Datapath is usually the industry recommendation.

Verify routing:

```bash
cilium config view |grep tunnel
```
- If `tunnel` is set to `vxlan` or `geneve`, it’s __Encapsulated__.
- If `tunnel` is unst, it’s __Datapath Direct__.

Cilium defaults do not enabling its __eBPF Datapath__ (`native`). It's default routing mode is rather by __encapsulation__ (`vxlan` or `geneve`)

The `native` packet forwarding mode leverages the routing capabilities of the network Cilium runs on instead of performing encapsulation.

@ `cm.cilium-config.data`

```yaml
ipam: kubernetes
routing-mode: native
datapath-mode: veth
ipv4-native-routing-cidr: 10.244.0.0/16
k8s-require-ipv4-pod-cidr: "true"
```

If a BGP daemon is running and there is multiple native subnets to the cluster network, optionally give each node L2 connectivity in each zone without traffic always needing to be routed by the BGP routers:

@ `cm.cilium-config.data`

```yaml
direct-routing-skip-unreachable: "true"
auto-direct-node-routes: "true"
```

## [Install](https://chatgpt.com/c/6749a5f4-ad00-8009-9166-ad815bc10bfc "ChatGPT")

Install by __`cilium`__ host __CLI__ or `helm` CLI. 
Regardless of install method, the project's Helm chart is applied.
Cilium configuration state is kept in `ConfigMap` `cilium-config` of `Namespace` `kube-system`, which may be edited directly, else per CLI.

Note the `cilium-*` (__Cilium Agent__) Pods have their own CLI, __`cilium-dbg`__, which is widely referenced in documentation, though without context.

### [CLI method](https://docs.cilium.io/en/stable/gettingstarted/k8s-install-default/) 


@ [`cilium.sh`](cilium.sh)

```bash 
cilium install [flags]

cilium install ... --dry-run-helm-values

cilium install --values $values --version 1.16.5

cilium upgrade --reuse-values --set ... --set ... ...
```
- `--reuse-values` on upgrade __else all existing configuration is deleted__ from `ConfigMap` `cilium-config`, except for those at current imperatives; "`--set ... --set ...`"
- `--dry-run-helm-values` flag generates YAML for subsequent use;
    however, does no linting; 
    is a pure mapping to YAML per syntax; 
    will map "`--set foo[0].bar=2`" to `foo: [{"bar": 2}]`
- `--version 1.16.5`
- `--values cilium.values.yaml` 
    - Note [`cilium.values.yaml](cilium.values.yaml) 
      is __not__ `values.yaml` of Helm.
- `--context lime` 
    - Must be one of `kubeconfig`.
- `--kubeconfig ~/.kube/config`
- `--set routingMode=native`
- `--set tunnelProtocol=""`
- `--set bgpControlPlane.enabled=true`
    - Augments `bgp.enabled=true`, otherwise is dormant; 
      however that requires an out-of-band ConfigMap.
- `--set ipam.mode=kubernetes` 
    - To abide `podCIDR` of `kubeadm init`
    - `--set k8s.requireIPv4PodCIDR=true`
    - `--set k8s.requireIPv6PodCIDR=false`
- `--set nodeIPAM.enabled=true`
- `--set kubeProxyReplacement=true` : 
  [To replace `kube-proxy`](https://docs.cilium.io/en/stable/network/kubernetes/kubeproxy-free/#kubeproxy-free) 
  : Requires:
    - `--set k8sServiceHost=${K8S_CONTROL_IP}`
    - `--set k8sServicePort=${K8S_CONTROL_PORT}`
    - 
- Add Hubble
    - `--set hubble.ui.enabled='true'`
    - `--set hubble.relay.enabled='true'`

See function __`install_by_cli`__ of [__cilium.sh__](cilium.sh)

Verify install ...

```bash
cilium status --wait
cilium config view
helm list -n kube-system
```
```plaintext
NAME    NAMESPACE       REVISION        UPDATED                                 STATUS          CHART           APP VERSION
cilium  kube-system     4               2025-01-03 15:26:50.168436737 -0500 EST deployed        cilium-1.16.3   1.16.3
```

```bash
kubectl get cm cilium-config -o yaml \
    |yq .data.tunnel-protocol 
    #> <nothing> if eBPF Datapath, else "vxlan"

kubectl get cm cilium-config -o yaml \
    |yq .data.routing-mode 
    #> native if eBPF Datapath

kubectl -n kube-system exec ds/cilium -c cilium-agent -- \
    cilium-dbg status 

```

Test : applies objects to Namespace `cilium-test-1`

```bash
cilium connectivity test |& tee cilium.connectivity.test.log
```

### [Helm method](https://docs.cilium.io/en/stable/installation/k8s-install-helm/ "docs.cilium.io") | [Helm params reference](https://docs.cilium.io/en/stable/helm-reference/#helm-reference)

```bash
helm upgrade cilium cilium/cilium --install --values $values

```

See function __`install_by_helm`__ of [__cilium.sh__](cilium.sh)

### Enable Hubble

```bash
cilium upgrade \
    --reuse-values \
    --set hubble.ui.enabled='true' \
    --set hubble.relay.enabled='true'

cilium status --wait
```
```plaintext
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
Deployment             hubble-relay       Desired: 1, Ready: 1/1, Available: 1/1
Deployment             hubble-ui          Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium             Running: 3
                       cilium-envoy       Running: 3
                       cilium-operator    Running: 2
                       hubble-relay       Running: 1
                       hubble-ui          Running: 1
```
```bash
cilium hubble ui
   #> Opening "http://localhost:12000" in your browser...

```

## `cilium` (host) v. `cilium-dbg` (ctnr)

__`cilium-dbg`__

```bash
☩ kubectl -n kube-system exec ds/cilium -c cilium-agent -- \
    cilium-dbg
```
```plaintext
CLI for interacting with the local Cilium Agent

Usage:
  cilium-dbg [command]

Available Commands:
  bgp                    Access to BGP control plane
  bpf                    Direct access to local BPF maps
  build-config           Resolve all of the configuration sources that apply to this node
  cgroups                Cgroup metadata
  completion             Output shell completion code
  config                 Cilium configuration options
  debuginfo              Request available debugging information from agent
  encrypt                Manage transparent encryption
  endpoint               Manage endpoints
  envoy                  Manage Envoy Proxy
  fqdn                   Manage fqdn proxy
  help                   Help about any command
  identity               Manage security identities
  ip                     Manage IP addresses and associated information
  kvstore                Direct access to the kvstore
  loadinfo               Show load information
  lrp                    Manage local redirect policies
  map                    Access userspace cached content of BPF maps
  metrics                Access metric status
  monitor                Display BPF program events
  node                   Manage cluster nodes
  nodeid                 List node IDs and associated information
  policy                 Manage security policies
  post-uninstall-cleanup Remove system state installed by Cilium at runtime
  prefilter              Manage XDP CIDR filters
  preflight              Cilium upgrade helper
  recorder               Introspect or mangle pcap recorder
  service                Manage services & loadbalancers
  statedb                Inspect StateDB
  status                 Display status of daemon
  troubleshoot           Run troubleshooting utilities to check control-plane connectivity
  version                Print version information

Flags:
      --config string   Config file (default is $HOME/.cilium.yaml)
  -D, --debug           Enable debug messages
  -h, --help            help for cilium-dbg
  -H, --host string     URI to server-side API

Use "cilium-dbg [command] --help" for more information about a command.
```

__`cilium`__

```bash
☩ cilium
```
```plaintext
CLI to install, manage, & troubleshooting Cilium clusters running Kubernetes.

Cilium is a CNI for Kubernetes to provide secure network connectivity and
load-balancing with excellent visibility using eBPF

Examples:
# Install Cilium in current Kubernetes context
cilium install

# Check status of Cilium
cilium status

# Enable the Hubble observability layer
cilium hubble enable

# Perform a connectivity test
cilium connectivity test

Usage:
  cilium [flags]
  cilium [command]

Available Commands:
  bgp          Access to BGP control plane
  clustermesh  Multi Cluster Management
  completion   Generate the autocompletion script for the specified shell
  config       Manage Configuration
  connectivity Connectivity troubleshooting
  context      Display the configuration context
  encryption   Cilium encryption
  help         Help about any command
  hubble       Hubble observability
  install      Install Cilium in a Kubernetes cluster using Helm
  multicast    Manage multicast groups
  status       Display status
  sysdump      Collects information required to troubleshoot issues with Cilium and Hubble
  uninstall    Uninstall Cilium using Helm
  upgrade      Upgrade a Cilium installation a Kubernetes cluster using Helm
  version      Display detailed version information

Flags:
      --context string             Kubernetes configuration context
      --helm-release-name string   Helm release name (default "cilium")
  -h, --help                       help for cilium
      --kubeconfig string          Path to the kubeconfig file
  -n, --namespace string           Namespace Cilium is running in (default "kube-system")

Use "cilium [command] --help" for more information about a command.

```

### Add __Hubble__ 

```bash
☩ cilium upgrade \
    --reuse-values \
    --set hubble.ui.enabled='true' \
    --set hubble.relay.enabled='true'

☩ cilium hubble ui
   Opening "http://localhost:12000" in your browser... # Blocks
```
```bash
☩ cilium status
```
```plaintext
    /¯¯\
 /¯¯\__/¯¯\    Cilium:             OK
 \__/¯¯\__/    Operator:           OK
 /¯¯\__/¯¯\    Envoy DaemonSet:    OK
 \__/¯¯\__/    Hubble Relay:       OK
    \__/       ClusterMesh:        disabled

DaemonSet              cilium             Desired: 3, Ready: 3/3, Available: 3/3
DaemonSet              cilium-envoy       Desired: 3, Ready: 3/3, Available: 3/3
Deployment             cilium-operator    Desired: 2, Ready: 2/2, Available: 2/2
Deployment             hubble-relay       Desired: 1, Ready: 1/1, Available: 1/1
Deployment             hubble-ui          Desired: 1, Ready: 1/1, Available: 1/1
Containers:            cilium             Running: 3
                       cilium-envoy       Running: 3
                       cilium-operator    Running: 2
                       hubble-relay       Running: 1
                       hubble-ui          Running: 1
Cluster Pods:          5/5 managed by Cilium
...
```

## Data Rate test : East-west traffic : `iperf3`

@ Server

```bash
☩ k -n default run nbox --image=nicolaka/netshoot -- \
    iperf3 -s
pod/nbox created

☩ k get pod -o wide -n default
NAME   READY   STATUS    RESTARTS   AGE   IP            NODE   NOMINATED NODE   READINESS GATES
nbox   1/1     Running   0          12s   10.244.1.44   a2     <none>           <none>

☩ ip=10.244.1.44
```

@ Client : __Same node__

```bash
☩ node=a2

☩ k -n default run nbox2 -it --rm \
    --image=nicolaka/netshoot \
    --overrides='{"spec": {"nodeName": "'$node'"}}' \
    --restart=Never -- \
    iperf3 -c $ip
...
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  55.1 GBytes  47.4 Gbits/sec  748             sender
[  5]   0.00-10.00  sec  55.1 GBytes  47.4 Gbits/sec                  receiver
```

@ Client : __Cross node__

```bash
☩ node=a1

☩ k -n default run nbox2 -it --rm \
    --image=nicolaka/netshoot \
    --overrides='{"spec": {"nodeName": "'$node'"}}' \
    --restart=Never -- \
    iperf3 -c $ip
...
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  7.68 GBytes  6.60 Gbits/sec  404             sender
[  5]   0.00-10.00  sec  7.68 GBytes  6.60 Gbits/sec                  receiver

```