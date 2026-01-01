# Vector + Elasticsearch + Kibana - Working Logging Solution

## Why This Works (When Fluentd/Fluent-bit Failed)

**The Problem with Fluentd/Fluent-bit:**
- Require per-application log parsers (nginx, apache, custom formats)
- Only capture logs matching configured parsers
- Miss all application logs that don't match the parser regex patterns
- This is why you only saw Kubernetes core pod logs

**Why Vector Works:**
- **Zero per-application configuration required**
- Automatically captures ALL container logs regardless of format
- Intelligent JSON parsing with fallback to plain text
- Enriches logs with Kubernetes metadata automatically
- No hardcoded parsers needed

## Architecture

```
┌─────────────────┐
│   All Pods      │
│  (Any Format)   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Vector DaemonSet│  ← Runs on every node
│  Auto-discovers │     Reads /var/log/containers/*.log
│  all containers │     No per-app config needed
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Elasticsearch   │  ← Stores all logs
│   Index: logs-* │     Indexed by date
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Kibana       │  ← Web UI for log viewing
│  NodePort:30561 │     Access via http://NODE_IP:30561
└─────────────────┘
```

### How Vector Processes Logs

Vector applies the following transformations to ensure compatibility with Kibana:

1. **JSON Parsing**: Attempts to parse log messages as JSON; falls back to plain text if parsing fails
2. **Timestamp Normalization**: Ensures all logs have the `@timestamp` field that Kibana requires:
   - If a log already has `@timestamp` (e.g., from Elasticsearch pods), it's preserved
   - If a log has `timestamp` but not `@timestamp`, it copies `timestamp` → `@timestamp`
   - If neither exists, creates `@timestamp` with the current time
3. **Kubernetes Metadata**: Automatically enriches logs with pod, namespace, container, and node information
4. **Custom Fields**: Adds cluster identification and log type markers

This ensures **all logs are searchable in Kibana** regardless of their original format.

## Deploy

```bash
# Apply the complete stack
kubectl apply -f vector-efk-complete.yaml

# Wait for Elasticsearch to be ready (takes 2-3 minutes)
kubectl wait --for=condition=ready pod -l app=elasticsearch -n logging --timeout=300s

# Wait for Kibana to be ready
kubectl wait --for=condition=ready pod -l app=kibana -n logging --timeout=300s

# Wait for Vector DaemonSet to be ready
kubectl rollout status daemonset/vector -n logging
```

## Verify

```bash
# Check all components are running
kubectl get pods -n logging

# Expected output:
# NAME                      READY   STATUS    RESTARTS   AGE
# elasticsearch-0           1/1     Running   0          2m
# kibana-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
# vector-xxxxx              1/1     Running   0          2m  (one per node)
# vector-xxxxx              1/1     Running   0          2m
# vector-xxxxx              1/1     Running   0          2m

# Check Vector logs to confirm it's collecting
kubectl logs -n logging daemonset/vector --tail=50

# Check Elasticsearch has received logs
kubectl exec -n logging elasticsearch-0 -- curl -s 'http://localhost:9200/_cat/indices?v'

# You should see indices like: logs-2026.01.01
```

## Access Kibana

Kibana is exposed as NodePort 30561:

```bash
# Get node IP
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo "Kibana URL: http://${NODE_IP}:30561"
```

Or access via any node:
- http://a1.lime.lan:30561
- http://a2.lime.lan:30561
- http://a3.lime.lan:30561

## Initial Kibana Setup

**Note:** Kibana 8.x uses "Data Views" (formerly "Index Patterns"). The UI validation can be problematic, so use the API method below.

### Create Data View via API (Recommended)

```bash
# Run the setup script
./logging/kibana-setup.sh

# Or manually via kubectl:
kubectl exec -n logging deployment/kibana -- curl -X POST \
  "http://localhost:5601/api/data_views/data_view" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "data_view": {
      "title": "logs-*",
      "timeFieldName": "@timestamp",
      "name": "Logs"
    }
  }'
```

### Access Logs in Kibana

