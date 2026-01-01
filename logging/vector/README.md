# EVK : **E**lasticsearch/OpenSearch + **V**ector + **K**ibana

## Vector Overview 

[Vector.dev](https://vector.dev/) is a powerful, flexible __observability data pipeline__ tool. It excels at collecting (sources), transforming/processing (transforms), and routing (sinks) logs, metrics, and even traces. 
It provided neither storage, indexing, nor querying/visualization components; __provides neither frontend nor backend__.

### Evolution of the Logging Stack

- **Old-school ELK** → Elasticsearch (storage + search) + Logstash (processing) + Kibana (UI)
- **Common EFK** (especially in Kubernetes) → Elasticsearch + Fluentd/Fluent Bit + Kibana
- **EVK** (very popular since ~2020–2025) → **E**lasticsearch / OpenSearch + **V**ector + **K**ibana

In the **EVK** stack, Vector typically replaces Logstash (or Fluentd/Fluent Bit) as the collector/processor/shipper because it's:

- Much lighter on resources (often 5–10× less memory/CPU than Logstash)
- Faster parsing and transformation
- More reliable with better error handling and backpressure
- Written in Rust (memory-safe, no GC pauses)
- Unified for logs + metrics (and traces via OTLP)

But both **backend** (storage + search) and **frontend** (visualization) are still Elastic-family products:

- **Elasticsearch** (or its open fork **OpenSearch**) for indexing/storage/search
- **Kibana** (or **OpenSearch Dashboards**) for the UI

Vector has a built-in `elasticsearch` **sink** that is 
fully compatible with **OpenSearch** as well 
(just point it at your OpenSearch endpoints, and it works out of the box in most cases).

So **EVK** is effectively still tied to Elastic's ecosystem (or its fork) for the heavy lifting on storage and search.
Vector just modernizes and lightens the ingestion/processing layer.

### Fully Open Alternatives to Break the Elastic Dependency

If the goal is to reduce vendor lock-in or avoid Elastic/OpenSearch licensing concerns, resource costs, or high-cardinality issues, here are the most common modern stacks using **Vector** as the collector/processor:

1. **Vector + Grafana Loki + Grafana**  
   → Very popular in Kubernetes/Cloud Native environments  
   → Loki is index-metadata-only (cheap storage, great for logs), queries are fast for known labels  
   → Vector → Loki sink is straightforward and efficient  
   → Visualization in Grafana (LogQL queries) — same UI as Prometheus metrics

2. **Vector + ClickHouse** (or tools built on it like SigNoz, VictoriaLogs)  
   → Excellent for high-volume logs + analytics/aggregations  
   → Columnar storage → much cheaper & faster for trends/counts than Elasticsearch  
   → Vector has direct sinks or you can use generic HTTP/OTLP  
   → Great for large-scale (companies like Uber/Cloudflare moved logs to ClickHouse)

3. **Vector + Other backends** (examples from Vector's 50+ sinks):  
   - **Grafana Mimir** / Prometheus (more for metrics, but can handle structured logs)  
   - **Axiom**, **Honeycomb**, **Quickwit**, **S3** (for cheap long-term + Athena/others for query)  
   - **VictoriaLogs** (very efficient alternative to Loki/Elasticsearch for logs)

In 2025–2026, the trend is clearly moving away from full-content indexing (like classic Elasticsearch) toward **metadata/label-based** (Loki-style) or **columnar/analytical** (ClickHouse-style) approaches for logs, precisely because they scale better and cost less.

If you're building this stack right now, **EVK** is still a solid, battle-tested choice (especially with OpenSearch for staying fully open source), but **Vector + Loki/Grafana** or **Vector + ClickHouse-based solution** gives you more independence from Elastic's orbit while keeping excellent performance.


## Deploy

**Status: WORKING - Captures ALL application logs with zero per-app configuration**

```bash
make vector-install    # Deploy the complete stack
make vector-status     # Check status
make vector-logs       # View collector logs
```

See **[DEPLOY-VECTOR.md](DEPLOY-VECTOR.md)** for complete deployment guide.

### Why This Works (When Fluentd/Fluent-bit Failed)

**Problem with Fluentd/Fluent-bit:**
- Require hardcoded per-application log parsers (nginx, apache, etc.)
- Only capture logs matching specific parser regex patterns
- Miss all application logs that don't match configured parsers
- This is why only Kubernetes core pod logs were visible

**Vector Solution:**
- Zero per-application configuration required
- Automatically captures ALL container logs regardless of format
- Intelligent JSON parsing with fallback to plain text
- Automatic Kubernetes metadata enrichment
- No hardcoded parsers needed

**Files:**
- `evk-complete.yaml` - Complete working stack (ES + Vector + Kibana)
- `DEPLOY-VECTOR.md` - Deployment guide and troubleshooting

---

## Alternative Stacks : In-depth


Here are the most practical **EVK-style or modern alternatives** ranked for your specific scenario in early 2026:

### 1. Recommended: **Vector + Grafana Loki + Grafana** (LGTM stack with Vector instead of Alloy/Promtail)
This is currently the **most popular and battle-tested** choice for Kubernetes-centric, on-prem environments at your scale.

**Why it fits best here**:
- Extremely **low resource usage** → Loki indexes only labels (metadata), not full text → cheap storage and RAM (often 5-10× less than OpenSearch/Elasticsearch for similar retention).
- HA is straightforward: Deploy Loki in **distributed mode** (multiple ingesters + queriers + a compactor) with replication factor 2-3 across your 5 nodes. Use object storage (MinIO on-prem, or NFS/S3-compatible) for chunks/index — very reliable and scales with your cluster.
- Vector → Loki sink is native, efficient, and battle-tested.
- Visualization in **Grafana** (LogQL queries feel like PromQL → easy if you're already using Prometheus/Grafana for metrics).
- Great for Kubernetes logs: Pod labels become stream selectors → perfect for filtering by namespace, deployment, pod, container.
- Community feedback (2025-2026) shows many on-prem K8s teams running this successfully on similar small HA clusters (e.g., RKE2/Talos + Azure Blob/NFS equivalents).

**Potential downsides**:
- Full-text search is **label-first** → if you need very fast arbitrary keyword search without good label discipline (e.g., no trace_id/user_id as labels), it can require broader scans and feel slower than classic Elasticsearch.
- High-cardinality labels (e.g., every request ID) can explode memory — enforce good label hygiene (limit to ~10-15 per stream).

**Deployment tips**:
- Use Grafana's official Loki Helm chart → enable microservices mode for HA.
- Retention: Start with 7-30 days (easy to tune).
- Resources: 1-2 CPU / 2-4GB RAM per Loki component (scale up if needed); Vector DaemonSet ~100-300MB RAM per node.

### 2. Solid & Familiar Alternative: **Vector + OpenSearch + OpenSearch Dashboards** (true EVK, fully open)
If your team already knows Kibana/Elasticsearch syntax or you need strong **full-text search** (relevance ranking, complex analyzers, SIEM-like use cases), stick close to the classic model.

**Pros**:
- Excellent for **ad-hoc text search** across everything — no label restrictions.
- Vector has direct Elasticsearch sink (fully compatible with OpenSearch).
- HA via OpenSearch cluster (3+ master-eligible + data nodes) — fits your 5 nodes (co-locate with workloads carefully).
- Dashboards are Kibana-like → familiar.

**Cons**:
- Higher resource usage (JVM heap, indexing overhead) → expect 4-8GB+ RAM per data node even at moderate scale.
- More operational work (sharding, ILM policies, rebalancing).
- Storage grows faster than Loki for raw logs.

**When to choose**:
- You have compliance/auditing needs requiring perfect full-text recall.
- Developers demand "grep-like" search without label constraints.

### 3. Emerging Strong Contender: **Vector + VictoriaLogs + Grafana**
VictoriaLogs (from VictoriaMetrics team) is gaining serious traction in 2025-2026 as a **Loki killer** for on-prem.

**Key advantages** (from benchmarks & user reports):
- Supports **high-cardinality fields** out-of-the-box (user_id, trace_id, IP — no explosions).
- Much lower resource usage than Loki/OpenSearch (up to 10-30× less RAM/disk in some workloads).
- Fast full-text search over all fields (not just labels).
- Single binary, easy to HA (clustering available).
- Grafana datasource plugin exists → Log browser + dashboards work well.
- Vector can send via Loki protocol or HTTP sink (compatible).

**Current status**:
- Very positive user reports for replacing Loki in K8s (faster queries, less resources, better compression).
- Helm chart available.
- Great if you want Loki-like simplicity but without cardinality pain or slow regex/text scans.

**Trade-off**:
- Smaller community than Loki (but growing fast).
- Query language (LogsQL) is different but intuitive.

### Quick Comparison Table (for your scale)

| Stack                        | Resource Efficiency | Full-Text Search Speed/Quality | High-Cardinality Support | HA Ease in 5-node K8s | Learning Curve | Best For Your Case? |
|------------------------------|---------------------|--------------------------------|---------------------------|------------------------|----------------|---------------------|
| Vector + Loki + Grafana     | ★★★★★              | ★★★ (label-first)             | ★★ (avoid high-card)     | ★★★★                  | Low            | Yes – default pick |
| Vector + OpenSearch         | ★★                 | ★★★★★                         | ★★★★                     | ★★★                   | Medium         | If search is critical |
| Vector + VictoriaLogs       | ★★★★★+             | ★★★★                          | ★★★★★                    | ★★★★                  | Low-Medium     | Yes – strong #2 pick |
| Vector + ClickHouse (SigNoz)| ★★★★               | ★★★★ (SQL)                    | ★★★★                     | ★★★                   | Medium-High    | If heavy analytics needed |

**My recommendation for your setup** → Start with **Vector + Loki + Grafana** in HA mode. It's the safest, most Kubernetes-native path with the lowest ops overhead and best community support at this scale. If you hit cardinality issues or want faster/better text search, evaluate **VictoriaLogs** next (it's the rising star for exactly these on-prem K8s use cases).

If your logs are extremely structured + analytical (e.g., lots of aggregations/counts over time), consider SigNoz (ClickHouse-based) as a unified observability solution.

Let me know your current metrics stack (Prometheus? Mimir?), expected retention, or if you have any must-have features (e.g. perfect full-text, SQL queries, trace correlation) — I can refine this further!

