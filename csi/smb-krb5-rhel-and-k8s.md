# SMB (CIFS) Access from RHEL and Kubernetes

This document provides declarative workflows for mounting Windows SMB shares from RHEL hosts and Kubernetes clusters, using either NTLM or Kerberos authentication.

## Infrastructure Required

- Windows Server acting as Domain Controller and having ADDS, ADUAC at least
- RHEL 8+ hosts joined into the domain by `realm` and `sssd`.
- AD Groups 
    - `ad-smb-admins` (Used for RW access to SMB share)
    - `ad-smb-users` (Used for RO access to SMB share)

---

## Prerequisites: Windows Server Configuration

Complete these steps on the Domain Controller before configuring RHEL or Kubernetes clients.

### 1. Create SMB Share and Folder

```powershell
$smbDomain = (Get-ADDomain).NetBIOSName  # e.g., LIME
$smbName = "SMBData"
$smbPath = "C:\Shares\$smbName"

New-Item -Path "$smbPath" -ItemType Directory

New-SmbShare -Name "$smbName" `
    -Path "$smbPath" `
    -FullAccess "$smbDomain\ad-smb-admins" `
    -ReadAccess "$smbDomain\ad-smb-users" `
    -Description "SMB (CIFS) share for Linux hosts"

icacls "$smbPath" /grant "$smbDomain\ad-smb-admins:(OI)(CI)F"
icacls "$smbPath" /grant "$smbDomain\ad-smb-users:(OI)(CI)R"
```

### 2. Verify Firewall Rules

```powershell
Get-NetFirewallRule -DisplayGroup "File and Printer Sharing" |
    Where-Object {$_.Enabled -eq $true}
```

### 3. Create AD Service Account

```powershell
$realm  = "LIME.LAN"
$sa     = "svc-smb-rw"
$pass   = "__REDACTED__"
$securePass = ConvertTo-SecureString $pass -AsPlainText -Force

New-ADUser -Name "$sa" `
    -SamAccountName "$sa" `
    -UserPrincipalName "$sa@$realm" `
    -Path "OU=ServiceAccounts,OU=OU1,DC=lime,DC=lan" `
    -AccountPassword $securePass `
    -PasswordNeverExpires $true `
    -CannotChangePassword $true `
    -KerberosEncryptionType AES128,AES256 `
    -Enabled $true

# For read-write access:
Add-ADGroupMember -Identity "ad-smb-admins" -Members "$sa"
# For read-only access:
# Add-ADGroupMember -Identity "ad-smb-users" -Members "$sa"
```
- Use `-AccountPassword (Read-Host -AsSecureString "Password")` for interactive password entry
- `KerberosEncryptionType AES128,AES256` enforces AES only (no RC4/DES) for security/FIPS compliance

#### Verify Service Account

```powershell
Get-ADUser -Identity "$sa"
Get-ADPrincipalGroupMembership -Identity "$sa" | Select-Object Name
```

### 4. Harden Service Account (Optional)

```powershell
Set-ADUser -Identity "$sa" -HomeDirectory $null -ProfilePath $null
```

---

## NTLM Authentication Workflows

AD User (service account) __`sw-smb-rw`__ AuthN by NetBIOS/NTLMv2


### RHEL Host: NTLM Mount

#### 1. Install CIFS Utilities

```bash
sudo dnf install cifs-utils
```

#### 2. Create Credentials File

```bash
pass="$(agede svc-smb-rw.creds.age)"
credsPath=/etc/cifs/svc-smb-rw.creds

sudo mkdir -p /etc/cifs
sudo tee $credsPath <<EOH
username=svc-smb-rw
password=$pass
domain=LIME
EOH
sudo chmod 600 $credsPath
```

#### 3. Mount SMB (CIFS) Share :

`//SERVER/SHARE` --> `/mnt/HERE`

**Single-user access (service account only):**

```bash
sudo mount -t cifs //dc1.lime.lan/SMBData /mnt/smb-data-01 -o sec=ntlmssp,vers=3.0,credentials=$credsPath,uid=$(id -u svc-smb-rw),gid=$(id -g svc-smb-rw),file_mode=0640,dir_mode=0775
```
- SMB 3.0
- AutnN by NTLMSSP (NTLM **S**ecurity **S**upport **P**rovider) mechanism, 
    which negotiates security, typically using NTLMv2; 
    ***is not FIPS compliant***.

**Group access (all members of `ad-smb-admins`):**

