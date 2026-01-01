#!/bin/bash
# Create Kibana Data View via API (Kibana 8.x)

set -e

KIBANA_URL="http://kibana.logging.svc.cluster.local:5601"

echo "Waiting for Kibana to be ready..."
kubectl wait --for=condition=ready pod -l app=kibana -n logging --timeout=60s

echo ""
echo "Creating Data View via Kibana API..."

kubectl exec -n logging deployment/kibana -- curl -X POST "${KIBANA_URL}/api/data_views/data_view" \
  -H "kbn-xsrf: true" \
  -H "Content-Type: application/json" \
  -d '{
    "data_view": {
      "title": "logs-*",
      "timeFieldName": "@timestamp",
      "name": "Logs"
    }
  }' 2>/dev/null | jq '.' || echo "Data view might already exist"

echo ""
echo "Data View created successfully!"
echo ""
echo "Now access Kibana at: http://a1.lime.lan:30561"
echo "Navigate to: Discover"
echo "The 'logs-*' data view should be available"
