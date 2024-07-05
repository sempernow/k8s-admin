# NFS 

>Provision an NFS server on any RHEL host

This is intended for use by clients that are K8s CSI provisioners of NFS type storage.

## [`provision-lvm-data-nfs.sh`](nfs/provision-lvm-data-nfs.sh)

## Server : [`/etc/exports`](etc.exports)

Note NFS export declarations and systemd service at the server:

@ `a0`

```bash
☩ ssh a0 cat /etc/exports
#/mnt/nfs_01    192.168.11.0/24(rw,sync,sec=krb5p:krb5i:krb5:sys,root_squash,no_subtree_check)
/srv/nfs/k8s    192.168.11.0/24(rw,sync,no_root_squash,no_subtree_check)
```
```bash
☩ ssh a0 ls -hl /srv
total 0
drwxr-xr-x. 3 root root 17 Apr  6 08:17 nfs
```
```bash
☩ ssh a0 systemctl status nfs-server.service
```
```plaintext
● nfs-server.service - NFS server and services
     Loaded: loaded (/usr/lib/systemd/system/nfs-server.service; enabled; preset: disabled)
    Drop-In: /run/systemd/generator/nfs-server.service.d
             └─order-with-mounts.conf
     Active: active (exited) since Sun 2025-04-06 08:33:18 EDT; 2h 12min ago
       Docs: man:rpc.nfsd(8)
             man:exportfs(8)
    Process: 22236 ExecStartPre=/usr/sbin/exportfs -r (code=exited, status=0/SUCCESS)
    Process: 22237 ExecStart=/usr/sbin/rpc.nfsd (code=exited, status=0/SUCCESS)
    Process: 22247 ExecStart=/bin/sh -c if systemctl -q is-active gssproxy; then systemctl reload gssproxy ; fi (code=exited, status=0/SUCCESS)
   Main PID: 22247 (code=exited, status=0/SUCCESS)
        CPU: 20ms

Apr 06 08:33:18 a0 systemd[1]: Starting NFS server and services...
Apr 06 08:33:18 a0 systemd[1]: Finished NFS server and services.
```

```bash
☩ ls -Rhl /srv
/srv:
total 0
drwxr-xr-x. 3 root root 17 Apr  6 08:17 nfs

/srv/nfs:
total 0
drwxrwxrwx. 3 root root 34 Apr  6 10:34 k8s

/srv/nfs/k8s:
total 0
drwxr-xr-x. 2 u2 ad-linux-users 15 Apr  6 10:41 bb
-rw-r--r--. 1 u1 u1              0 Apr  6 08:36 a
-rw-r--r--. 1 u2 ad-linux-users  0 Apr  6 10:34 b

/srv/nfs/k8s/bb:
total 0
-rw-r--r--. 1 u2 ad-linux-users 0 Apr  6 10:41 a
```
- Note export, `/srv/nfs/k8s`, has file mode `777`


## Client @ `[u2@a2 ~]`

```bash
sudo mkdir /mnt/test
sudo mount -t nfs a0.lime.lan:/srv/nfs/k8s /mnt/test
```

```bash
$ mkdir -p /mnt/test/bb
$ touch /mnt/test/b
$ touch /mnt/test/bb/a
$ ls -Rhl /mnt/
/mnt/:
total 0
drwxr-xr-x. 2 root root  6 Mar  1 16:22 nfs_01
drwxrwxrwx. 3 root root 34 Apr  6 10:34 test

/mnt/nfs_01:
total 0

/mnt/test:
total 0
-rw-r--r--. 1 u1 u1              0 Apr  6 08:36 a
-rw-r--r--. 1 u2 ad-linux-users  0 Apr  6 10:34 b
drwxr-xr-x. 2 u2 ad-linux-users 15 Apr  6 10:41 bb

/mnt/test/bb:
total 0
-rw-r--r--. 1 u2 ad-linux-users 0 Apr  6 10:41 a
```
- Note the NFS-client mount, `/mnt/test`, 
  adopts the server-exported FS configurations;  
  `OWNER:GROUP` (`root:root`) and `MODE` (`777`).


## Client @ K8s Pod

```bash
kubectl apply -f app.nfs-common.yaml
```

## **NFS Mount Option: `hard` v. `soft`**

The `hard` and `soft` options in NFS determine __how the client behaves when an NFS server becomes unresponsive__ or crashes. Here’s a breakdown:

---

#### **1. `hard` (Recommended for Data Integrity)**
- **Behavior:**  
  - The client **retries NFS requests indefinitely** until the server responds.  
  - If the server is down, processes accessing NFS will **"hang" (freeze)** until the server returns.  
- **Use Case:**  
  - Critical data (databases, VM storage, transactional workloads).  
  - Ensures **no silent data corruption** if the server crashes.  
- **Example:**  
  ```bash
  mount -t nfs -o hard server:/share /mnt
  ```

**Pros & Cons of `hard`**
| Pros | Cons |
|------|------|
| ✅ **Guarantees data integrity** | ❌ **Processes freeze if server dies** |
| ✅ **No partial writes on failure** | ❌ Requires manual recovery (e.g., `umount -f`) |

---

#### **2. `soft` (Faster Failure Handling, Risky)**
- **Behavior:**  
  - The client **gives up after retries** (default: 3 retries, 60s timeout).  
  - Returns an I/O error (`EIO`) to applications if the server is unreachable.  
