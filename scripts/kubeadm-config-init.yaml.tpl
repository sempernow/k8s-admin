---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
## https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/#kubeadm-k8s-io-v1beta3-InitConfiguration
## Certificate Key : Declare static ok, even on : 64 char hex : "openssl rand -hex 32"
certificateKey: $K8S_CERTIFICATE_KEY
# bootstrapTokens:
# ## --token=$(kubeadm token generate)
# - token: $K8S_BOOTSTRAP_TOKEN
#   ttl: 24h
#   usages:
#   - authentication
#   - signing
#   groups:
#   - system:bootstrappers:kubeadm:default-node-token
## Local API Endpoint is *not* the cluster (External LB) endpoint
# localAPIEndpoint:
#   advertiseAddress: 1.2.3.4  # IP address of this control node
#   bindPort: 6443             # 6443 (default)
nodeRegistration:
  name: "$K8S_NODE_INIT" # Defaults to $(hostname)
  # imagePullPolicy: IfNotPresent ## Always|Never|IfNotPresent (default)
  criSocket: $K8S_CRI_SOCKET
  # taints: null   # Default taints on control nodes
  taints: []       # No taints on control nodes
  # taints:        # []core/v1.Taint
  # - key: "kubeadmNode"
  #   value: "someValue"
  #   effect: "NoSchedule"
  # ignorePreflightErrors:
  # - Mem         # Useful at VM having dynamically-allocated memory.
  # kubeletExtraArgs:
  ## k-v maps to inline arg by prepending `--`,
  ## so k-v `pod-cidr: <cidr>` becomes arg `--pod-cidr <cidr>` .
  ## See kubelet --help
  ## Some kubeletExtraArgs are exclusive to Standalone mode,
  ## which is enabled by omitting `--kubeconfig` flag.
  #   v: "5"
  #   pod-cidr: "$K8S_POD_CIDR"
  #   cgroup-driver: $K8S_CGROUP_DRIVER
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
## https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/#kubeadm-k8s-io-v1beta3-ClusterConfiguration
## RELEASEs https://kubernetes.io/releases/
## Capture after init and store to /etc/kubernetes/kubeadm-config.yaml
## kubectl -n kube-system get cm kubeadm-config -o yaml |yq .data.ClusterConfiguration
kubernetesVersion: $K8S_VERSION
# imageRepository: $K8S_REGISTRY
apiServer:
  timeoutForControlPlane: 3m # Wait for apiserver to appear
  extraArgs:    # map[string]string : arg(s), each sans leading dashes
    #tls-cipher-suites: "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
    #tls-cipher-suites: "TLS_AES_128_GCM_SHA256,TLS_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384"
    # Verify : kubectl -n kube-system logs <kube-apiserver-pod-name> |grep tls-cipher-suites
    # Or     : psk kube-apiserver |grep tls-cipher-suites
    # Check FIPS compliance of host : cat /proc/sys/crypto/fips_enabled
  extraVolumes: # []HostPathMount
  certSANs:     # []string          : SANs of API Server signing certificate.
clusterName: $K8S_CLUSTER_NAME
## External LB endpoint else that of init node
controlPlaneEndpoint: "$K8S_CONTROL_ENTRYPOINT"
controllerManager:
## https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta3/#kubeadm-k8s-io-v1beta3-ControlPlaneComponent
## https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/
  extraArgs:
    allocate-node-cidrs: "true"
    cluster-cidr: "$K8S_POD_CIDR"
#   extraVolumes: []
# dns: {}
# etcd:
#   local:
#     dataDir: /var/lib/etcd
networking:
  #dnsDomain: cluster.local
  ## Services subnet CIDR : Default is 10.96.0.0/12
  serviceSubnet: "$K8S_SERVICE_CIDR"
  ## Pod subnet CIDR      : Default is 10.244.0.0/16
  podSubnet: "$K8S_POD_CIDR"
