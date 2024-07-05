# [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack#kube-prometheus-stack) (KPS) : Minimal configuration

## Q:

Regarding the KPS chart, what changes to the default `values.yaml` would provision 
a minimal configuration that provides dynamic scraping 
of apps into the basic prometheus/grafana app?

## A:

To set up a **minimal `values.yaml` for kube-prometheus-stack** that:

* Installs Prometheus and Grafana
* Scrapes your own dynamic application pods using ServiceMonitors
* Avoids extras like Thanos, etc.

…you only need a few essential settings beyond the defaults.

---

## ✅ Minimal `values.yaml` changes

```yaml
# Minimal values.yaml for kube-prometheus-stack
# to scrape your own apps via ServiceMonitor and show in Grafana

# Skip extras
alertmanager:
  enabled: false

prometheusOperator:
  enabled: true

grafana:
  enabled: true
  defaultDashboardsEnabled: true
  sidecar:
    dashboards:
      enabled: true
    datasources:
      enabled: true

prometheus:
  enabled: true
  prometheusSpec:
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    ruleSelectorNilUsesHelmValues: false
    # Scrape configs will be driven by ServiceMonitors you create
```

This:

* Disables Alertmanager
* Enables only Prometheus, Prometheus Operator, and Grafana
* Ensures your `ServiceMonitors` will be picked up by Prometheus
* Keeps the Prometheus CRD's `.spec.serviceMonitorSelector` unset so it doesn't filter out your monitors
* Lets Grafana auto-discover Prometheus and dashboards

---

## 📥 Example: Add your own app's ServiceMonitor

Assume your app exposes metrics at `/metrics` on port `8080`, 
and is labeled `app=my-app` in namespace `default`.

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  namespace: default
  labels:
    release: kube-prometheus-stack  # Match the Helm release
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: http
      path: /metrics
      interval: 15s
```

Make sure the `Service` backing your app has the right port and label:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  selector:
    app: my-app
  ports:
    - name: http
      port: 8080
      targetPort: 8080
```

Prometheus will pick this up dynamically if:

* `release: kube-prometheus-stack` label matches the Helm release name
* `serviceMonitorSelectorNilUsesHelmValues` is set to `false`

---

## 🧪 Optional but helpful

You can add this label to your Helm release:

```bash
helm install kps prometheus-community/kube-prometheus-stack \
  --namespace kube-metrics \
  --create-namespace \
  -f values.yaml
```

Then all your `ServiceMonitors` just need:

```yaml
metadata:
  labels:
    release: kps
```

You can also use label selectors (`matchExpressions`) for broader matches.

---

## 🧠 TL;DR

1. Use `prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues: false` to allow **dynamic discovery** of ServiceMonitors.
2. Your apps need a `Service` and a `ServiceMonitor`.
3. Label your `ServiceMonitor` to match the Prometheus release.
4. Use minimal values.yaml to reduce overhead and get straight to metrics/Grafana.

The **minimal `values.yaml`** configuration we discussed 
**does capture the core functionality of the `kube-prometheus-stack` chart**, specifically:

### ✅ **What it provides out of the box with that config:**

| Capability                                  | Status | Notes                                                               |
| ------------------------------------------- | ------ | ------------------------------------------------------------------- |
| ✅ Prometheus installation                   | ✔️     | Via Prometheus CRD + Operator                                       |
| ✅ Prometheus Operator                       | ✔️     | Manages Prometheus, Alertmanager, rules, etc.                       |
| ✅ Grafana with Prometheus datasource        | ✔️     | Includes sidecar for dashboards + default dashboards                |
| ✅ Ability to define custom `ServiceMonitor` | ✔️     | Fully dynamic if `serviceMonitorSelectorNilUsesHelmValues: false`   |
| 🚫 Alertmanager                             | ❌      | Disabled in the minimal config                                      |
| 🚫 Thanos                                   | ❌      | Not included unless configured                                      |
| 🚫 Node exporter, kube-state-metrics        | ❌      | Not explicitly enabled (defaults vary — can be disabled explicitly) |
| 🚫 Automatic app scraping                   | ❌      | Requires manual `ServiceMonitor` or `PodMonitor`                    |

---

## 💡 Summary

This **minimal configuration gives you the essential Prometheus+Grafana observability stack** 
with dynamic service monitor discovery enabled, but:

* Keeps the system lightweight (no Alertmanager, Thanos, exporters).
* Leaves it up to **you to define what apps to monitor** via custom `ServiceMonitor` or `PodMonitor` resources.

