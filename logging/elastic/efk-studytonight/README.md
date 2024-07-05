# EFK Stack Setup (Elasticsearch, Fluent-bit and Kibana) for Kubernetes Log Management

@ [__`efk-studytonight`__](https://www.studytonight.com/post/efk-stack-setup-elasticsearch-fluentbit-and-kibana-for-kubernetes-log-management)

## TL;DR 

Success! Logs are being aggregated by the EFK stack.

## Install | [`efk.sh`](efk.sh)

```bash
kubectl apply -f ns.yaml
```
- [`ns.yaml`](ns.yaml) 

__Elasticsearch__ (Backend)

```bash
kubectl apply -f elasticsearch.yaml
```
- Configured [`elasticsearch.yaml`](elasticsearch.yaml) 
  to __StorageClass `nfs-client`__

```bash
☩ k get pod,pvc,pv
NAME               READY   STATUS    RESTARTS   AGE
pod/es-cluster-0   1/1     Running   0          11m
pod/es-cluster-1   1/1     Running   0          11m
pod/es-cluster-2   1/1     Running   0          10m

NAME                                      STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-es-cluster-0   Bound    pvc-2f133792-d90d-41b8-ac4b-77c84fa88a2c   10Gi       RWO            nfs-client     <unset>                 11m
persistentvolumeclaim/data-es-cluster-1   Bound    pvc-e89ae45a-17ac-4b64-93e7-1b8205764811   10Gi       RWO            nfs-client     <unset>                 11m
persistentvolumeclaim/data-es-cluster-2   Bound    pvc-5bd9a714-9314-47af-8296-cf250640d41e   10Gi       RWO            nfs-client     <unset>                 10m

NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                            STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/pvc-2f133792-d90d-41b8-ac4b-77c84fa88a2c   10Gi       RWO            Delete           Bound    kube-logging/data-es-cluster-0   nfs-client     <unset>                          11m
persistentvolume/pvc-5bd9a714-9314-47af-8296-cf250640d41e   10Gi       RWO            Delete           Bound    kube-logging/data-es-cluster-2   nfs-client     <unset>                          10m
persistentvolume/pvc-e89ae45a-17ac-4b64-93e7-1b8205764811   10Gi       RWO            Delete           Bound    kube-logging/data-es-cluster-1   nfs-client     <unset>                          11m

☩ k get svc
NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
elasticsearch   ClusterIP   None            <none>        9200/TCP,9300/TCP   31m

☩ k get sts -o wide
NAME         READY   AGE   CONTAINERS      IMAGES
es-cluster   3/3     32m   elasticsearch   docker.elastic.co/elasticsearch/elasticsearch:7.2.0
```

__Kibana__ (Frontend)

```bash
☩ k apply -f kibana.yaml
service/kibana created
deployment.apps/kibana created

☩ k get pod # After a few minutes
NAME                      READY   STATUS    RESTARTS   AGE
es-cluster-0              1/1     Running   0          13m
es-cluster-1              1/1     Running   0          13m
es-cluster-2              1/1     Running   0          12m
kibana-85fd454f74-m55b6   1/1     Running   0          55s

☩ k get svc -o wide
NAME            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE   SELECTOR
elasticsearch   ClusterIP   None            <none>        9200/TCP,9300/TCP   34m   app=elasticsearch
kibana          ClusterIP   10.108.83.192   <none>        5601/TCP            21m   app=kibana
```
- [`kibana.yaml`](kibana.yaml) 

__Fluent Bit__ (Collector) | [Guide](https://www.studytonight.com/post/what-is-fluent-bit-fluent-bit-beginners-guide) | [Input Plugins](https://docs.fluentbit.io/manual/pipeline/inputs)

```bash
☩ k apply -f fluent-bit.yaml
serviceaccount/fluent-bit created
clusterrole.rbac.authorization.k8s.io/fluent-bit created
clusterrolebinding.rbac.authorization.k8s.io/fluent-bit created
configmap/fluent-bit created
daemonset.apps/fluent-bit created

☩ k get pod
NAME                      READY   STATUS    RESTARTS   AGE
es-cluster-0              1/1     Running   0          16m
es-cluster-1              1/1     Running   0          15m
es-cluster-2              1/1     Running   0          14m
fluent-bit-489dk          1/1     Running   0          7s
fluent-bit-5kbhb          1/1     Running   0          7s
fluent-bit-wfcxx          1/1     Running   0          7s
kibana-85fd454f74-m55b6   1/1     Running   0          3m32s

```


## Access

```bash
☩ kubectl port-forward $(kubectl get pod -l app=kibana --no-headers |cut -d' ' -f1) 5601:5601 &
[1] 36064
☩ Forwarding from 127.0.0.1:5601 -> 5601
Forwarding from [::1]:5601 -> 5601

☩ curl -I http://localhost:5601/app/kibana
Handling connection for 5601
HTTP/1.1 200 OK
...
```

[Debug Kibana's ubiquitous "No Elasticsearch indices match your pattern." issue.](https://chat.deepseek.com/a/chat/s/a9be45c7-1ad1-4061-8b1e-5201ca63167b) at "__Step 1.__"

__Expose__ the Elasticsearch (backend) service sans Ingress:

```bash
☩ kubectl port-forward svc/elasticsearch 9200:9200 &
[2] 36219
☩ Forwarding from 127.0.0.1:9200 -> 9200
Forwarding from [::1]:9200 -> 9200
```

Show response to __Elasticsearch indices output__ endpoint : __`/_cat/indices?v`__ 
to __verify new logs are arriving__:

```bash
☩ curl http://localhost:9200/_cat/indices?v
Handling connection for 9200
health status index                uuid                   pri rep docs.count docs.deleted store.size pri.store.size
green  open   .kibana_1            4ABIjZ9aRXmY2fp-x6LuyQ   1   1          4            0     30.9kb         15.4kb
green  open   .kibana_task_manager 3SOJtT_9TSmMjrvEiIljeg   1   1          2            0       83kb         45.6kb
green  open   logstash-2025.04.06  HlfPmMdmQmeCsk3v8W_rEw   1   1     159715            0    154.1mb         78.3mb
```
- Two Kibana system indices (`.kibana_1` and `.kibana_task_manager`), AKA "internals"
- One log index: `logstash-2025.04.06`
    - This is __the actual log-data index__.

So, at [Kibana's (Stack) Management / Index patterns page](http://localhost:5601/app/kibana#/management/kibana/index_pattern), 
under "Create index pattern", 
enter the pattern: __logstash-*__. 

__Kibana reports__:

"
__Success!__ Your index pattern matches 1 index.  
`logstash-2025.04.06`
"

Note that our Fluent Bit configuration (`ConfigMap` @ `fluent-bit.yaml`) 
is using __Logstash-style indexing__ (`Logstash_Format On`), 

```yaml
output-elasticsearch.conf: |
[OUTPUT]
    Name            es
    Match           *
    Host            ${FLUENT_ELASTICSEARCH_HOST}
    Port            ${FLUENT_ELASTICSEARCH_PORT}
    Logstash_Format On
```

which creates daily indices with the `logstash-YYYY.MM.DD` pattern, 
so the __wildcard pattern__ (`logstash-*`) __matches all daily indices__.



Moving on to "Next", select `@timestamp` filter to create/filter the index of our pattern.

Response page, http://localhost:5601/app/kibana#/management/kibana/index_patterns/1304d290-132b-11f0-aeb4-1730d808ada5?_g=()&_a=(tab:indexedFields),
lists logs

...

kubernetes.annotations.cni_projectcalico_org/podIPs

kubernetes.annotations.cni_projectcalico_org/podIPs.keyword

kubernetes.annotations.hash_operator_tigera_io/cni-config

kubernetes.annotations.hash_operator_tigera_io/cni-config.keyword

kubernetes.annotations.hash_operator_tigera_io/system

kubernetes.annotations.hash_operator_tigera_io/system.keyword

kubernetes.annotations.kubeadm_kubernetes_io/etcd_advertise-client-urls

kubernetes.annotations.kubeadm_kubernetes_io/etcd_advertise-client-urls.keyword

kubernetes.annotations.kubeadm_kubernetes_io/kube-apiserver_advertise-address_endpoint

kubernetes.annotations.kubeadm_kubernetes_io/kube-apiserver_advertise-address_endpoint.keyword

See logs @ __Discover__ tab : http://localhost:5601/app/kibana#/discover?_g=()&_a=(columns:!(_source),index:'1304d290-132b-11f0-aeb4-1730d808ada5',interval:auto,query:(language:kuery,query:''),sort:!('@timestamp',desc))

