# Kerberos @ [RHEL NFS Server](https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/8/html/deploying_different_types_of_servers/deploying-an-nfs-server_deploying-different-types-of-servers) 

When a RHEL system is joined to an Active Directory (AD) domain using `realm join`, `sssd` is responsible for handling authentication, including Kerberos ticketing.


## TL:DR

We were able to generate Kerberos tickets for host, and even for NFS after a fantastic amount of configuration; however, the tickets are short lived and do not renew automatically, even after meticulously configuring it to do so.  

__Kerberos is notoriously tedious to manage.__
The scheme requires coordinated configurations across sssd, krb5, pam.d and AD  has more configuration permutations than there are atoms in the Universe.
Tickets failing to renew after expiry is a common fail mode.

## NFS Server/Client Services

The services required for the **NFS server** and **NFS client** depend on the **NFS version** and the **specific configuration** (e.g., Kerberos authentication, Active Directory integration). Below is a summary of the required services for both the server and client in your environment.

---

### **NFS Server Services**
The following services are typically required on the **NFS server**:

```bash
dnf install -y nfs-utils rpcbind krb5-workstation chrony authselect
```

1. **`rpcbind`**:
   - Required for **NFSv3** to map RPC services to their corresponding ports.
   - Not strictly required for **NFSv4**, but often enabled for backward compatibility.

2. **`nfs-server`**:
   - The main NFS server service that handles NFS exports and client requests.

3. **`nfs-mountd`**:
   - Required for **NFSv3** to handle mount requests.
   - Optional for **NFSv4**, but often enabled for backward compatibility or mixed environments.

4. **`rpc-statd`**:
   - Required for **NFSv3** to handle file locking and crash recovery.
   - Not required for **NFSv4**, but often enabled for backward compatibility or mixed environments.

5. **`chronyd`**:
   - Ensures time synchronization with the domain controller and clients.
   - Critical for Kerberos authentication.

6. **Optional: `rpc-svcgssd`**:
   - Required for **Kerberos authentication** on the NFS server.
   - Handles server-side Kerberos security.

---

### **NFS Client Services**
The following services are typically required on the **NFS client**:

```bash
dnf install -y nfs-utils rpcbind krb5-workstation chrony authselect
```

1. **`nfs-client.target`**:
   - A target that ensures all necessary NFS client services are running.

2. **`rpc-gssd`**:
   - Required for **Kerberos authentication** on the NFS client.
   - Handles client-side Kerberos security.

3. **`rpcbind`**:
   - Required for **NFSv3** to map RPC services to their corresponding ports.
   - Not strictly required for **NFSv4**, but often enabled for backward compatibility.

4. **`nfs-idmapd`**:
   - Required for **NFSv4** to map user and group IDs between the client and server.
   - Ensures consistent UID/GID mapping for files and directories.

5. **`chronyd`**:
   - Ensures time synchronization with the domain controller and server.
   - Critical for Kerberos authentication.

---

### **Summary of Services**

#### **NFS Server**
| Service          | Required for NFSv3 | Required for NFSv4 | Notes                                   |
|------------------|--------------------|--------------------|-----------------------------------------|
| `rpcbind`        | Yes                | Optional           | Required for NFSv3, optional for NFSv4. |
| `nfs-server`     | Yes                | Yes                | Main NFS server service.                |
| `nfs-mountd`     | Yes                | Optional           | Required for NFSv3, optional for NFSv4. |
| `rpc-statd`      | Yes                | Optional           | Required for NFSv3, optional for NFSv4. |
| `chronyd`        | Yes                | Yes                | Critical for Kerberos authentication.   |
| `rpc-svcgssd`    | Optional           | Optional           | Required for Kerberos authentication.   |

#### **NFS Client**
| Service              | Required for NFSv3 | Required for NFSv4 | Notes                                   |
|----------------------|--------------------|--------------------|-----------------------------------------|
| `nfs-client.target`  | Yes                | Yes                | Ensures all NFS client services are running. |
| `rpc-gssd`           | Optional           | Yes                | Required for Kerberos authentication.   |
| `rpcbind`            | Yes                | Optional           | Required for NFSv3, optional for NFSv4. |
| `nfs-idmapd`         | No                 | Yes                | Required for NFSv4 ID mapping.          |
| `chronyd`            | Yes                | Yes                | Critical for Kerberos authentication.   |

---

### **Example Commands to Enable and Start Services**

#### **On the NFS Server**
```bash
sudo systemctl enable rpcbind nfs-server nfs-mountd rpc-statd chronyd
sudo systemctl start rpcbind nfs-server nfs-mountd rpc-statd chronyd
```

