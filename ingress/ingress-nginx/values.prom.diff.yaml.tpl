# values.diff.yaml.tpl
#############################################################################
# This values override (diff) file template requires only those entries 
# (k-v pairs) that differ from chart's default (ingress-nginx/values.yaml).
#############################################################################
controller:
  # -- Global configuration passed to the ConfigMap consumed by the controller. Values may contain Helm templates.
  # Ref.: https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/configmap/
  config:
    use-proxy-protocol: true
    forwarded-for-header: "X-Forwarded-For"
    proxy-real-ip-cidr: "$HALB_DOMAIN_CIDR"
  # -- This configuration defines if Ingress Controller should allow users to set
  # their own *-snippet annotations, otherwise this is forbidden / dropped
  # when users add those annotations.
  # Global snippets in ConfigMap are still respected
  allowSnippetAnnotations: true
  # -- Additional command line arguments to pass to Ingress-Nginx Controller
  # E.g. to specify the default SSL certificate you can use
  extraArgs:
    default-ssl-certificate: "$INGRESS_NGINX_NAMESPACE/$DEFAULT_SSL_CERTIFICATE"
  # -- Use a `DaemonSet` or `Deployment`
  kind: DaemonSet # ds for 3-node cluster; want at least 2 instances and not on same node.
  podAnnotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "10254"
  service:
    # -- External traffic policy of the external controller service. Set to "Local" to preserve source IP on providers supporting it.
    # Ref: https://kubernetes.io/docs/tasks/access-application-cluster/create-external-load-balancer/#preserving-the-client-source-ip
    externalTrafficPolicy: "Local"
    # -- Type of the external controller service.
    # Ref: https://kubernetes.io/docs/concepts/services-networking/service/#publishing-services-service-types
    type: NodePort
    nodePorts:
      # -- Node port allocated for the external HTTP listener. If left empty, the service controller allocates one from the configured node port range.
      http: "$HALB_PORT_HTTP"
      # -- Node port allocated for the external HTTPS listener. If left empty, the service controller allocates one from the configured node port range.
      https: "$HALB_PORT_HTTPS"
  metrics:
    port: 10254
    portName: metrics
    # if this port is changed, change healthz-port: in extraArgs: accordingly
    enabled: true
    service:
      # -- Enable the metrics service or not.
      enabled: true
      type: ClusterIP     # Default; change to NodePort/LoadBalancer for external access
      servicePort: 10254  # Metrics port
    serviceMonitor:
      enabled: true
      additionalLabels:
        release: $PROMETHEUS_OPERATOR_RELEASE    # Match Prometheus Operator's selector
      namespace: $PROMETHEUS_OPERATOR_NAMESPACE  # Match Prometheus namespace

    prometheusRule:
      enabled: true # Deploys alert rules
      additionalLabels:
        release: $PROMETHEUS_OPERATOR_RELEASE  # Must match Prometheus Operator's selector
      rules:  # Customize defaults (optional)
        ## **Examples**
        - alert: NginxIngressDown
          expr: nginx_ingress_controller_nginx_process_requests_total == 0
          for: 5m
        - alert: NGINXConfigFailed
          expr: count(nginx_ingress_controller_config_last_reload_successful == 0) > 0
          for: 1s
          labels:
            severity: critical
          annotations:
            description: bad ingress config - nginx config test failed
            summary: uninstall the latest ingress changes to allow config reloads to resume
        # By default a fake self-signed certificate is generated as default and
        # it is fine if it expires. If `--default-ssl-certificate` flag is used
        # and a valid certificate passed please do not filter for `host` label!
        # (i.e. delete `{host!="_"}` so also the default SSL certificate is
        # checked for expiration)
        - alert: NGINXCertificateExpiry
          expr: (avg(nginx_ingress_controller_ssl_expire_time_seconds{host!="_"}) by (host) - time()) < 604800
          for: 1s
          labels:
            severity: critical
          annotations:
            description: ssl certificate(s) will expire in less then a week
            summary: renew expiring certificates to avoid downtime
        - alert: NGINXTooMany500s
          expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"5.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
          for: 1m
          labels:
            severity: warning
          annotations:
            description: Too many 5XXs
            summary: More than 5% of all requests returned 5XX, this requires your attention
        - alert: NGINXTooMany400s
          expr: 100 * ( sum( nginx_ingress_controller_requests{status=~"4.+"} ) / sum(nginx_ingress_controller_requests) ) > 5
          for: 1m
          labels:
            severity: warning
          annotations:
            description: Too many 4XXs
            summary: More than 5% of all requests returned 4XX, this requires your attention