# scheduler: {}
apiVersion: kubeadm.k8s.io/v1beta4
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
## https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/#kubelet-config-k8s-io-v1beta1-KubeletConfiguration
## Kubelet is PER NODE : See kubelet -h
## FS @ /var/lib/kubelet/config.yaml
## systemd @ "systemctl cat kubelet.service"
## GET @ "kubectl -n kube-system get cm kubelet-config -o jsonpath='{.data.kubelet}'"
## Defaults @ "kubeadm config print init-defaults --component-configs KubeletConfiguration" 
## Restart kubelet.service on any change to its --config CONFIG
# enableServer: true
# imageGCHighThresholdPercent: 85
# imageGCLowThresholdPercent: 80
## Default authentication schemes okay:
# authentication:
#   anonymous:
#     enabled: false
#   webhook:
#     cacheTTL: 0s
#     enabled: true
#   x509:
#     clientCAFile: /etc/kubernetes/pki/ca.crt
# authorization:
#   mode: Webhook
#   webhook:
#     cacheAuthorizedTTL: 0s
#     cacheUnauthorizedTTL: 0s
## Docker-K8s shim : /var/run/cri-docker.sock
##   https://github.com/mirantis/cri-dockerd
##   https://www.mirantis.com/blog/the-future-of-dockershim-is-cri-dockerd/
##   https://mirantis.github.io/cri-dockerd/usage/install/
containerLogMaxSize: 1Mi  # Default is 10Mi
containerLogMaxFiles: 5   # Default is 5
containerRuntimeEndpoint: $K8S_CRI_SOCKET
cgroupDriver: $K8S_CGROUP_DRIVER
## Node Allocatable
## https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/
## WARNINGS : General Guidelines 
## https://kubernetes.io/docs/tasks/administer-cluster/reserve-compute-resources/#general-guidelines
## Reserve ample resources for control plane, especially if node is dual use.
## https://unofficial-kubernetes.readthedocs.io/en/latest/tasks/administer-cluster/reserve-compute-resources/
## Rather than Node Allocatable scheme, rely on Pod QoS : Guaranteed
## https://kubernetes.io/docs/tasks/configure-pod-container/quality-service-pod/#create-a-pod-that-gets-assigned-a-qos-class-of-guaranteed
# systemReserved:   # host
#   cpu: "500m"
#   memory: "1Gi"
#   ephemeral-storage: "1Gi"
# kubeReserved:     # K8s
#   cpu: "1000m"
#   memory: "2Gi"
#   ephemeral-storage: "1Gi"
# enforceNodeAllocatable:
#   - "pods"
#   - "system-reserved"
#   - "kube-reserved"
# clusterDomain: cluster.local
## Hairpin mode affects Pod requests of their own Services by
## disallowing localhost, so Service requests *always* go through svc route (vEth/IP).
hairpinMode: hairpin-veth
# healthzBindAddress: 127.0.0.1
# healthzPort: 10248
# imageGCHighThresholdPercent: 85
# imageGCLowThresholdPercent: 80
# imageMinimumGCAge: 2m
evictionHard:
  nodefs.available: "<10%"
  imagefs.available: "<15%"
  memory.available: "<500Mi"
evictionSoft:
  nodefs.available: "<15%"
  imagefs.available: "<20%"
evictionSoftGracePeriod:
  nodefs.available: "1m"
  imagefs.available: "1m"
evictionMaxPodGracePeriod: 30
evictionPressureTransitionPeriod: 30s
nodeStatusReportFrequency: 10s
nodeStatusUpdateFrequency: 10s
runtimeRequestTimeout: 2m
volumeStatsAggPeriod: 1m
syncFrequency: 1m
rotateCertificates: true
cpuManagerReconcilePeriod: 10s
fileCheckFrequency: 20s
httpCheckFrequency: 10s
logging:
  flushFrequency: 5s
  verbosity: 0
shutdownGracePeriod: 30s
shutdownGracePeriodCriticalPods: 10s
streamingConnectionIdleTimeout: 0s
## TLS Params : See https://pkg.go.dev/crypto/tls#pkg-constants
# tlsCipherSuites: []
# tlsCipherSuites:
#   - TLS_AES_128_GCM_SHA256
#   - TLS_AES_256_GCM_SHA384
#   - TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256
#   - TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
#   - TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256
#   - TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384
tlsMinVersion: VersionTLS12
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
## @ "kubectl -n kube-system get cm kube-proxy -o yaml |yq -Mr '.data["config.conf"]'"
## https://kubernetes.io/docs/reference/config-api/kube-proxy-config.v1alpha1/#kubeproxy-config-k8s-io-v1alpha1-KubeProxyConfiguration
mode: "ipvs"                            # Use IPVS for better performance and scalability compared to iptables.
clusterCIDR: "$K8S_POD_CIDR"             # Replace with your cluster's pod network CIDR.
detectLocalMode: "ClusterCIDR"          # Detect local traffic based on the cluster CIDR.
healthzBindAddress: "0.0.0.0:10256"
metricsBindAddress: "0.0.0.0:10249"     # Enable metrics for monitoring tools (Prometheus, etc.).
# hostnameOverride: "$K8S_NODE_INIT"       # Overriding current hostname prevents future changes from being injested by K8s,
                                        # which has caused systemic mTLS failure on the subsequent rotation.
                                        # However, this setting would be required at each node?
ipvs:
  strictARP: true                       # Ensures traffic is only processed if it belongs to the node.
  scheduler: "rr"                       # Use Round Robin for IPVS load balancing.
  minSyncPeriod: 0s                     # If 0s, then every Service or EndpointSlice change triggers immediate resync.
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig.conf"
conntrack:
  maxPerCore: 32768                     # Adjust based on workload; default is usually sufficient.
  min: 131072                           # Minimum conntrack entries; increase if under heavy traffic.
  tcpCloseWaitTimeout: 60s              # Shorten for faster resource cleanup.
  tcpEstablishedTimeout: 30m0s          # Default timeout for long-lived connections.
  udpStreamTimeout: 30s
  udpTimeout: 300s
iptables:
  masqueradeAll: false                  # Only masquerade traffic that needs it; some CNI require true.
  minSyncPeriod: 0s                     # If 0s, then every Service or EndpointSlice change triggers immediate resync.
  syncPeriod: 30s                       # Periodic refresh of iptables rules as safety net for a failed event trigger.
nftables:
  masqueradeAll: false                  # Only masquerade traffic that needs it; some CNI require true.
  minSyncPeriod: 0s                     # If 0s, then every Service or EndpointSlice change triggers immediate resync.
  syncPeriod: 30s                       # Periodic refresh of iptables rules as safety net for a failed event trigger.
configSyncPeriod: 1m0s                  # Periodic updates from apiserver
logging:
  flushFrequency: 10s                   # Periodic flush from its own buffer to the storage medium or logging sink
  options:
    json:
      infoBufferSize: "0"
  verbosity: 0                          # 0-5; 0 is only the most important and error messages.