If using Kerberos:
```bash
sudo systemctl enable rpc-svcgssd
sudo systemctl start rpc-svcgssd
```

#### **On the NFS Client**
```bash
sudo systemctl enable nfs-client.target rpc-gssd rpcbind nfs-idmapd chronyd
sudo systemctl start nfs-client.target rpc-gssd rpcbind nfs-idmapd chronyd
```

---

### **Key Considerations**
1. **NFS Version**:
   - For **NFSv3**, ensure `rpcbind`, `nfs-mountd`, and `rpc-statd` are running on both the server and client.
   - For **NFSv4**, focus on `nfs-idmapd` and `rpc-gssd` (for Kerberos).

2. **Kerberos Authentication**:
   - Ensure `rpc-gssd` is running on the client and `rpc-svcgssd` is running on the server.

3. **Time Synchronization**:
   - Ensure `chronyd` is running on both the server and client for Kerberos to work properly.

4. **Firewall Configuration**:
   - Open the necessary ports for NFS, rpcbind, and Kerberos on both the server and client.


## Summary of Commands

For this NFS + Kerberos + AD Integration Project

## **1️⃣ Active Directory (AD) Configuration on Windows Server**
### **🔹 Verify Kerberos KDC on AD DC**
```powershell
Get-Service KDC
```
```powershell
PS C:\Users\Administrator> Get-Service KDC

Status   Name               DisplayName
------   ----               -----------
Running  KDC                Kerberos Key Distribution Center
```
### **🔹 Verify AD Issues Kerberos Tickets**
```powershell
klist tickets
```
- These tickets regard this host only; 
  they have nothing to do with RHEL hosts under this DC.

### **🔹 Verify AD DNS Records for Kerberos**
```powershell
nslookup -type=SRV _kerberos._tcp.lime.lan
```
### **🔹 Create an NFS Service Principal in AD**

If all the relevant RHEL services are configured properly, then a Service principal is created automatically for each host upon "`realm join --user=Administrator lime.lan`". 

```
host/a0.lime.lan@LIME.LAN
RestrictedKrbHost/a0.lime.lan@LIME.LAN
```
However, such is not the case for the NFS server (`nfs-server`) created at a RHEL host thereafter.


```powershell
ktpass -out "C:\nfs_a0.keytab" `
    -princ "nfs/a0.lime.lan@LIME.LAN" `
    -mapuser "LIME\A0$" `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass +rndpass
```
### **🔹 Verify Keytab File**

A keytab file __stores encryption keys__ for service principals, allowing services to authenticate themselves to the Kerberos Key Distribution Center (KDC) without requiring manual password entry.

Verify the newly-created keytab file

```powershell
klist -k C:\nfs_a0.keytab
```

---

## **2️⃣ Linux: General AD & Kerberos Configuration**
### **🔹 Verify Kerberos Authentication**
```bash
kinit u2@LIME.LAN # If needed
klist
```
```plaintext
Ticket cache: KCM:0
Default principal: u2@LIME.LAN

Valid starting     Expires            Service principal
03/14/25 10:37:49  03/14/25 20:37:49  krbtgt/LIME.LAN@LIME.LAN
        renew until 03/21/25 10:37:44
```
### **🔹 Request a Service Ticket for NFS**
```bash
kinit -S nfs/a0.lime.lan u2@LIME.LAN
```
```bash
klist
```
Before:
```plaintext
Ticket cache: KCM:0:31053
Default principal: A2$@LIME.LAN

Valid starting     Expires            Service principal
12/31/69 19:00:00  12/31/69 19:00:00  Encrypted/Credentials/v1@X-GSSPROXY:
```
After:
```plaintext
Default principal: u2@LIME.LAN

Valid starting     Expires            Service principal
03/14/25 10:29:12  03/14/25 20:29:12  nfs/a0.lime.lan@LIME.LAN
        renew until 03/21/25 10:29:05
