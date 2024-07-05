# [Kubernetes Dashboard](https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/) | [Setup/Debug](https://chatgpt.com/share/6769c50f-b62c-8009-bb86-46472b9251d1 "ChatGPT")

Web UI @ [http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/](http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

```bash
# Download the dashboard's manifest
curl -sSLO https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
# Create the dashboard
kubectl apply -f recommended.yaml 
# Access @ http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/
kubectl proxy 
```

Web UI has __two auth options__ : __Token__ and __kubeconfig__ (failing). 
Yet the token created of default ServiceAccount lacks the access needed to observe all metrics,
so we create a `ClusterRoleBinding` that assigns `cluster-admin` (`ClusterRole`) permissions 
to dashboard's `ServiceAccount`.

Token auth:

```bash
# 1. Assign cluster-admin permissions to dashboard ServiceAccount
sa=kubernetes-dashboard
ns=$sa
cr=cluster-admin
kubectl get clusterrolebinding $sa-admin || 
    kubectl create clusterrolebinding $sa-admin \
    --clusterrole=$cr \
    --serviceaccount=$ns:$sa

# 2. Create token
kubectl -n $ns create token $sa
#... eyJ...vW5g

```


### &nbsp;

