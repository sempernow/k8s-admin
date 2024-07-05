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
