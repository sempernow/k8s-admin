# https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.Installation
# 
# BPF via patch:
# kubectl patch installation.operator.tigera.io default --type merge -p '{"spec":{"calicoNetwork":{"linuxDataplane":"BPF", "hostPorts":null}}}'
# DSR via patch: 
# calicoctl patch felixconfiguration default --patch='{"spec": {"bpfExternalServiceMode": "DSR"}}'
# watch kubectl get tigerastatus
# Disable kube-proxy by adding a node selector that matches no nodes:
# kubectl patch ds -n kube-system kube-proxy -p '{"spec":{"template":{"spec":{"nodeSelector":{"non-calico": "true"}}}}}'
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: kubernetes-services-endpoint
  namespace: tigera-operator
data:
  KUBERNETES_SERVICE_HOST: "K8S_CONTROL_IP"
  KUBERNETES_SERVICE_PORT: "K8S_CONTROL_PORT"
---
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  variant: Calico
  cni:
    type: Calico
  controlPlaneReplicas: 2
  calicoNetwork:
    ## https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.CalicoNetworkSpec
    linuxDataplane: BPF # BPF, Iptables
    bgp: Enabled
    ipPools:
    - cidr: "K8S_POD_CIDR" 
      blockSize: K8S_NODE_CIDR_MASK # Per node
      natOutgoing: Enabled  # Enable NAT for outbound traffic.
      nodeSelector: all()   # Apply to all nodes.
      ## Encapsulation : IPIPCrossSubnet, IPIP, VXLAN, VXLANCrossSubnet, None
      encapsulation: None
  serviceCIDRs:
    - "K8S_SERVICE_CIDR"
  nodeUpdateStrategy:
    rollingUpdate:
      maxUnavailable: 25%   # Configure rolling updates.

---
# This section configures the Calico API server.
# For more information, see: https://docs.tigera.io/calico/latest/reference/installation/api#operator.tigera.io/v1.APIServer
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