1. Open Kibana in browser (http://NODE_IP:30561)
2. Click the hamburger menu (☰) in the top-left
3. Go to **Analytics** → **Discover**
4. The **"logs-*"** data view should be automatically selected
5. You should now see all your container logs!

### Useful Filters and Queries

- Filter by namespace: `kubernetes.pod_namespace: "kube-system"`
- Filter by pod: `kubernetes.pod_name: "test-logger"`
- Search errors: `level: "error" OR level: "ERROR"`
- Search exceptions: `message: *exception*`

**Note:** The correct field name is `kubernetes.pod_namespace`, not `kubernetes.namespace_name`.

## Test with Sample Application

Deploy a test app to verify logs are captured:

```bash
kubectl run test-logger --image=busybox:1.36 --restart=Never -- sh -c 'while true; do echo "Test log message at $(date)"; sleep 5; done'

# Wait 30 seconds, then check Kibana
# Search for: kubernetes.pod_name:"test-logger"
```
- Elasticsearch is verifited to have the logs, but Kibana sees no match to any filter `kubvernetes.pod_namespce : default` nor any other namespace except `logging`.

## Storage Considerations

The current config uses:
- **Elasticsearch**: 10Gi PersistentVolume per replica
- **Vector**: emptyDir (stateless, uses disk buffer for reliability)

For production, adjust storage in `vector-efk-complete.yaml`:

```yaml
# Line ~215: Elasticsearch storage
volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: [ "ReadWriteOnce" ]
      resources:
        requests:
          storage: 100Gi  # ← Adjust based on log volume
```

## Resource Requirements

**Minimum per component:**
- Elasticsearch: 1Gi RAM, 500m CPU
- Kibana: 512Mi RAM, 500m CPU
- Vector (per node): 128Mi RAM, 100m CPU

**Recommended for production:**
- Elasticsearch: 4Gi RAM, 2 CPU, SSD storage
- Kibana: 1Gi RAM, 1 CPU
- Vector: 512Mi RAM, 500m CPU

## Troubleshooting

### No logs appearing in Kibana

```bash
# 1. Check Vector is running on all nodes
kubectl get pods -n logging -l app=vector -o wide

# 2. Check Vector logs for errors
kubectl logs -n logging daemonset/vector --tail=100

# 3. Verify Vector can reach Elasticsearch
kubectl exec -n logging -it daemonset/vector -- wget -O- http://elasticsearch.logging.svc.cluster.local:9200/_cluster/health

# 4. Check Elasticsearch health
kubectl exec -n logging elasticsearch-0 -- curl -s 'http://localhost:9200/_cluster/health?pretty'

# 5. Verify indices are being created
kubectl exec -n logging elasticsearch-0 -- curl -s 'http://localhost:9200/_cat/indices?v'
```

### Elasticsearch won't start

```bash
# Check pod events
kubectl describe pod -n logging elasticsearch-0

# Common issue: vm.max_map_count too low
# The initContainer should fix this, but if it fails:
# On each node, run:
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
```

### Vector permission errors

```bash
# Vector needs to read /var/log and /var/lib
# Check the DaemonSet has proper volume mounts
kubectl describe daemonset -n logging vector

# Verify on a node:
sudo ls -la /var/log/containers/
```

### Kibana shows logs from some namespaces but not others

**Symptom:** Kibana displays logs from the `logging` namespace but not from `default`, `kube-system`, or other namespaces.

**Root Cause:** Logs are missing the `@timestamp` field that Kibana uses for time-based filtering.

**Diagnosis:**
```bash
# Check if logs have @timestamp field
kubectl exec -n logging elasticsearch-0 -- curl -s "http://localhost:9200/logs-$(date +%Y.%m.%d)/_search?size=1&q=kubernetes.pod_namespace:default" | grep -o '"@timestamp"'

# If no output, logs are missing @timestamp
```

**Solution:** The current Vector configuration (lines 241-251 in `vector-efk-complete.yaml`) handles this correctly by:
1. Copying `timestamp` → `@timestamp` if needed
2. Creating `@timestamp` if neither field exists

If you modified the Vector config and broke this, ensure the `parse_logs` transform includes:
```toml
# Ensure @timestamp exists (Elasticsearch standard)
if exists(.timestamp) && !exists(."@timestamp") {
  ts = .timestamp
  . = set!(., ["@timestamp"], ts)
}
if !exists(."@timestamp") {
  . = set!(., ["@timestamp"], now())
}
```

After fixing, restart Vector:
```bash
kubectl rollout restart daemonset/vector -n logging
```

**Prevention:** Always use `@timestamp` as the time field in Kibana data views (this is the default).

## Uninstall

```bash
kubectl delete -f vector-efk-complete.yaml

# If you need to remove PVCs too:
kubectl delete pvc -n logging --all
```

## Compare to Previous Failed Attempts

| Aspect | Fluentd/Fluent-bit (Failed) | Vector (This Solution) |
|--------|----------------------------|------------------------|
| Configuration | Per-app parsers required | Zero per-app config |
| Log capture | Only matched formats | ALL container logs |
| Kubernetes metadata | Manual configuration | Automatic enrichment |
| JSON parsing | Hardcoded parser rules | Intelligent auto-detect |
| Reliability | Single buffer | Disk-backed buffer |
| Performance | High memory usage | Low memory footprint |

## Next Steps

1. Deploy this stack
2. Verify logs appear in Kibana
3. Create Kibana dashboards for your specific needs
4. Set up Index Lifecycle Management (ILM) for log rotation
5. Consider adding alerting via ElastAlert or Watcher

## References

- [Vector Kubernetes Integration](https://vector.dev/docs/reference/configuration/sources/kubernetes_logs/)
- [Elasticsearch on Kubernetes](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html)
- [Kibana Guide](https://www.elastic.co/guide/en/kibana/current/index.html)
