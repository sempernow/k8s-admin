# Cluster-level Logging Solutions

## ✅ RECOMMENDED: Vector + Elasticsearch + Kibana

See __`./evk`__

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
- `vector-efk-complete.yaml` - Complete working stack (Vector + ES + Kibana)
- `DEPLOY-VECTOR.md` - Deployment guide and troubleshooting

---

## Logging Architecture Overview

Kubernetes stores container logs on the node's local filesystem:

    [Pods] -> [Node Filesystem]

Log collectors read from node filesystem and forward to storage backends:

    [Pods] -> [Log Collector] -> [Elasticsearch/S3/… ]
    [Pods] -> [Log Collector] -> [Kafka]
    [Pods] -> [Log Collector] -> [Kafka] -> [KafkaConnector] -> [Elasticsearch/S3/… ]

---

## Alternative Solutions (For Reference)

### ELK/EFK ❌ (Failed - Per-app Config Required)

Mature stack built of Elasticsearch (backend) and Kibana (frontend).
Fluent-bit is the preferred lightweight collector.

**Issue:** Requires tedious per-application parser configurations.
See `elastic/` directory for failed attempts.

### Loki

Simplified solution, but lacks full search/query capabilities.

### Vector.dev ✅ | [GitHub](https://github.com/vectordotdev/vector) | [Docs](https://vector.dev/docs/)

Highly performant DataDog product written in Rust.
Provides log collection, transform and route, sans Fluent* tedium of per-app configurations.

**This is the implemented solution - see DEPLOY-VECTOR.md**

### [OpenTelemetry](https://opentelemetry.io/docs/)

Slightly more resource intensive than fluent-bit,
but provides __unified logging, metrics and tracing__ solution.

---

## Quick Start

```bash
# Deploy Vector logging stack
make vector-install

# Access Kibana at http://NODE_IP:30561
# Initial setup instructions in DEPLOY-VECTOR.md
```
