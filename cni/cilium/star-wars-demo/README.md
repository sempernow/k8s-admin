# [Cilium](https://github.com/cilium/cilium) : [Star Wars Demo](https://docs.cilium.io/en/stable/gettingstarted/demo/)

- Deployment `deathstar` of "`org: empire`" is the resource we want to protect
- Naked Pod `tiefighter` of "`org: empire`" is friendly.
- Naked Pod `xwing` of "`org: alliance`" is enemy.

```bash
☩ curl -fsSLO https://raw.githubusercontent.com/cilium/cilium/1.16.5/examples/minikube/http-sw-app.yaml

☩ kn default

☩ k apply -f  http-sw-app.yaml
service/deathstar created
deployment.apps/deathstar created
pod/tiefighter created
pod/xwing created

☩ k get pod,svc -o wide
NAME                            READY   STATUS    RESTARTS   AGE     IP             NODE   NOMINATED NODE   READINESS GATES
pod/deathstar-b4b8ccfb5-2lpn9   1/1     Running   0          2m45s   10.244.1.5     a2     <none>           <none>
pod/deathstar-b4b8ccfb5-bfbpz   1/1     Running   0          2m45s   10.244.2.135   a3     <none>           <none>
pod/tiefighter                  1/1     Running   0          2m45s   10.244.0.89    a1     <none>           <none>
pod/xwing                       1/1     Running   0          2m45s   10.244.0.87    a1     <none>           <none>

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE     SELECTOR
service/deathstar    ClusterIP   10.103.37.253   <none>        80/TCP    2m45s   class=deathstar,org=empire
...
```

Sans policy, __both__ fighters (`tiefighter`, `xwing`) __are allowed__ `POST` at `/request-landing` on `deathstar`.

```bash
# Friendly lands
☩ kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed

# Enemy lands
☩ kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed
```

### [Apply an __L3/L4 Policy__](https://docs.cilium.io/en/stable/gettingstarted/demo/#apply-an-l3-l4-policy)

Filter clients (Pods) by __`matchLabels`__

```bash
# Apply policy
☩ curl -fsSLO https://raw.githubusercontent.com/cilium/cilium/1.16.5/examples/minikube/sw_l3_l4_policy.yaml
☩ k apply -f  sw_l3_l4_policy.yaml
ciliumnetworkpolicy.cilium.io/rule1 created

# Friendly lands
☩ kubectl exec tiefighter -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
Ship landed

# Enemy cannont land
☩ kubectl exec xwing -- curl -s -XPOST deathstar.default.svc.cluster.local/v1/request-landing
command terminated with exit code 28 #... after looooong wait
```
- [`sw_l3_l4_policy.yaml`](sw_l3_l4_policy.yaml)

Pods having both __`matchLabels`__ "`org: empire`" and "`class: deathstar`" now have __`ingress` policy__ enforcement __`Enabled`__,
due to __`CiliumNetworkPolicy`__. 
See [`sw_l3_l4_policy.yaml`](sw_l3_l4_policy.yaml)

```bash
☩ kubectl -n kube-system exec cilium-vv8rf -c cilium-agent -- cilium-dbg endpoint list
ENDPOINT   POLICY (ingress)   POLICY (egress)   IDENTITY   LABELS (source:key[=value])                                                  IPv6   IPv4           STATUS
           ENFORCEMENT        ENFORCEMENT
...
2464       Enabled            Disabled          46474      k8s:app.kubernetes.io/name=deathstar                                                10.244.2.135   ready
                                                           k8s:class=deathstar
                                                           ...
                                                           k8s:org=empire
...
```
- `cilium-vv8rf` is on __same node__ as `deathstar` pod;
  different namespaces.

View __`CiliumNetworkPolicy`__ (`cnp`)

```bash
kubectl get cnp rule1 -o yaml
```

Yet this all-or-none access per `matchLabels` has limitations.
For example, our friendly though inexpt `tiefighter` has access to perform maintenance (`PUT`) on `/exhaust-port` with dire consequences:

```bash
☩ kubectl exec tiefighter -- curl -s -XPUT deathstar.default.svc.cluster.local/v1/exhaust-port
Panic: deathstar exploded
```

### [Apply and Test HTTP-aware __L7 Policy__](https://docs.cilium.io/en/stable/gettingstarted/demo/#apply-and-test-http-aware-l7-policy)

The fix is to filter per __`rules`__ (L7; HTTP method and path) upon those clients passing the `matchLabels` filter. See the additional __`CiliumNetworkPolicy`__ of [`sw_l3_l4_l7_policy.yaml`](sw_l3_l4_l7_policy.yaml)

```bash
# Apply policy
curl -fsSLO https://raw.githubusercontent.com/cilium/cilium/1.16.5/examples/minikube/sw_l3_l4_l7_policy.yaml
k apply -f sw_l3_l4_l7_policy.yaml
```
- [`sw_l3_l4_l7_policy.yaml`](sw_l3_l4_l7_policy.yaml)

Now the friendly though inexperienced `tiefighter` can't hurt `deathstar` when attempting `PUT` at `/exhaust-port`.

```bash
# Friendly does not have access to maintenance port
☩ kubectl exec tiefighter -- curl -s -XPUT deathstar.default.svc.cluster.local/v1/exhaust-port
Access denied
```