- **Use Case:**  
  - Non-critical data (e.g., read-only media, temporary files).  
  - Avoids hanging but risks **data corruption** if writes fail.  
- **Example:**  
  ```bash
  mount -t nfs -o soft server:/share /mnt
  ```

**Pros & Cons of `soft`**

| Pros | Cons |
|------|------|
| ✅ **No hanging processes** | ❌ **Risk of corrupted files** |
| ✅ **Faster failure detection** | ❌ Not suitable for databases/VMs |

---

#### **3. Key Differences**
| Feature          | `hard` | `soft` |
|------------------|--------|--------|
| **Retries**       | Infinite | Limited (default: 3) |
| **Process Behavior** | Hangs | Fails with `EIO` |
| **Data Safety**   | ✅ Safe | ❌ Risky |
| **Use Case**      | Databases, VMs | Temporary files |

---

#### **4. Best Practices**
1. **Always use `hard` for:**  
   - Databases (MySQL, PostgreSQL).  
   - Virtual machine disks (KVM, VMware).  
   - Any write-heavy workload.  

2. **Use `soft` only for:**  
   - Read-only mounts (e.g., media files).  
   - Non-critical scratch space.  

3. **Tune Timeouts (if needed):**  
   ```bash
   mount -t nfs -o hard,timeo=300,retrans=5 server:/share /mnt
   ```
   - `timeo`: Timeout in deciseconds (default: 600 = 60s).  
   - `retrans`: Number of retries (default: 3).  

---

#### **5. Recovery from a Frozen (`hard`) Mount**
If the server crashes and processes hang:
```bash
# Force-unmount (if safe):
umount -f /mnt

# Kill stuck processes:
fuser -km /mnt
```

---

#### **6. Example `/etc/fstab` Entry**
```bash
server:/share  /mnt  nfs  hard,timeo=300,retrans=5  0  0
```

---

#### **Final Recommendation**
- **Default to `hard`** for reliability.  
- **Never use `soft` for writes**—it can corrupt data.  
- **Adjust `timeo`/`retrans`** if network latency is high.  


## NFS Performance Tuning

### Server-Side Optimizations

#### **A. Kernel Tuning (Sysctl)**

@ `/etc/sysctl.conf`:

Inspect:

```bash
# Show NFS and SunRPC (client/server) settings
sysctl -a |grep -E '^(sunrpc|nfs|nfsd)'
#... others ...
```

Add: 
```bash
# Increase NFS thread count
sunrpc.tcp_max_slot_table_entries=128
sunrpc.udp_slot_table_entries=128

# Boost TCP performance
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem=4096 87380 16777216
net.ipv4.tcp_wmem=4096 87380 16777216
```

Apply changes:
```bash
sysctl -p
```

#### **B. NFS Daemon (nfsd) Threads**

Increase server threads (default=8):
```bash
echo "64" |sudo tee /proc/fs/nfsd/threads
```
- **Rule of thumb:** `2 threads per CPU core`.


## **`/etc/exports`**

```bash
/data  *(rw,async,no_wdelay,no_subtree_check,no_root_squash,fsid=0)
```
*Only includes server-side options:*
- `rw`: Read-write permissions
- `async`: Asynchronous writes (for performance)
- `no_wdelay`: Disables write batching (good for SSDs)
- `no_subtree_check`: Improves reliability
- `no_root_squash`: Allows root access (use cautiously)
- `fsid=0`: Filesystem ID for NFSv4

### Client-Side Optimizations : mount options

Ephemeral:

```bash
mount -t nfs -o rsize=65536,wsize=65536,timeo=50,retrans=5,noatime,hard server:/data /mnt
```
Persist : `/etc/fstab`:

```bash
server:/data  /mnt  nfs  rsize=65536,wsize=65536,timeo=50,retrans=5,noatime,hard  0  0
```

#### Server v. Client 

1. **Protocol Layer Separation**:
   - Server exports define *what* to share and *basic permissions*
   - Client mounts define *how* to access it (performance/retry settings)

2. **Implementation Details**:
   - `wsize/rsize` are TCP stack parameters negotiated during mount
   - `timeo/retrans` are client-side network timeout behaviors
   - The server has no control over these client TCP stack settings

3. **Error Prevention**:
   - NFS servers will reject unknown options with "unknown keyword"
   - Client mounts will ignore server-side options they don't understand

#### **Performance Considerations**
While the options are separated, they work together:
1. Server-side `async` + client-side `hard` = Best throughput for writes
2. Server-side `no_wdelay` + client-side `wsize=65536` = Optimal SSD performance
3. Client `timeo=50` (5s timeout) matches modern network expectations

#### **Special Case: NFSv4.1+ (pNFS)**
For parallel NFS, some performance options move back to server side:
```bash
/data  *(rw,async,no_wdelay,pnfs)
```

Apologies for the earlier confusion - the corrected separation is crucial for both functionality and performance tuning. Would you like me to provide any additional specifics about optimizing either the server or client configuration?

## Monitoring & Verification**
Check NFS stats:
```bash
nfsstat -c  # Client stats
nfsstat -s  # Server stats
cat /proc/net/rpc/nfsd  # NFS thread utilization
```
