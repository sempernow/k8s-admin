# [`efk-chatgpt`](https://chatgpt.com/share/680e77c5-7d68-8009-b6a4-f66d608c8714 "ChatGPT")

## TL;DR

Vendor's images and manifest deploy *straight out of the box*, 
yet fluentbit default ConfigMap is useless. 

1. Install by manifests 
    - [`stack.sh`](stack.sh):
2. Browse to __Kibana__ ("elastic" name/logo) 
    - http://192.168.11.101:30001/app/home
        - `NODE_IP:KIBANA_SVC_NODEPORT`
3. Select __Management > Stack Management > Kibana > Index Patterns__
    - Create Index Pattern: `logstach-*`
4. Select __Analytics > Discover__
    - See logs
    - http://192.168.11.101:30001/app/discover

Attempting HA ([`02-es-cluster.yaml`](02-es-cluster.yaml)) hits vendor lockout issues. 
Hence the attempted migration to OSS (bitnami) images (below).

## Prefer OSS v. Elastic Inc.

- Upgraded images to OSS and newer.  
    - Issues at Web UI
- Kibana web UI up
    - http://192.168.11.101:30001/

```bash
☩ curl -IX GET http://192.168.11.101:30001/app/home
HTTP/1.1 200 OK
...
```

@ `Ubuntu (master) ... /s/DEV/devops/infra/kubernetes/k8s-vanilla-ha-rhel9`

```bash
☩ kubectl port-forward svc/elasticsearch 9200:9200 &
[1] 209729

☩ curl -sXGET 'http://localhost:9200/_cat/indices?v' |grep logstash
Handling connection for 9200
yellow open   logstash-2025.04.28              DB_8_gDdQaynKIcYNG-OZg   1   1       1085            0      1.3mb          1.3mb
```

```bash
☩ k get $all
NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/kibana   1/1     1            1           126m

NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/fluent-bit   3         3         3       3            3           <none>          100m

NAME                             READY   AGE
statefulset.apps/elasticsearch   1/1     126m

NAME                          READY   STATUS    RESTARTS   AGE
pod/elasticsearch-0           1/1     Running   0          126m
pod/fluent-bit-gkn6l          1/1     Running   0          100m
pod/fluent-bit-qjtkz          1/1     Running   0          100m
pod/fluent-bit-vgnsq          1/1     Running   0          100m
pod/kibana-5ffdb4fd86-5vzh8   1/1     Running   0          126m

NAME                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
service/elasticsearch   ClusterIP   None             <none>        9200/TCP         126m
service/kibana          NodePort    10.107.225.222   <none>        5601:30001/TCP   126m

NAME                      ENDPOINTS             AGE
endpoints/elasticsearch   10.244.141.136:9200   126m
endpoints/kibana          10.244.65.70:5601     126m

NAME                          DATA   AGE
configmap/fluent-bit-config   2      100m
configmap/kube-root-ca.crt    1      126m
```

__Due to licensing issues__ on upgrade to 3-node Elasticsearch cluster (fork of that at `efk-tonight` folder using our NFS as its backing store), changed to __Bitnami__ images.

```bash
☩ k get $all
NAME                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/kibana   1/1     1            1           6m16s

NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/fluent-bit   3         3         3       3            3           <none>          168m

NAME                          READY   AGE
statefulset.apps/es-cluster   3/3     30m

NAME                          READY   STATUS    RESTARTS   AGE
pod/es-cluster-0              1/1     Running   0          30m
pod/es-cluster-1              1/1     Running   0          29m
pod/es-cluster-2              1/1     Running   0          29m
pod/fluent-bit-gkn6l          1/1     Running   0          168m
pod/fluent-bit-qjtkz          1/1     Running   0          168m
pod/fluent-bit-vgnsq          1/1     Running   0          168m
pod/kibana-6965c5b7b5-45msp   1/1     Running   0          6m16s

NAME                    TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)             AGE
service/elasticsearch   ClusterIP   None            <none>        9200/TCP,9300/TCP   30m
service/kibana          NodePort    10.101.49.144   <none>        5601:30001/TCP      6m16s

NAME                      ENDPOINTS                                                              AGE
endpoints/elasticsearch   10.244.141.142:9200,10.244.65.77:9200,10.244.78.211:9200 + 3 more...   30m
endpoints/kibana          10.244.141.143:5601                                                    6m16s

NAME                          DATA   AGE
configmap/fluent-bit-config   2      168m
configmap/kube-root-ca.crt    1      3h13m

NAME                                      STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
persistentvolumeclaim/data-es-cluster-0   Bound    pvc-1f921279-46b5-451a-ab66-c61dc3a5bb18   10Gi       RWO            nfs-client     <unset>                 55m
persistentvolumeclaim/data-es-cluster-1   Bound    pvc-24343622-769a-4f94-8716-ee8a1a4acc1d   10Gi       RWO            nfs-client     <unset>                 52m
persistentvolumeclaim/data-es-cluster-2   Bound    pvc-10c40667-3a18-4a2d-bfbf-aec57e395ee1   10Gi       RWO            nfs-client     <unset>                 52m

NAME                                                        CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                            STORAGECLASS   VOLUMEATTRIBUTESCLASS   REASON   AGE
persistentvolume/pvc-10c40667-3a18-4a2d-bfbf-aec57e395ee1   10Gi       RWO            Delete           Bound    kube-logging/data-es-cluster-2   nfs-client 
persistentvolume/pvc-1f921279-46b5-451a-ab66-c61dc3a5bb18   10Gi       RWO            Delete           Bound    kube-logging/data-es-cluster-0   nfs-client  
persistentvolume/pvc-24343622-769a-4f94-8716-ee8a1a4acc1d   10Gi       RWO            Delete           Bound    kube-logging/data-es-cluster-1   nfs-client

```