This makes it ideal for:

* Dev/test environments
* Focused setups where you selectively expose metrics
* Clean base layer to build upon

## Images of the `kube-prometheus-stack` chart

Here’s a breakdown of what each image provides **operationally** 
in the context of the `kube-prometheus-stack` 
Helm chart or similar Prometheus/Grafana setups:

---

## 🧩 Core Monitoring Stack Components

### 1. **`docker.io/grafana/grafana:12.0.0`**

* **Purpose:** Web UI for dashboards and visualization.
* **Role:** Displays time-series metrics from Prometheus and other sources.
* **Operational Notes:**

  * Runs as a deployment.
  * Can be customized via dashboards, alerting panels, and data sources.

---

### 2. **`quay.io/prometheus-operator/prometheus-operator:v0.82.2`**

* **Purpose:** The Prometheus Operator controller.
* **Role:** Watches CRDs like `Prometheus`, `Alertmanager`, `ServiceMonitor`, etc., and reconciles them into actual Prometheus/Alertmanager StatefulSets.
* **Operational Notes:**

  * Central to managing Prometheus lifecycle.
  * Must run for CRD-based setup to work.

---

### 3. **`quay.io/prometheus/prometheus:v3.3.1`**

* **Purpose:** Prometheus server.
* **Role:** Scrapes metrics, stores time-series data, handles alert evaluations.
* **Operational Notes:**

  * Runs as a StatefulSet managed by the Prometheus Operator.
  * Sidecars like Thanos or remote storage may be attached optionally.

---

### 4. **`quay.io/prometheus/alertmanager:v0.28.1`**

* **Purpose:** Handles alerts from Prometheus.
* **Role:** Groups, deduplicates, silences, and routes alerts (e.g., to email, Slack, PagerDuty).
* **Operational Notes:**

  * Runs separately but is also managed via `Alertmanager` CR by the Operator.

---

## 📊 Metric Sources / Exporters

### 5. **`quay.io/prometheus/node-exporter:v1.9.1`**

* **Purpose:** Exposes node-level OS metrics.
* **Role:** CPU, memory, disk, and network stats of each Kubernetes node.
* **Operational Notes:**

  * Runs as a DaemonSet.
  * Essential for node health dashboards.

---

### 6. **`registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0`**

* **Purpose:** Exposes metrics about Kubernetes objects (state, not resource usage).
* **Role:** Tracks deployments, pods, node conditions, replica statuses, etc.
* **Operational Notes:**

  * Runs as a standalone deployment.
  * Emits metrics consumed by Prometheus.

---

## 🔧 Supporting Utilities

### 7. **`quay.io/kiwigrid/k8s-sidecar:1.30.0`**

* **Purpose:** Sidecar container used by Grafana for **auto-discovery** of dashboards and datasources.
* **Role:** Watches ConfigMaps or Secrets for Grafana dashboards and loads them.
* **Operational Notes:**

  * Enables dynamic injection of dashboards into Grafana.
  * Used in the Grafana pod.

---

### 8. **`registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.3`**

* **Purpose:** Generates TLS certificates for admission webhooks.
* **Role:** Used to generate and rotate certs for validating/mutating webhooks (e.g., Prometheus Operator admission controller).
* **Operational Notes:**

  * Runs as a Job or InitContainer at install/upgrade time.

---

### 9. **`docker.io/bats/bats:v1.4.1`**

* **Purpose:** [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core) framework.
* **Role:** Runs chart-related smoke tests (e.g., in CI or post-install Jobs).
* **Operational Notes:**

  * Often used in test hooks, not part of production stack.
  * Can be safely excluded unless running validation Jobs.

---

## 🧠 TL;DR

| Image                                     | Purpose                                                  |
| ----------------------------------------- | -------------------------------------------------------- |
| `grafana/grafana`                         | Visualization frontend                                   |
| `prometheus/prometheus`                   | Metrics scraping and alerting engine                     |
| `prometheus-operator/prometheus-operator` | Reconciles Prometheus/Alertmanager CRs into StatefulSets |
| `alertmanager`                            | Handles alert notifications                              |
| `node-exporter`                           | OS-level metrics from each node                          |
| `kube-state-metrics`                      | Kubernetes object state metrics                          |
| `k8s-sidecar`                             | Loads dashboards/datasources into Grafana                |
| `kube-webhook-certgen`                    | Cert generation for webhook admission                    |
| `bats/bats`                               | Chart testing tool (optional)                            |