```
### **🔹 Check Kerberos Ticket Expiry**
```bash
klist -f
```
### **🔹 Renew Kerberos Ticket Manually**
```bash
kinit -R
```
### **🔹 Destroy All Kerberos Tickets**
```bash
kdestroy
```
### **🔹 Verify Keytab on NFS Server**
```bash
sudo klist -k /etc/krb5.keytab | grep nfs
```

---

## **3️⃣ SSSD Configuration**
### **🔹 Verify SSSD Configuration**
```bash
sssctl config-check
```
### **🔹 Restart SSSD & Apply Changes**
```bash
sudo systemctl restart sssd
journalctl -u sssd --no-pager | tail -n 50
```
### **🔹 Clear SSSD Cache**
```bash
sudo sssctl cache-remove u2
sudo systemctl restart sssd
```

---

## **4️⃣ NFS Server Setup**
### **🔹 Verify NFS Daemon Status**
```bash
systemctl status nfs-server
```
### **🔹 Restart NFS Services**
```bash
sudo systemctl restart nfs-server rpc-gssd
```
### **🔹 Check Running NFS Processes**
```bash
ps aux | grep nfsd
```
### **🔹 Verify NFS Exports**
```bash
exportfs -v
```
### **🔹 Reload NFS Exports**
```bash
exportfs -rv
```
### **🔹 Check Kernel NFS Modules**
```bash
lsmod | grep nfs
```
### **🔹 Check NFS Ports**
```bash
ss -tulpn | grep :2049
```

---

## **5️⃣ NFS Client Configuration**
### **🔹 Check Current NFS Mounts**
```bash
mount | grep nfs
```
### **🔹 Verify NFS Mount Security Mode**
```bash
nfsstat -m
```
### **🔹 Unmount and Remount NFS with Kerberos**
```bash
sudo umount -f /mnt/nfs
sudo mount -o sec=krb5p nfs-server:/exports/data /mnt/nfs
```
### **🔹 Show NFS Exports from Server**
```bash
showmount -e a0.lime.lan
```

---

## **6️⃣ Debugging & Troubleshooting**
### **🔹 Check System Logs for NFS & Kerberos**
```bash
journalctl -xe | grep krb5
journalctl -xe | grep nfs
```
### **🔹 Check Kernel Logs for NFS Issues**
```bash
dmesg | grep nfs
```
### **🔹 Check if KCM Cache is Used**
```bash
klist -C
```
### **🔹 Force Clear KCM Credential Cache**
```bash
sudo keyctl purge user
```
### **🔹 Verify Kernel Keyring**
```bash
sudo keyctl show
```
### **🔹 Remove Stuck Kerberos Credentials**
```bash
sudo sssctl cache-remove u2
sudo systemctl restart sssd
```

---

### **📌 Next Steps**
If something is **still not working**, focus on:
1. **Ensuring the correct Kerberos tickets exist (`klist`).**
2. **Verifying AD authentication (`kinit -S nfs/a0.lime.lan`).**
3. **Checking whether NFS enforces Kerberos (`nfsstat -m`).**
4. **Examining logs (`journalctl -xe | grep krb5`).**

Would you like any additional sections added? 🚀


## @ Server : [`install-nfs-server.sh`](install-nfs-server.sh)

@ `a0` as `root`

Configure the share __only after host is joined into domain__.

### [Kerberos](https://chatgpt.com/share/67c47f8a-ca60-8009-bd32-99d0d10bebf7)

Do not add Kerberos option at NFS server unless host is configured for it.

If `sssd` is of host joined into AD by `realm join`, 
then it is configured __to allow for__ Kerberos.

See `/etc/sssd/sssd.conf`, `man sssd-krb5` and `man sssd.conf`

 However, creating, renewing, and otherwise maintaining __Kerberos tickets requires a labyrinth of configurations across many interrelated tools__. And such tickets are target specific. That is, tickets for use at a host differ from those for use at NFS on that host.


```bash
# Create/Renew ticket : Prompts for user's AD password
kinit # Default (AD DS USER@REALM)
# Else declare
realm=$(hostname -d)
kinit $(id -un)@${realm^^}

