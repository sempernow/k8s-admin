# Cluster-level Logging Solutions

Kubernetes, by default, stores container logs from pods on the node's (host's) local filesystem.

    [Pods] -> [Node Filesystem] 

Kafka may be inserted into logging solution to provide transforms/filtering/… and improve reliability/scaling.

    [Pods] -> [Log Collector] -> [Elasticsearch/S3/… ]
    [Pods] -> [Log Collector] -> [Kafka]
    [Pods] -> [Log Collector] -> [Kafka] -> [KafkaConnector] -> [Elasticsearch/S3/… ]

Though shown above as `[Pod]`, log collectors like Fluentd, Vector, 
OpenTelemetry Collector (Otel), and similar tools 
typically operate by reading the log files 
directly from the node's filesystem (`[Node Filesystem]`).

---

## K8s to ES

Elasticsearch can be wired [directly to K8s pod logs](https://chat.deepseek.com/share/5gpzkuxy1zn3k1os61), sans any collector.

## ELK/EFK

Mature stack built of Elasticsearch (backend) and Kibana (frontend). 
Fluent-bit is the preferred lightweight collector.

## Loki

Simplified solution, but lacks full search/query

## Vector.dev

Highly performant DataDog product written in Rust.

Provides log collection sans the hellscape of per-app configurations required by Fluent*.

## OpenTelemetry

Slightly more resource intensive than fluent-bit, 
but provides __unified logging, metrics and tracing__ solution.

##

&hellip;