```bash
sudo mount -t cifs //dc1.lime.lan/SMBData /mnt/smb-data-01 -o sec=ntlmssp,vers=3.0,credentials=$credsPath,uid=$(id -u svc-smb-rw),gid=$(getent group ad-smb-admins |cut -d: -f3),file_mode=0660,dir_mode=0775
```

#### 4. Persistent Mount via `/etc/fstab`

Append the mount declartion: 

```bash
sudo tee -a /etc/fstab <<EOH
//dc1.lime.lan/SMBData  /mnt/smb-data-01  cifs  sec=ntlmssp,vers=3.0,credentials=$credsPath,uid=$(id -u svc-smb-rw),gid=$(getent group ad-smb-admins |cut -d: -f3),file_mode=0660,dir_mode=0775_netdev,nofail  0  0
EOH
```

#### NTLM Mount Function (Scripted)

```bash
setCreds(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    [[ $3 ]] || echo "  USAGE: $FUNCNAME user pass realm 2>&"
    [[ $3 ]] || return 2

    mkdir -p /etc/cifs || return 3
	tee /etc/cifs/$1.creds <<-EOH
	username=$1
	password=$2
	domain=$3
	EOH
    chmod 600 /etc/cifs/$1.creds
}

mountCIFS(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    mode=${1:-service}  # service|group|unmount

    dnf list installed cifs-utils || dnf -y install cifs-utils || return 2

    realm=LIME
    server=dc1.lime.lan
    share=SMBdata
    mnt=/mnt/smb-data-01
    svc=svc-smb-rw
    creds=/etc/cifs/$svc.creds
    mkdir -p $mnt || return 3
    uid="$(id -u $svc)"

    [[ $mode == unmount ]] && { umount $mnt; return $?; }
    echo "Mount CIFS share from $(hostname -f) for '$mode' access."

    gid="$(id -g svc-smb-rw)"
    [[ $mode == service ]] && {
        mount -t cifs //$server/$share $mnt -o sec=ntlmssp,vers=3.0,credentials=$creds,uid=$uid,gid=$gid,file_mode=0640,dir_mode=0775 || return 4
    }

    gid="$(getent group ad-smb-admins | cut -d: -f3)"
    [[ $mode == group ]] && {
        mount -t cifs //$server/$share $mnt -o sec=ntlmssp,vers=3.0,credentials=$creds,uid=$uid,gid=$gid,file_mode=0660,dir_mode=0775 || return 5
    }

    return 0
}
```

---

## Kerberos Authentication Workflows

AD User (service account) __`sw-smb-rw`__ AuthN by Kerberos

KCM is SSSD's **K**erberos **C**redential **M**anager. 
When a Linux (RHEL) host is joined into the AD domain via "`realm join`" 
(or manual SSSD config), __the default credential cache__, 
declared in **`/etc/krb5.conf`**, 
is set to KCM:

```ini
[libdefaults]
    default_ccache_name = KCM:
```

That's why `kinit` run _as any user_ stores tickets in KCM automatically, 
and why our `klist` shows `KCM:322203108` rather than `FILE:/tmp/krb5cc_322203108`.


### Quick Reference (TL;DR)

```powershell
# Generate keytab on Windows DC:
$realm  = "LIME.LAN"
$sa     = "svc-smb-rw"
$pass   = "__REDACTED__"

cmd /c ktpass -princ $sa@$realm -mapuser LIME\$sa -pass $pass -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -out $sa.keytab
```


```bash
# Set keytab permissions on RHEL:
sudo chown svc-smb-rw: /etc/svc-smb-rw.keytab
sudo chmod 600 /etc/svc-smb-rw.keytab

# Acquire ticket:
sudo -u svc-smb-rw kinit -k -t /etc/svc-smb-rw.keytab svc-smb-rw@LIME.LAN

# Mount:
realm=LIME; server=dc1.lime.lan; share=SMBdata; mnt=/mnt/smb-data-01; svc=svc-smb-rw
mkdir -p $mnt
uid="$(id -u $svc)"; gid="$(id -g $svc)"
mount -t cifs //$server/$share $mnt -o sec=krb5,vers=3.0,cruid=$uid,uid=$uid,gid=$gid,file_mode=0640,dir_mode=0775
```

**Key Points:**

- KVNO (**K**ey **V**ersion **N**umber) 
  must match between keytab and AD 
  (regenerate keytab after password changes)
- Ticket must be in the correct user's cache (not root's)
- `ktutil` on Linux doesn't know the real KVNO, 
   so better using `ktpass` on Windows

---

### Keytab Generation

#### Option A: Generate on Windows Server (Recommended)

Using __`ktpass`__

