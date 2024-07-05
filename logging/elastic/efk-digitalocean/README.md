# [How To Set Up EFK Logging Stack on Kubernetes](https://www.digitalocean.com/community/tutorials/how-to-set-up-an-elasticsearch-fluentd-and-kibana-efk-logging-stack-on-kubernetes "DigitalOcean.com")

- __E__ lasticsearch
- __F__ luentd
- __K__ ibana

### Q:

I am stuck in the __end part of Step 4__.  
I try to create index pattern in __Kibana__ ...  
no place to add "`logstash-*`" and I cannot proceed to next step.

Then I tried including system indices.  
Then __`logstash-*` was not recognized as an index pattern__.

### A:

Mod `fluentd.yaml`

```yaml
...
containers:
- name: fluentd
  image: fluent/fluentd-kubernetes-daemonset:v1.11.5-debian-elasticsearch7-1.1
  env:
    - name:  FLUENT_ELASTICSEARCH_HOST
      value: "10.0.2.15"
    - name:  FLUENT_ELASTICSEARCH_PORT
      value: "9200"
    - name: FLUENT_ELASTICSEARCH_SCHEME
      value: "http"
    - name: FLUENTD_SYSTEMD_CONF
      value: disable
    - name: FLUENT_CONTAINER_TAIL_EXCLUDE_PATH
      value: /var/log/containers/fluent*
    - name: FLUENT_CONTAINER_TAIL_PARSER_TYPE
      value: /^(?<time>.+) (?<stream>stdout|stderr)( (?<logtag>.))? (?<log>.*)$/
  resources:
    limits:
      memory: 1024Mi
    requests:
      cpu: 100m
      memory: 200Mi
...
```