# Verify
klist
```

@ `u1@a0`

```bash
u1@a0 [08:05:27] [1] [#0] ~
☩ kinit admin@LIME.LAN
Password for admin@LIME.LAN:

u1@a0 [08:06:40] [1] [#0] ~
☩ klist
Ticket cache: KCM:1000
Default principal: admin@LIME.LAN

Valid starting     Expires            Service principal
03/02/25 08:06:36  03/02/25 18:06:36  krbtgt/LIME.LAN@LIME.LAN
        renew until 03/09/25 09:06:14
```

```bash
☩ kinit u1@LIME.LAN
Password for u1@LIME.LAN:

☩ klist
Ticket cache: KCM:1000:28381
Default principal: u1@LIME.LAN

Valid starting     Expires            Service principal
03/02/25 08:11:22  03/02/25 18:11:22  krbtgt/LIME.LAN@LIME.LAN
        renew until 03/09/25 09:11:17

☩ klist -l
Principal name                 Cache name
--------------                 ----------
u1@LIME.LAN                    KCM:1000:28381
admin@LIME.LAN                 KCM:1000
```
- So Kerberos ticket is good for __7 days__


Yet for NFS access, each user of each client needs a valid ticket-granting ticket (TGT).

```bash
# Get ticket for service (-S SERVICE)
kinit -S nfs/a0.lime.lan@LIME.LAN $user

```

__Get TGT__ (ticket-granting ticket) for NFS at all clients

```bash
☩ ansibash
...
  ANSIBASH_TARGET_LIST='a1 a2 a3'
  ANSIBASH_USER='u2'

☩ ansibash kinit -S nfs/a0.lime.lan@LIME.LAN u2
```

Verify

```bash
u2@a1 [07:21:43] [1] [#0] ~
☩ klist -c
Ticket cache: KCM:322202610:62865
Default principal: u2@LIME.LAN

Valid starting     Expires            Service principal
03/13/25 22:11:35  03/14/25 08:11:35  krbtgt/LIME.LAN@LIME.LAN
        renew until 03/20/25 22:11:29
03/13/25 22:12:23  03/14/25 08:11:35  nfs/a0.lime.lan@
        renew until 03/20/25 22:11:29
        Ticket server: nfs/a0.lime.lan@LIME.LAN
```

Validate

```bash
☩ ansibash ls -hal /mnt
=== u2@a1
drwxr-xr-x.  3 root root            20 Feb  1 18:38 .
dr-xr-xr-x. 18 root root           235 Dec 13 12:35 ..
drwxrws---+  3 root ad-linux-users  24 Mar  2 16:38 nfs_01
=== u2@a2
drwxr-xr-x.  3 root root            20 Mar  1 16:22 .
dr-xr-xr-x. 18 root root           235 Dec 13 12:41 ..
drwxrws---+  3 root ad-linux-users  24 Mar  2 16:38 nfs_01
=== u2@a3
drwxr-xr-x.  3 root root            20 Mar  1 16:22 .
dr-xr-xr-x. 18 root root           235 Dec 13 12:42 ..
drwxrws---+  3 root ad-linux-users  24 Mar  2 16:38 nfs_01
```

```bash
☩ ansibash ls -hal /mnt/nfs_01
=== u2@a1
...
drwxrws---+ 2 u2   ad-linux-users 15 Mar  1 17:19 a
-rw-rw----. 1 u1   ad-linux-users  0 Mar  2 16:38 b
=== u2@a2
...
drwxrws---+ 2 u2   ad-linux-users 15 Mar  1 17:19 a
-rw-rw----. 1 u1   ad-linux-users  0 Mar  2 16:38 b
=== u2@a3
...
drwxrws---+ 2 u2   ad-linux-users 15 Mar  1 17:19 a
-rw-rw----+ 1 u1   ad-linux-users  0 Mar  2 16:38 b
```

### Declare the domain

```bash
sudo vi /etc/idmapd.conf
```

```plaintext
[General]
Domain = lime.lan
```
```bash
firewall-cmd --permanent --add-service nfs
firewall-cmd --reload
#systemctl enable --now nfs-server
exportfs -ra
systemctl daemon-reload
systemctl restart nfs-mountd
systemctl restart nfs-server
```

Verify 

```bash
cat /proc/fs/nfsd/versions # +4.2
```

## @ Client(s)

__This only after host is joined into domain__ 
and __AD user (`u1`) is created and added to AD group `linux-users`__.

@ `a1` as `root`

```bash
dnf install -y nfs-utils

# Mount temporarily
nfs_server=a0.lime.lan
nfs_mount=/mnt/nfs_01
local_mnt=/mnt/nfs_01
mkdir -p $local_mnt
mount -t nfs4 -o vers=4.2 $nfs_server:$nfs_mount/ $local_mnt/
```
@ `/etc/fstab`

```ini
a0.lime.lan:/mnt/nfs_01 /mnt/nfs_01 nfs4 vers=4.2,_netdev,auto 0 0
```

Fail

```bash
root@a1 [07:54:29] [1] [#0] /home/u1
# nfs_server=a0.lime.lan
nfs_mount=/mnt/nfs_01
local_mnt=/mnt/nfs_01
mkdir -p $local_mnt
mount -t nfs4 -o vers=4.2 $nfs_server:$nfs_mount/ $local_mnt/
mount.nfs4: access denied by server while mounting a0.lime.lan:/mnt/nfs_01/
```

### Kerberos config 

Auto get ticket on user login and  auto renew

See `nfs/kerberos/`. Mod to configs:

- `/etc/sssd/sssd.conf`
- `/etc/pam.d/sshd`
- `/etc/krb5.conf`


Install all

```bash
tar -caf kerberos.tgz nfs/kerberos
ansibash -u kerberos.tgz
ansibash tar -xaf  kerberos.tgz
ansibash sudo cp nfs/kerberos/sssd.conf /etc/sssd/
ansibash sudo ls -hl /etc/sssd/
ansibash sudo cat /etc/sssd/sssd.conf |grep krb5
ansibash sudo cp nfs/kerberos/pam.d.sshd /etc/pam.d/sshd
ansibash sudo ls -hl /etc/pam.d/sshd
ansibash sudo cp nfs/kerberos/krb5.conf /etc/krb5.conf
ansibash sudo ls -hl /etc/krb5.conf
ansibash ls -hl nfs/kerberos/

# Restart services
sudo systemctl restart sssd
sudo systemctl restart rpc-gssd
sudo systemctl restart nfs-client.target
```


__Verify__

```bash
☩ ansibash klist
=== u2@a1
Ticket cache: KCM:322202610:62865
Default principal: u2@LIME.LAN

Valid starting     Expires            Service principal
03/02/25 17:54:58  03/03/25 03:54:58  nfs/a0.lime.lan@LIME.LAN
        renew until 03/09/25 18:54:52
=== u2@a2
Ticket cache: KCM:322202610:72575
Default principal: u2@LIME.LAN

Valid starting     Expires            Service principal
03/02/25 17:55:02  03/03/25 03:55:02  nfs/a0.lime.lan@LIME.LAN
        renew until 03/09/25 18:54:59
=== u2@a3
Ticket cache: KCM:322202610:85859
Default principal: u2@LIME.LAN

Valid starting     Expires            Service principal
03/02/25 17:55:07  03/03/25 03:55:07  nfs/a0.lime.lan@LIME.LAN
        renew until 03/09/25 18:55:03
```

#### Kerberos @ AD KDC

AD KDC is built into AD DS.

- The Domain Controller (DC) acts as the KDC.
- The KDC issues Kerberos tickets (TGTs & service tickets) to domain users and services.
- When you run `kinit` on a Linux client, it contacts the KDC running on the AD DC.

__Recreate Kerberos `*.keytab`__ having all SPNs.
Do this __only if necessary__; 
only if `klist` is not recognize the NFS server.
That is, if `klist` does not report the NFS server 
as a "Service principal" of a ticket-generating ticket (TGT).

After adding an NFS server at host `a0`

1. `realm leave` at all RHEL hosts that are NFS clients
2. Run this PowerShell script at the domain controller (AD KDC)
3. `realm join` at all RHEL hosts that are NFS clients

@ `dc1.lime.lan` (host of Windows Server)

```powershell
$Realm      = "LIME.LAN"
$Domain     = "LIME"   # NetBIOS domain name used by AD KDC (See -mapuser)
$Machine    = "A0"
$KeytabPath = "C:\$Machine.keytab"

# Get all SPNs assigned to the machine
$SPNs = setspn -L "$Machine$" | Select-String -Pattern "^\s+\S+" | ForEach-Object { $_.ToString().Trim() }

# Check if SPNs were found
if (-not $SPNs) {
    Write-Host "No SPNs found for $Machine$ in domain $Realm"
    exit 1
}

# Generate keytab for the first SPN (without -append)
$FirstSPN = $SPNs[0]
$FirstPrincipal = "$FirstSPN@$Realm"
Write-Host "Adding $FirstPrincipal to keytab..."
ktpass -out "$KeytabPath" `
    -princ $FirstPrincipal `
    -mapuser "$Domain\$Machine$" ` 
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass +rndpass
# ktpass -out nfs.keytab `
#     -princ nfs/a0.lime.lan@LIME.LAN `
#     -mapuser LIME\A0$ `
#     -crypto AES256-SHA1 `
#     -ptype KRB5_NT_PRINCIPAL `
#     -pass +rndpass



# Add remaining SPNs with -append
$SPNs | Select-Object -Skip 1 | ForEach-Object {
    $SPN = $_
    $Principal = "$SPN@$Realm"
    Write-Host "Appending $Principal to keytab..."
    
    ktpass -out "$KeytabPath" `
        -princ $Principal `
        -mapuser "$Domain\$Machine$" `
        -crypto AES256-SHA1 `
        -ptype KRB5_NT_SRV_HST `
        -pass +rndpass `
        -append
}

Write-Host "Keytab generated at $KeytabPath"
```