```powershell
$netbios = "LIME"
$realm   = "$netbios.LAN"
$sa      = "svc-smb-rw"
$pass    = "__REDACTED__"

cmd /c ktpass -princ $sa@$realm -mapuser $netbios\$sa -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -pass $pass -out ${sa}.keytab
```
- Fails at PowerShell unless invoked by `cmd`.

#### Option B: Generate on RHEL

**Prerequisite:** 

**Verify RHEL sees the AD service account**:

```bash
id svc-smb-rw@LIME.LAN
# uid=322203108(svc-smb-rw) gid=322200513(domain users) groups=322200513(domain users),322203103(ad-smb-admins)

getent passwd svc-smb-rw@LIME.LAN
# svc-smb-rw:*:322203108:322200513:svc-smb-rw:/home/svc-smb-rw:/bin/bash
```

**Verify KVNO (Key Version Number)** at either Windows or RHEL:

**On Windows:**

```powershell
Get-ADUser $sa -Properties msDS-KeyVersionNumber | Select-Object msDS-KeyVersionNumber
```

**On RHEL:**

```bash
sudo dnf install -y openldap-clients
kinit u2@LIME.LAN
ldapsearch -H ldap://dc1.lime.lan -Y GSSAPI -b "DC=lime,DC=lan" "(sAMAccountName=svc-smb-rw)" msDS-KeyVersionNumber
```

**Install required packages:**

```bash
dnf install krb5-workstation
```

**Interactive method:**

```bash
sudo ktutil
# In ktutil session:
# addent -password -p svc-smb-rw@LIME.LAN -k <KVNO> -e aes256-cts-hmac-sha1-96
# <enter password>
# wkt /etc/svc-smb-rw.keytab
# quit
```

**Non-interactive method:**

```bash
password="$(agede svc-smb-rw.creds.age)"
sudo ktutil <<EOF
addent -password -p svc-smb-rw@LIME.LAN -k <KVNO> -e aes256-cts-hmac-sha1-96
$password
wkt /etc/svc-smb-rw.keytab
quit
EOF
```

> **Warning:** `ktutil` is a local-only tool that doesn't query AD for the current KVNO. __Always verify__ the KVNO __before generating a keytab__ on RHEL.

---

### RHEL Host: Kerberos Mount

By AD User (service account) __`sw-smb-rw`__

#### 1. Install Packages

```bash
sudo dnf install cifs-utils krb5-workstation
```

#### 2. Deploy Keytab

Copy the keytab file generated on Windows to `/etc/svc-smb-rw.keytab` on each RHEL host.

#### 3. Set Keytab Permissions

```bash
sudo chown svc-smb-rw:svc-smb-rw /etc/svc-smb-rw.keytab
sudo chmod 600 /etc/svc-smb-rw.keytab
```

#### 4. Verify Keytab and Cache

```bash
# Keytab file
# - Static file containing the principal's long-term keys. 
# - Used to obtain tickets without a password. 
# - Doesn't change unless regenerated
#   (e.g., after password rotation or KVNO bump).
sudo klist -k -t /etc/svc-smb-rw.keytab

# Credential cache
# - Dynamic/runtime cache of actual Kerberos tickets 
#   (TGT + service tickets)
# - Tickets expire, get renewed, and rotate throughout the day 
#   as the principal authenticates to services.
sudo -u svc-smb-rw klist  

```
- Credential cache is what a current AuthN attempt would rely upon.

__If KVNO mismatch__ (Windows vs. RHEL) occurs, 
then regenerate keytab on Windows:

```powershell
$netbios    = "LIME"
$realm      = "$netbios.LAN"
$sa         = "svc-smb-rw"
$password   = "__REDACTED__"

cmd /c ktpass -princ $sa@$realm -mapuser $sa@$realm -pass $password -crypto AES256-SHA1 -ptype KRB5_NT_PRINCIPAL -out ${sa}.keytab
```

#### 5. Acquire Kerberos Ticket

```bash
# Acquire ticket for service-account user (using keytab file)
sudo -u svc-smb-rw kinit -k -t /etc/svc-smb-rw.keytab svc-smb-rw@LIME.LAN

# Verify the new ticket is in their credential cache
sudo -u svc-smb-rw klist  
```

> **Note:** The ticket must be acquired as the service account user, not root.

#### 6. Mount SMB Share

