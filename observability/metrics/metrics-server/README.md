# [`metrics-server`](https://github.com/kubernetes-sigs/metrics-server "GitHub") | [K8s Metrics API](https://kubernetes.io/docs/tasks/debug/debug-cluster/resource-metrics-pipeline/ "kubernetes.io")

## Install : [`metrics-server.sh](metrics-server.sh)

```bash
☩ bash metrics-server.sh
```

```bash
☩ k top node
NAME   CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
a1     183m         9%       2059Mi          57%
a2     162m         8%       2099Mi          59%
a3     167m         8%       2094Mi          58%

☩ k top pod -A
NAMESPACE            NAME                                            CPU(cores)   MEMORY(bytes)
kube-system          coredns-76f75df574-bqc89                        1m           43Mi
kube-system          coredns-76f75df574-f7p42                        1m           74Mi
kube-system          etcd-a1                                         22m          109Mi
kube-system          etcd-a2                                         21m          101Mi
kube-system          etcd-a3                                         24m          151Mi
kube-system          kube-apiserver-a1                               26m          329Mi
kube-system          kube-apiserver-a2                               25m          323Mi
kube-system          kube-apiserver-a3                               22m          288Mi
kube-system          kube-controller-manager-a1                      8m           58Mi
kube-system          kube-controller-manager-a2                      1m           66Mi
kube-system          kube-controller-manager-a3                      1m           129Mi
kube-system          kube-router-2cjd8                               1m           98Mi
...
rook-ceph            csi-cephfsplugin-provisioner-784d9966c6-rttbv   1m           99Mi
rook-ceph            csi-cephfsplugin-provisioner-784d9966c6-v8jrc   2m           109Mi
rook-ceph            csi-cephfsplugin-xp594                          1m           161Mi
...
rook-ceph            csi-rbdplugin-provisioner-75cfd96674-xr2ll      2m           240Mi
rook-ceph            rook-ceph-crashcollector-a1-7c54587697-spx4z    0m           6Mi
...
rook-ceph            rook-ceph-mgr-a-78cc55dd4c-mfqjb                35m          525Mi
rook-ceph            rook-ceph-mgr-b-86c6bf4594-6hncb                30m          508Mi
...
rook-ceph            rook-ceph-operator-659f7d85-tzhq8               16m          142Mi
...

☩ kubectl get --raw /apis/metrics.k8s.io/v1beta1/nodes |jq .
# Or, running `kubectl proxy` @ another terminal (blocks)
☩ curl http://127.0.0.1:8001/apis/metrics.k8s.io/v1beta1/nodes |jq .
```
```json
{
  "kind": "NodeMetricsList",
  "apiVersion": "metrics.k8s.io/v1beta1",
  "metadata": {},
  "items": [
    {
      "metadata": {
        "name": "a1",
        "creationTimestamp": "2024-12-28T13:06:41Z",
        "labels": {
          "beta.kubernetes.io/arch": "amd64",
          "beta.kubernetes.io/os": "linux",
          "kubernetes.io/arch": "amd64",
          "kubernetes.io/hostname": "a1",
          "kubernetes.io/os": "linux",
          "node-role.kubernetes.io/control-plane": "",
          "node.kubernetes.io/exclude-from-external-load-balancers": ""
        }
      },
      "timestamp": "2024-12-28T13:06:35Z",
      "window": "20.068s",
      "usage": {
        "cpu": "190188160n",
        "memory": "2111508Ki"
      }
    },
    {
      "metadata": {
        "name": "a2",
        ...
      },
      ...,
      "usage": {
        "cpu": "148977030n",
        "memory": "2160796Ki"
      }
    },
    {
      "metadata": {
        "name": "a3",
        ...
      },
      ...,
      "usage": {
        "cpu": "148769813n",
        "memory": "2156024Ki"
      }
    }
  ]
}
```