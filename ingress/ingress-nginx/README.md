# [Ingress-NGINX Controller](https://kubernetes.github.io/ingress-nginx/deploy/#bare-metal-clusters "kubernetes.github.io") | [Releases](https://github.com/kubernetes/ingress-nginx/releases) | Configuration ( [GitHub](https://github.com/kubernetes/ingress-nginx/blob/main/docs/user-guide/nginx-configuration/index.md) | [kubernetes.github.io](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#configuration-options) )
 

## TL;DR

~~Using manifest method on generated helm template because bug in `--set controller.proxySetHeaders` causes non-string mapping on direct install by `helm upgrade ...`. ~~

Install by Chart method.

See [`ingress-nginx.sh`](ingress-nginx.sh).


## `Ingress` : Rewrite ([`rewrite-target`](https://github.com/kubernetes/ingress-nginx/blob/main/docs/examples/rewrite/README.md "github.com/kubernetes/ingress-nginx")) Syntax

URL rewrite rules are based on RegEx [Capture Group](https://www.regular-expressions.info/refcapture.html "regular-expressions.info")s, which are saved in numbered placeholders; `$1`, `$2` &hellip; `$n`.
So, rewrite rule `\$n` declares the capture group (of the request) that survives the rewrite, and is sent upstream. 

__Here are some example patterns__:

### 1. `/*` --> `/*`

Here there is no actual rewrite. 
Request for `/a1` is sent to upstream app as `/a1`.
The pattern is used only to optimize 
handling by NGINX processor.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
...
  annotations:
    # Apply rewrite to the 1st ($1) Capture Group.
    # That is, preserve only that group.
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$1
spec:
 ...
  rules:
    ...
      paths:
        # This 1st (only) capture group to capture everything after leading slash and rewrite to root. So actually rewrite nothing, yet this pattern informs NGINX to fully injest and process, resulting in optimized handling of edge-cases and query params.
      - path: /(.*) 
        # Inform K8s that path interpretation is performed by Ingress Controller (RegEx)
        pathType: ImplementationSpecific
        ...
```

>Different Ingress controllers support different annotations.

###  2. `/a/*` --> `/*`

```yaml
...
  annotations:
    # Apply rewrite to the 2nd ($2) Capture Group.
    # That is, preserve only that group.
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
..
      - path: /a(/|$)(.*)
        pathType: ImplementationSpecific

```
- `/a` is the literal string.
- `(/|$)` is the 1st capture group, 
  matching either a forward slash `/` 
  or the end of the string `($)`.
- `(.*)` is the 2nd capture group, 
   matching `/a` strictly, 
   or anything that comes after `/a/`.

So __client request__ `/a/1/2?q=v` 
is __rewritten__ to `/1/2?q=v`, 
__before it is sent upstream__. 
Request `/a` matches, yet `/aany` does not.

### 3. `/a/*` --> `/b/*`

```yaml
...
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /b/$1
...
      - path: /a/(.*)
        pathType: ImplementationSpecific

```

So, __client request__ `/a/any` matches and 
is __rewritten__ to `/b/any`, yet `/aany` does not match.

### `app-root: /a` 

```yaml
...
  annotations:
    nginx.ingress.kubernetes.io/app-root: /a
...
      - path: /
        pathType: Prefix
        ...
```
- Request of `http://foo.lime.lan/` responds with HTTP __redirect__:
    - Code: `302 Moved Temporarily`
    - Header: `Location: http://foo.lime.lan/a`

Respond to request of root (`/`) with redirect to app root `/a`. There is no interal rewrite; the application is not sent that original (`/`) request.


## Deploy (DaemonSet) : Baremetal (On-prem) Configuration

See "[Using a self-provisioned edge](https://kubernetes.github.io/ingress-nginx/deploy/baremetal/#using-a-self-provisioned-edge "Ingress NGINX Controller : Deployment : Bare-metal considerations")".

The Ingress-NGINX-Controller project uses the term "bare metal" as a synonym for on-prem, whether those hosts are "bare-metal" (physical sever) or on a hypervisor. Compare to the default by generating the manifest using "`helm template ...`". 

At the core of the on-prem Edge configuration is its Service, `ingress-nginx-controller`, configuration, which wires each service port (`http`, `https`) to a `nodePort` (`port`), 
each an upstream target of the external (HA)LB pool of such.

However, we needn't bother with the project's default baremmetal considerations configuration;  [__`ingress-nginx-baremetal-v1.12.0.yaml`__](ingress-nginx-baremetal-v1.12.0.yaml). __We have migrated past that on-prem Edge example__ to include its `NodePort` and such settings amongst other modifications of the chart's default `values.yaml` for our on-prem environments. Rather use the chart method of [__`ingress-nginx.sh`__](ingress-nginx.sh)

See [__`ingress-nginx.sh`__](ingress-nginx.sh)

Install by __Helm__ chart :

| Setting                                                    | Purpose                                                                                       |
| ---------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `controller.kind=DaemonSet`                                | Ensures each node has a controller pod, needed for `NodePort` + `externalTrafficPolicy=Local` |
| `controller.service.externalTrafficPolicy=Local`           | Preserves source IP for ingress controllers behind a TCP load balancer                        |
| `controller.config.use-proxy-protocol=true`                | Tells NGINX to expect and parse the PROXY protocol header                                     |
| `controller.config.enable-real-ip=true`                    | Enables use of `X-Forwarded-For` / real client IPs                                            |
| `controller.config.forwarded-for-header=X-Forwarded-For`   | Ensures consistent header interpretation                                                      |
| `controller.config.proxy-real-ip-cidr=$proxy_real_ip_cidr` | Crucial to trust only the HAProxy LB (e.g., `192.168.11.0/24`) as a legitimate PROXY sender   |


```yaml
apiVersion: v1
kind: Service
metadata:
  ...
  name: ingress-nginx-controller
  namespace: ingress-nginx
spec:
  type: NodePort
  ports:

  - appProtocol: http
    name: http
    port: 30080
    protocol: TCP
    targetPort: http

  - appProtocol: https
    name: https
    port: 30443
    protocol: TCP
    targetPort: https
  ...
```


## All [Configuration Options](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#configuration-options) of Ingress NGINX


__For example__:

Modify the `ConfigMap` (`cm.ingress-nginx-controller`) 
of a release __to overwrite any parameter__.


```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    app.kubernetes.io/instance: ingress-nginx
    app.kubernetes.io/name: ingress-nginx
    ...
data:
  ## Configuration Options : 
  ## - All keys and values of ConfigMap must be type *string*.
  ## - Use `helm install ... --set cm.data.$key=$val` to override default/values settings.
  ## https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
  ##
  ## Enable allow-snippet-annotations grants access to Ingress objects, which may modify nginx.conf
  allow-snippet-annotations: "true"
  annotation-value-word-blocklist: "load_module,lua_package,_by_lua,location,root,proxy_pass,serviceaccount,{,},',\""
  ## client-body-buffer-size : "0" # No limit, else HTTP 413 if over limit.
  client-body-buffer-size: "4096m" # E.g., allow clients to upload OCI-images
  ssl-protocols: "TLSv1.2 TLSv1.3" # Restrict TLS versions
  ssl-ciphers: "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384." #... the default list
  ## use-proxy-protocol : Must set this key to "true" if the downstream 
  ## (external HA)LB uses PROXY protocol, else must set to "false".
  ## In TCP (TLS-passthrough) mode, HAProxy (LB) configured for "send-proxy" 
  ## adds cleartext PROXY-protocol header(s) to TLS payload. 
  ## NGINX responds HTTP 400 if not so informed of PROXY protocol/mode.
  ## https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/#use-proxy-protocol
  use-proxy-protocol: "true" # Default: "false"
  ## enable-real-ip : To preserve client-endpoint IP address under PROXY protocol.
  enable-real-ip: "true"
  forwarded-for-header: "X-Forwarded-For" # Default: "X-Forwarded-For"
  proxy-real-ip-cidr: "192.168.11.0/24"   # Default: "0.0.0.0/0"

```

## E2E Test : [__`e2e/test-ingress.sh`__](e2e/test-ingress.sh)


## Metrics of Ingress NGINX

Enable them. See [__`values.diff.yaml`__](values.diff.yaml).

### Options to Expose the Metrics Service

Quick test : Expose by `port-forward`ing the Service

```bash
☩ kubectl port-forward svc/ingress-nginx-controller-metrics -n ingress-nginx 8080:10254 &
[1] 33329
Forwarding from [::1]:8080 -> 10254

☩ curl -fsSIX GET http://localhost:8080/healthz
...
HTTP/1.1 200 OK
...
```

Better to __patch__ the metrics Service,
`ingress-nginx-controller-metrics`,
from `type: ClusterIP` __to `type: NodePort`__

```bash
kubectl patch svc ingress-nginx-controller-metrics -n ingress-nginx -p '{"spec":{"type":"NodePort"}}'

☩ kubectl patch svc ingress-nginx-controller-metrics -n ingress-nginx -p '{"spec":{"type":"NodePort"}}'
service/ingress-nginx-controller-metrics patched

☩ k get svc
NAME                                 TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller             NodePort    10.103.201.149   <none>        80:30080/TCP,443:30443/TCP   48m
ingress-nginx-controller-admission   ClusterIP   10.103.122.51    <none>        443/TCP                      48m
ingress-nginx-controller-metrics     NodePort    10.97.37.75      <none>        10254:31435/TCP              25m

# Confirm
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
METRICS_PORT=$(kubectl get svc ingress-nginx-controller-metrics -n ingress-nginx -o jsonpath='{.spec.ports[0].nodePort}')
curl http://$NODE_IP:$METRICS_PORT/healthz

# Or simply
☩ curl -fsS http://kube.lime.lan:31435/healthz
ok
```

Better yet to leave as `type: ClusterIP` 
and rather expose it using Ingress:

@ `values.diff.yaml` : Add ...

```yaml
controller:
  metrics:
    service:
      type: ClusterIP  # Keep as ClusterIP
      
  extraArgs:
    metrics-port: "10254"

  # Add ingress for metrics
  extraResources:
    - apiVersion: networking.k8s.io/v1
      kind: Ingress
      metadata:
        name: nginx-metrics
        annotations:
          nginx.ingress.kubernetes.io/rewrite-target: /metrics
      spec:
        ingressClassName: nginx
        rules:
        - host: metrics.yourdomain.com
          http:
            paths:
            - path: /
              pathType: Prefix
              backend:
                service:
                  name: ingress-nginx-controller-metrics
                  port:
                    number: 10254
```

## [Monitoring](https://kubernetes.github.io/ingress-nginx/user-guide/monitoring/) : Prometheus/Grafana


### Mods to `values.diff.yaml`

To enable the Prometheus metrics interface in the `ingress-nginx` Helm chart, several key configurations in the `values.yaml` file need to be modified. Here’s a breakdown of the changes required:

---

#### **1. Enable Metrics in the Controller**
The primary setting to enable Prometheus metrics is:
```yaml
controller:
  metrics:
    enabled: true  # Must be set to true
```
This exposes the metrics endpoint on port `10254` by default .

---

#### **2. Configure the Metrics Service**
To create a dedicated `ClusterIP` service for metrics:
```yaml
controller:
  metrics:
    service:
      enabled: true  # Creates a Service for metrics
      type: ClusterIP  # Default; change to NodePort/LoadBalancer for external access
      port: 10254      # Metrics port
```
This service allows Prometheus to scrape the metrics internally .

---

#### **3. Add Pod Annotations (Optional)**
For Prometheus to auto-discover the metrics endpoint via pod annotations:
```yaml
controller:
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "10254"
```
This is useful if Prometheus is configured to scrape pods with these annotations .

---

#### **4. Enable ServiceMonitor (For Prometheus Operator)**
If using `kube-prometheus-stack`, enable the `ServiceMonitor`:
```yaml
controller:
  metrics:
    serviceMonitor:
      enabled: true
      additionalLabels:
        release: PROMETHEUS_OPERATOR_RELEASE    # Match Prometheus Operator's selector
      namespace: PROMETHEUS_OPERATOR_NAMESPACE  # Match Prometheus namespace


```
This automatically creates a `ServiceMonitor` resource for Prometheus to scrape metrics .

---

#### **5. Adjust Metrics Port (Optional)**
To change the default metrics port (e.g., to `9113`):
```yaml
controller:
  extraArgs:
    metrics-port: "9113"  # Overrides default 10254
  metrics:
    port: 9113            # Update service port accordingly
```
This aligns with some configurations where Prometheus expects metrics on port `9113` .

---

#### ~~**6. Enable Latency Metrics (Optional)**~~ 

__OBSOLETE : Handled automatically__

For upstream latency metrics:
```yaml
controller:
  extraArgs:
    enable-latency-metrics: "true"
```
This adds metrics like `controller_upstream_server_response_latency_ms_count` .

---

#### **Summary of Key Changes**
| Parameter | Purpose | Default | Required? |
|-----------|---------|---------|-----------|
| `controller.metrics.enabled` | Enable metrics endpoint | `false` | Yes |
| `controller.metrics.service.enabled` | Create metrics `Service` | `false` | Yes |
| `controller.metrics.serviceMonitor.enabled` | Create `ServiceMonitor` | `false` | If using Prometheus Operator |
| `controller.podAnnotations` | Auto-discovery by Prometheus | None | Optional |
| `controller.extraArgs.metrics-port` | Custom metrics port | `10254` | Optional |

---

#### **Verification**
After applying these changes:
1. Check the metrics service:
   ```bash
   kubectl get svc -n ingress-nginx | grep metrics
   ```
2. Test the endpoint:
   ```bash
   kubectl port-forward svc/ingress-nginx-controller-metrics -n ingress-nginx 10254:10254
   curl http://localhost:10254/metrics
   ```
3. For Prometheus Operator, verify the `ServiceMonitor`:
   ```bash
   kubectl get servicemonitor -n ingress-nginx
   ```


### [Ingress NGINX : Grafana Dashboard ](https://github.com/kubernetes/ingress-nginx/tree/main/deploy/grafana/dashboards)

#### [Grafana : __Import `ingress-nginx` Dashboard__

Instructions at [Ingress NGINX](https://kubernetes.github.io/ingress-nginx/user-guide/monitoring/#connect-and-view-grafana-dashboard) are __obsolete__.

-Download the Ingress NGINX project's Dashboard JSON (__`nginx.json`__) from one of:
    - https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/grafana/dashboards/nginx.json
    - https://github.com/kubernetes/ingress-nginx/tree/main/deploy/grafana/dashboards
- Click on "Dashboards" (Left-side panel)
    - Click "New" button
        - Select "Import" 
            - Import the JSON (by file upload, or string paste)
            - Enter the Grafana.com dashboard ID (9614)
- Configure the Data Source:
    - After importing, Grafana prompts to select a __Prometheus data source__
        - Select same data source we're using for Ingress-Nginx metrics
            - Typically "__Prometheus__"
    - Click "Import"


To add a data source:

1. Select "Data Sources" from Grafana menu (Left-side pane)
2. Click "__+ Add new data source__" button
3. Select __prometheus-1__ and enter at form input:
    - Connection: http://10.111.170.42:9090  
    That IP address and port are that Prometheus' `Service` : 
    ```bash
    svc=kps-kube-prometheus-stack-prometheus
    kubectl -n kube-metrics get svc $svc -o yaml \
        |yq '.spec | {
            "ip": .clusterIP,
            "port": (.ports[] | select(.name == "http-web").port)
        }'
    ```