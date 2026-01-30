# [`kubernetes-csi/csi-driver-smb`](https://github.com/kubernetes-csi/csi-driver-smb "GitHub")


>This driver allows Kubernetes to access SMB Server on both Linux and Windows nodes.


## TL;DR

The driver, `csi-driver-smb` v1.19.1, has bug preventing (CIFS) 
mount via [Kerberos AuthN if ticket management is at the node](https://github.com/kubernetes-csi/csi-driver-smb/blob/master/docs/driver-parameters.md#kerberos-ticket-support-for-linux). 

The required Secret providing the current Kerberos ticket cache (binary) fails, 
and so the Pod is stuck at status CreatingContainer due to failed mount, reporting "`Invalid UTF-8`". 

The fundamental __issue is the driver's gRPC handling of binary data__.
The node-level Kerberos setup is solid; the ___CSI driver just can't consume it properly___.

The simplest workaround is to mount the SMB share at all nodes,
and use `hostPath` for access in Pods.

Else must provision Pod-level ticket management.

## Provision : [`csi-driver-smb.sh`](./csi-driver-smb.sh)

## Reference

- __`smb-krb5-rhel-and-k8s`__ ([MD](smb-krb5-rhel-and-k8s.md)|[HTML](smb-krb5-rhel-and-k8s.html))
- __`netapp-cifs-export`__ ([MD](netapp-cifs-export.md)|[HTML](netapp-cifs-export.html))

