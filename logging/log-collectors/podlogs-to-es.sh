## Pods to ES directly, sans log-collector
# https://chat.deepseek.com/share/5gpzkuxy1zn3k1os61
kubectl create -f https://download.elastic.co/downloads/eck/2.0.0/crds.yaml
kubectl apply -f https://download.elastic.co/downloads/eck/2.0.0/operator.yaml