```bash
sudo mount -t cifs //dc1.lime.lan/SMBData /mnt/smb-data-01 -o sec=krb5,vers=3.0,cruid=$(id -u svc-smb-rw),uid=$(id -u svc-smb-rw),gid=$(id -g svc-smb-rw),file_mode=0640,dir_mode=0775

# Verify access to file created by Windows Administrator
sudo -u svc-smb-rw bash -c '
    echo $(date -Is) : Hello from $(id -un) @ $(hostname -f) |
        tee -a /mnt/smb-data-01/created-by-Administrator-at-uncpath-in-rdp-session.txt
'
# Verify access to write new file
sudo -u svc-smb-rw bash -c '
    echo $(date -Is) : Hello from $(id -un) @ $(hostname -f) |
        tee -a /mnt/smb-data-01/created-by-$(id -un)-at-cifs-mnt-krb5-authn-in-$(hostname -f).txt
'
```

<a name="configure-auto-ticket-renewal"></a>

#### 7. Configure Automatic Ticket Renewal

**Create systemd service:**

```ini
# Static : Do NOT enable
#sudo tee /etc/systemd/system/svc-smb-rw-kinit.service <<EOH
# /etc/systemd/system/svc-smb-rw-kinit.service
[Unit]
Description=Renew Kerberos ticket for svc-smb-rw
After=network-online.target

[Service]
Type=oneshot
User=svc-smb-rw
ExecStart=/usr/bin/kinit -k -t /etc/svc-smb-rw.keytab svc-smb-rw@LIME.LAN
#EOH
```

**Create systemd timer:**

```ini
#sudo tee /etc/systemd/system/svc-smb-rw-kinit.timer <<EOH
# /etc/systemd/system/svc-smb-rw-kinit.timer 
[Unit]
Description=Renew Kerberos ticket every 4 hours

[Timer]
OnBootSec=1min
OnUnitActiveSec=4h

[Install]
WantedBy=timers.target
#EOH
```

**Enable timer:**

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now svc-smb-rw-kinit.timer
```
- Unlike the `*.timer`, the associated `*.service` is *static*; 
  do not (attempt to) enable the service itself.

**Verify**

```bash
# Check timer is active and scheduled
systemctl status svc-smb-rw-kinit.timer

# Check last service run
systemctl status svc-smb-rw-kinit.service

# Verify ticket exists
sudo -u svc-smb-rw klist
```

> **Alternative:** The `k5start` package from `kstart` (EPEL) handles refresh automatically and can be daemonized.

#### Kerberos Mount Function (Scripted)

```bash
mountCIFSkrb5(){
    [[ "$(id -u)" -ne 0 ]] && return 1
    mode=${1:-service}  # service|group|unmount

    realm=LIME
    server=dc1.lime.lan
    share=SMBdata
    mnt=/mnt/smb-data-01
    svc=svc-smb-rw
    mkdir -p $mnt || return 3
    uid="$(id -u $svc)"

    [[ $mode == unmount ]] && { umount $mnt; return $?; }
    echo "Mount CIFS share from $(hostname -f) for '$mode' access using Kerberos."

    gid="$(id -g svc-smb-rw)"
    [[ $mode == service ]] && {
        mount -t cifs //$server/$share $mnt -o sec=krb5,vers=3.0,cruid=$uid,uid=$uid,gid=$gid,file_mode=0640,dir_mode=0775 || return 4
    }

    gid="$(getent group ad-smb-admins | cut -d: -f3)"
    [[ $mode == group ]] && {
        mount -t cifs //$server/$share $mnt -o sec=krb5,vers=3.0,cruid=$uid,uid=$uid,gid=$gid,file_mode=0660,dir_mode=0775 || return 5
    }

    return 0
}
```

---

### Kubernetes CSI: Kerberos Mount

Install the `csi-driver-smb` chart.

The `csi-driver-smb` node plugin runs as a privileged DaemonSet and performs `mount.cifs` in the host's mount namespace. The host kernel performs the SMB mount, so it uses the host's Kerberos credential cache.


---

#### Reference: CSI Driver SMB : [Kerberos ticket support for Linux](https://github.com/kubernetes-csi/csi-driver-smb/blob/master/docs/driver-parameters.md#kerberos-ticket-support-for-linux)

Pass kerberos ticket in kubernetes secret 
To pass a ticket through secret, it needs to be acquired. 
Here's example how it can be done:

```bash
export KRB5CCNAME="/var/lib/kubelet/kerberos/krb5cc_1000"
kinit USERNAME # Log in into domain
kvno cifs/lowercase_server_name # Acquire ticket for the needed share, it'll be written to the cache file
CCACHE=$(base64 -w 0 $KRB5CCNAME) # Get Base64-encoded cache
```

And passing the actual ticket to the secret, instead of the password.  
Note that key for the ticket has included credential id, 
that must match exactly cruid= mount flag. 
In theory, nothing prevents from having more than single ticket cache in the same secret.

```bash
kubectl create secret generic smbcreds-krb5 --from-literal krb5cc_1000=$CCACHE
```

>The problems you encountered (empty/invalid cache, UTF-8 errors) are specific to how that driver handles the Secret. The community thread you referenced suggests it's a known experimental feature with bugs.

---

#### Option A: Host-Level Ticket Management (Recommended for Self-Managed Clusters)

Configure **each Kubernetes node** same as that of host mount section:

1. **Deploy keytab** to `/etc/svc-smb-rw.keytab`
2. **Configure** `/etc/krb5.conf` for your domain
    - Handled automatically on "`realm join`" if by SSSD.
3. **Create systemd timer** for periodic `kinit`
    - Use same configuration as [7. Configure Automatic Ticket Renewal](#configure-auto-ticket-renewal)

The `cruid=` mount option (configured in StorageClass) tells the kernel which user's credential cache to search. The systemd service must run as that same user so the ticket lands in the correct cache. See [Credential Cache and `cruid=`](#credential-cache-and-cruid) reference.

> **Note:** Verify CSI node pods do not override `KRB5CCNAME` or isolate from host credential cache.

**Pros:** Simpler debugging, works regardless of CSI deployment
**Cons:** Requires node-level configuration, keytab on every node

#### Option B: CSI Pod-Level Ticket Management (For Managed/Immutable Nodes)

1. Store keytab in a Kubernetes Secret
2. Patch the `csi-smb-node` DaemonSet to mount the secret
3. Add init/sidecar container for `kinit`
4. Share credential cache volume between containers

**Pros:** Kubernetes-native, no node filesystem dependencies
**Cons:** More complex, requires DaemonSet patching and credential cache sharing

#### StorageClass Configuration

**Create keytab secret:**

```bash
kubectl create secret generic svc-smb-rw \
    --from-file=krb5.keytab=./svc-smb-rw.keytab \
    --namespace=kube-system
