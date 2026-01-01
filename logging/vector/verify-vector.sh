#!/bin/bash
# Verify Vector logging stack is working

set -e

echo "============================================="
echo "Vector Logging Stack Verification"
echo "============================================="
echo ""

echo "=== 1. Vector Pods Status ==="
kubectl get pods -n logging -l app=vector -o wide
echo ""

echo "=== 2. Elasticsearch Status ==="
kubectl get pods -n logging -l app=elasticsearch
echo ""

echo "=== 3. Kibana Status ==="
kubectl get pods -n logging -l app=kibana
echo ""

echo "=== 4. All Logging Services ==="
kubectl get svc -n logging
echo ""

echo "=== 5. Checking Vector Logs (last 20 lines) ==="
kubectl logs -n logging daemonset/vector --tail=20
echo ""

echo "=== 6. Waiting 30 seconds for logs to flow to Elasticsearch... ==="
sleep 30

echo "=== 7. Elasticsearch Cluster Health ==="
kubectl exec -n logging elasticsearch-0 -- curl -s 'http://localhost:9200/_cluster/health?pretty' 2>/dev/null
echo ""

echo "=== 8. Elasticsearch Indices ==="
kubectl exec -n logging elasticsearch-0 -- curl -s 'http://localhost:9200/_cat/indices?v' 2>/dev/null
echo ""

echo "=== 9. Count of Documents in Today's Index ==="
TODAY=$(date +%Y.%m.%d)
kubectl exec -n logging elasticsearch-0 -- curl -s "http://localhost:9200/logs-${TODAY}/_count?pretty" 2>/dev/null || echo "Index logs-${TODAY} not created yet"
echo ""

echo "=== 10. Sample Log Entries ==="
kubectl exec -n logging elasticsearch-0 -- curl -s "http://localhost:9200/logs-${TODAY}/_search?size=3&pretty" 2>/dev/null | head -100 || echo "No logs yet"
echo ""

echo "=== 11. Verify @timestamp Field Coverage ==="
echo "Checking that logs have @timestamp for Kibana compatibility..."
kubectl exec -n logging elasticsearch-0 -- curl -s "http://localhost:9200/logs-${TODAY}/_search?size=1&sort=timestamp:desc" 2>/dev/null | grep -q '"@timestamp"' && echo "✓ Recent logs have @timestamp field" || echo "⚠ WARNING: Logs missing @timestamp - Kibana filtering may not work"
echo ""

echo "============================================="
echo "Verification Complete!"
echo "============================================="
echo ""
echo "Kibana Access:"
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
echo "  http://${NODE_IP}:30561"
echo "  http://a1.lime.lan:30561"
echo "  http://a2.lime.lan:30561"
echo "  http://a3.lime.lan:30561"
echo ""
echo "Next Steps:"
echo "  1. Open Kibana in browser"
echo "  2. Create index pattern: logs-*"
echo "  3. Select @timestamp as time field"
echo "  4. View logs in Discover tab"
echo ""
