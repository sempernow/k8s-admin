# EFK Stack

- __E__ lasticsearch
- __F__ luentd
- __K__ ibana

Log aggregation in Kubernetes via EFK can be a fragile mess. 

So, weeks of failed "EFK" stacks, requiring fantastically brittle and tedious `ConfigMap` settings, none of which provided the basic structured fields expected of any such log aggregation stack. 


---

### ❌ **EFK (or ELK) on Kubernetes** — *Infamous for pain*

**Problems you probably hit:**

* **Fluentd/Fluent Bit config hell**: Hard to get useful parsing out of container logs, especially with multiline logs or JSON-in-logs.
* **Elasticsearch eats RAM**: Needs persistent volume tuning, memory limits, JVM heap, etc.
* **Kibana is brittle**: UI loads but data often missing due to wrong index patterns or timestamp mappings.
* **Poor out-of-the-box value**: Unlike Prometheus, there’s no "log dashboard" that just works. You must design every filter/query from scratch.

---

### A More Reasonable Observability Stack:

If you want a **working Kubernetes observability setup**:

* **Metrics**: Use `kube-prometheus-stack` Helm chart. It just works.
* **Logs**: Consider **Grafana Loki + Fluent Bit** as a lighter alternative to EFK. Loki indexes *labels only* (not full log content), so it’s cheaper and easier to run.
* **Tracing**: Add `Tempo` or `Jaeger` if you need distributed tracing.
* **Visualization**: Grafana can aggregate metrics (Prometheus), logs (Loki), and traces (Tempo) in a single view.

---

### Summary:

* **Prometheus/Grafana** is *solid* in Kubernetes.
* **EFK** is *fragile*, especially on small/air-gapped clusters.
* **Loki** + **Fluent Bit** is the pragmatic log solution today, especially when used alongside Prometheus.

---

# Elastic/Kibana


1. Browse to __Kibana__ ("elastic" name/logo)
    - http://192.168.11.101:30001/app/home
        - `NODE_IP:KIBANA_SVC_NODEPORT`
1. Select __Management > Stack Management > Kibana > Index Patterns__
    - Create Index Pattern: `logstach-*`
1. Select __Analytics > Discover__
    - See logs
    - http://192.168.11.101:30001/app/discover


## `efk-chatgpt`

### http://192.168.11.101:30001/app/discover

KCL : Kibana Query Language

Select `log` and `kubernetes.container_name` from "__Available fields__" using the "+" button, which moves them to  "__Selected fields__"
```ini
kubernetes.container_name: "my-api" AND log: "*404*"
```

Not seeing any of the useful fields, only those above.

ChatGPT says logs are unstructured because Fluent-bit parser needs work,
so saved original/running version (`04-fluentbit.v0.0.0.yaml`),
and modified and deployed newer version (`04-fluentbit.yaml`).

Deleted pods to ingest the new configmap, yet the mods had no change whatsoever.

ChatGPT says:

__Most likely causes__:

1. The log field is not named log after merging.
This breaks your merge_parser logic — Fluent Bit may be trying to parse the wrong key.
1. The embedded JSON is malformed or truncated.
We saw that earlier log lines were cut off at the end — this could cause parsing to fail silently.
1. The parser isn’t being invoked at all.
Because Fluent Bit's merge_parser only runs when Merge_Log succeeds — if the merged field is missing or the wrong key is specified, nothing happens.
