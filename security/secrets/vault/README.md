# Vault in K8s


## Hashicorp Vault project Helm chart

Installs:

- A Vault cluster (with Raft or Consul storage)
    - Optional High Availability (HA) setup
- The Vault Agent Injector (for sidecar injection)
    - But no operator functionality

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
    --set 'server.ha.enabled=true' \
    --set 'server.ha.raft.enabled=true'

```

## [`bank-vaults/vault-operator`](https://github.com/bank-vaults/vault-operator "GitHub")

Installs operator, and optionally the vault cluster via CRDs.

DEPRICATED, along with the operator. 
