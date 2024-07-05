# [`kube-proxy`](https://github.com/cloudnativelabs/kube-router/) | [User Guide](https://github.com/cloudnativelabs/kube-router/blob/master/docs/user-guide.md)

>Kube-router uses IPVS/LVS technology built in Linux to provide L4 load balancing. Each `ClusterIP`, `NodePort`, and `LoadBalancer` Kubernetes `Service` type is configured as an __IPVS virtual service__. Each Service Endpoint is configured as real server to the virtual service. The standard `ipvsadm` tool can be used to verify the configuration and monitor the active connections.

## [Docs](https://github.com/cloudnativelabs/kube-router/tree/master/docs)

- [How it works](https://github.com/cloudnativelabs/kube-router/blob/master/docs/how-it-works.md)
- [Deploying kube-router with kubeadm](https://github.com/cloudnativelabs/kube-router/blob/master/docs/kubeadm.md)

## Data Rate

```bash
☩ kubectl run nbox --image=nicolaka/netshoot -- iperf3 -s
pod/nbox created

☩ kubectl run nbox2 -it --rm --image=nicolaka/netshoot -- iperf3 -c 10.22.2.8
...
[  5]   7.00-8.00   sec   722 MBytes  6.06 Gbits/sec    0   2.92 MBytes
[  5]   8.00-9.00   sec   693 MBytes  5.81 Gbits/sec    0   3.08 MBytes
[  5]   9.00-10.00  sec   639 MBytes  5.37 Gbits/sec    0   3.24 MBytes
- - - - - - - - - - - - - - - - - - - - - - - - -
[ ID] Interval           Transfer     Bitrate         Retr
[  5]   0.00-10.00  sec  6.87 GBytes  5.90 Gbits/sec   84             sender
[  5]   0.00-10.00  sec  6.87 GBytes  5.90 Gbits/sec                  receiver
```

That's as fast as either Calico or Cilium, with the exception of Cilium's DirectPath mode having a labyrinth of undocumented parameters and is far too brittle to be useful for anything but as a toy.

## Node tools

View 

```bash
type -t ipvsadm || sudo dnf install -y ipvsadm
sudo ipvsadm -L  # List the virtual server table by HOST:SCHEME
sudo ipvsadm -Ln # List the virtual server table by IP:PORT


```