```

**Define StorageClass:**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: smb-kerberos
provisioner: smb.csi.k8s.io
parameters:
  source: //dc1.lime.lan/SMBData
mountOptions:
  - sec=krb5        # or krb5i (integrity), or krb5p (privacy/encryption)
  - cruid=322203108 # UID (credential) of Kerberos-AuthN user; cruid=$(id -u svc-smb-rw)
  - uid=1000        # Map file ownership to pipeline user
  - gid=1000
```

---

## Reference

### Common Mount Options

| Option | Purpose |
|--------|---------|
| `vers=3.0` or `3.1.1` | SMB protocol version (avoid SMB1) |
| `sec=krb5` | Kerberos authentication (domain-joined hosts) |
| `sec=ntlmssp` | NTLM authentication (simpler, non-domain-joined) |
| `uid=`, `gid=` | Map ownership to local user/group |
| `file_mode=`, `dir_mode=` | Override permissions on mount |
| `cruid=` | Credential UID for Kerberos ticket lookup |
| `_netdev` | Wait for network before mounting |

### Credential Cache and `cruid=`

The `cruid=` mount option determines which user's Kerberos credential cache the kernel searches for a valid ticket during `sec=krb5` mounts.

**Key point:** The systemd service `User=` directive must match `cruid=`. If `kinit` runs as root but mount uses `cruid=322203108`, the kernel looks in `/tmp/krb5cc_322203108` and finds no ticket — authentication fails.

Both RHEL host mounts and Kubernetes CSI mounts in this document use `User=svc-smb-rw` with `cruid=$(id -u svc-smb-rw)` for consistency and least-privilege operation.

On SSSD-integrated hosts, `cifs-utils` and `keyutils` __handle the upcall plumbing automatically__, and __KCM replaces file-based credential caches__.

### Mount Behavior Notes

- Access is determined by both mode and UID:GID
- Omitting mode defaults to `0755` for all folders and files
- Linux file mode is asymmetrically cosmetic at CIFS: dir/file modes can limit but not grant access
- Setting `setgid` bit (`02775`) at CIFS type mount does **not** set file creator as owner (unlike NFS)

### Additional Considerations

- **SPN registration:** Usually not required for user account accessing a share as client. If issues occur, verify file server has `cifs/fileserver.domain.local` SPN registered.
- **Minimal permissions:** Grant the account only the NTFS and share permissions it needs on the specific share path.
- **Keytab rotation:** When rotating passwords, regenerate keytab and update Kubernetes secrets.
- **Kerberos vs NTLM:** For air-gapped/enterprise environments with domain-joined RHEL hosts, `sec=krb5` with keytab is cleaner than storing credentials.
