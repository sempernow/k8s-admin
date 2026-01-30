## NetApp CIFS export

__SAN__ (iSCSI/FCP LUNs) and __CIFS__ (SMB)

Note __LUNs__ are block-level logical storage volumes presented to servers 
from a **S**torage **A**rea **N**etwork (__SAN__). Hence "`san-cifs`" _reference_.

Available __NetApp ONTAP protocols__:

- `nfs`
- `cifs` (SMB)
- `iscsi`
- `fcp`
- `nvme`

## [`csi-driver-smb.sh`](csi-driver-smb.sh)


Resources

- `PersistentVolume` : [`smb.pv.yaml`](smb.pv.yaml) (If manually provisioned)
- `StorageClass` : [smb.sc.yaml](smb.sc.yaml) (Dynamic provisioning)
- `PersistentVolumeClaim` : [`smb.pvc.yaml`](smb.pvc.yaml)
- Other [examples](https://github.com/kubernetes-csi/csi-driver-smb/tree/master/deploy/example "GitHub : kubernetes-csi/csi-driver-smb/deploy/example")

---

# SMB (CIFS) Protocol 

>How to mount a Windows Share of am NTFS volume from a RHEL host.

If the __NetApp__ export is configured for **`san-cifs`**, 
and you're working with **NTFS-backed file volumes**, 
then the **right move is to access it via SMB/CIFS**, *not* NFS.

## Pod-managed Kerberos Tickets

See [__`csi-krb5-pod-managed.md`__](csi-krb5-pod-managed.md)


## [Kerberos Support for Linux](https://github.com/kubernetes-csi/csi-driver-smb/blob/master/docs/driver-parameters.md#kerberos-ticket-support-for-linux)
## SMB (CIFS) Access from RHEL and Kubernetes


### TL;DR

The csi-driver-smb v1.19.1 has a driver bug preventing the use of Kerberos authentication.

The workaround is a node-level Kerberos setup, which is proven stable;
the ___CSI driver just can't consume it properly___.



### CSI driver limitation

`csi-driver-smb` v1.19.1 cannot handle binary Kerberos credential caches — gRPC marshaling fails with UTF-8 error. Consider filing an issue at https://github.com/kubernetes-csi/csi-driver-smb/issues.

---

## 🔐 Permissions & ACLs

CIFS access **honors NTFS ACLs** directly. That means:

* No `UID/GID` translation weirdness.
* If your NetApp share gives `svc_reader` read-only access to a folder, that's what you’ll get.
* You can even access extended NTFS attributes if needed.

---

## ⚠️ Common Pitfalls

| Symptom                              | Cause                                       | Fix                                                   |
| ------------------------------------ | ------------------------------------------- | ----------------------------------------------------- |
| `mount error(13): Permission denied` | Bad credentials or SMB version mismatch     | Try `vers=2.1` or `vers=3.0`                          |
| `mount: wrong fs type, bad option`   | Missing `cifs-utils`                        | Install with `dnf install cifs-utils`                 |
| Write fails                          | Share is read-only or NTFS ACL denies write | Adjust NetApp ACLs                                    |
| Domain user not working              | NetApp requires Kerberos or mapped account  | Use IP + correct domain or try with keytab/krb5 setup |

---

## ✅ When to Prefer CIFS Over NFS

| Situation                      | Use CIFS? | Use NFS?                |
| ------------------------------ | --------- | ----------------------- |
| Volume is NTFS                 | ✅ Yes     | ❌ Complicated           |
| Accessing from RHEL + Windows  | ✅ Yes     | ❌ Complex mappings      |
| You want to use Windows ACLs   | ✅ Yes     | ❌ Not supported via NFS |
| You’re accessing a LUN         | ❌ No      | ❌ No — use iSCSI        |
| NetApp exports only `san-cifs` | ✅ Yes     | ❌ Not supported         |

---

## 🧩 TL;DR

If NetApp volume is `san-cifs` and formatted as NTFS, 
**RHEL access is by SMB/CIFS**, *not* NFS.
---

# AD Group Permissions issues at NetApp CIFS server shares

It makes sense once we peel apart how **NetApp ONTAP volumes, protocols, and security styles** interact.


## 🔍 Why Some CIFS Volumes Mount with NFS and Others Don’t

1. **CIFS options**

   * The **SVM (Storage Virtual Machine)** is enabled for *SAN* (iSCSI/FCP LUNs) **and** *CIFS (SMB)*.
   * Whether an individual volume is mountable by NFS depends on whether **NFS is enabled/exported** for that volume, not just the SVM protocol list.

2. **Dual-protocol volumes**
   ONTAP supports **multi-protocol access**: the same volume can be accessed over SMB **and** NFS. This requires:

   * The volume has a **junction-path**.
   * An **export-policy** that allows NFS clients.
   * A **security style** (`unix`, `ntfs`, or `mixed`).

   So if NFS is enabled in the export policy, your RHEL host can `mount -t nfs ...`.
   If not, you’ll get *permission denied* or *no export* errors.

3. **Volumes that don’t mount over NFS**

   * May be LUN-only (pure SAN, no junction path).
   * May lack an export-policy for NFS.
   * May be `ntfs` security style with no UNIX user mapping (NFS clients can’t be mapped to Windows accounts).

---

## 🔐 Why Group Permissions Break (AD Groups vs UNIX Groups)

This is a classic NetApp dual-protocol headache:

* **NTFS Security Style (common for CIFS/SMB shares):**

  * File/folder permissions are controlled by **NTFS ACLs**.
  * NFS clients’ UIDs/GIDs must be **mapped to AD users/groups**.
  * If mappings are missing, NFS clients fall back to “anonymous” (typically `nobody:nobody`). → Permissions fail.

* **Unix Security Style:**

  * File/folder permissions are POSIX mode bits.
  * CIFS clients’ AD users get mapped into UNIX identities.
  * If group memberships don’t translate, Windows clients may lose access.

* **Mixed Security Style:**

  * First access protocol sets the ACL type (NFS → UNIX bits, SMB → NTFS ACLs).
  * Can lead to unpredictable behavior if both access methods are used.

So the “AD group permissions issue” you see from RHEL is almost certainly a **name-mapping gap**:

* Your UNIX GID from RHEL doesn’t map to the correct AD group.
* NetApp enforces NTFS ACLs, but can’t validate your Linux identity.

---

## ✅ How to Diagnose in ONTAP

On the NetApp CLI:

1. Check volume security style:

   ```bash
   volume show -vserver <svm> -volume <vol> -fields security-style
   ```

2. Check export policy for NFS:

   ```bash
   volume show -vserver <svm> -volume <vol> -fields policy
   export-policy rule show -vserver <svm> -policyname <policy>
   ```

3. Check name mapping:

   ```bash
   vserver name-mapping show -vserver <svm>
   ```

4. Test mapping of a user:

   ```bash
   vserver security login mapping show -vserver <svm> -authmethod nsswitch -user <unix-user>
   ```

---

## 🛠 Fixes / Workarounds

1. **If you want stable NFS access from RHEL:**

   * Ask NetApp admin to set **security-style to unix or mixed** on the volume.
   * Ensure export-policy explicitly allows your RHEL subnet.
   * Create **name-mapping rules** (`unix → win`) for users and groups.

2. **If CIFS/NTFS ACLs are required (Windows-first workloads):**

   * Prefer SMB/CIFS mounts from RHEL (`cifs-utils`) — these honor NTFS ACLs directly, no UID/GID mapping headaches.

3. **If you must use NFS for Linux pods in Kubernetes:**

   * Confirm the NetApp admin sets `mixed` security-style + proper name mappings.
   * Or: use `csi-driver-smb` in Kubernetes to mount SMB shares directly (avoiding ACL mismatch).

---

## 🧩 TL;DR

* Some CIFS volumes export over NFS because their **export policy + junction path + multiprotocol config** allow it. Others don’t.
* AD group permission issues arise because **NTFS ACLs require Windows SID mapping** — RHEL’s UID/GID doesn’t match unless NetApp has **name mappings** configured.
* If you control the NetApp config, choose:

  * **NFS + UNIX security style** → for Linux-friendly access.
  * **SMB + NTFS security style** → for Windows/AD-friendly access.

---

# Fix mappings issues


**NetApp CLI commands** you’d need to check or fix name mappings, so that your RHEL users/groups map correctly to AD groups. That’s usually the missing link when NFS “works but has permissions issues.”


**How NetApp ONTAP handles identity and permissions for NFS clients**, 
and the commands you can use to troubleshoot/fix:


# 🔍 The Core Problem

When a **RHEL client mounts an NTFS-security-style NetApp volume over NFS**, the client sends a **UID/GID**.
NetApp has to translate that UID/GID into a **Windows SID** (because NTFS ACLs are SID-based).

* If the mapping succeeds → access granted/denied based on NTFS ACLs.
* If the mapping fails → user is mapped to `pcuser` or `nobody`, and AD group permissions don’t apply.

That’s why you see **AD group permission issues from RHEL**.

---

# ✅ Step 1: Check Volume Security Style

```bash
volume show -vserver <SVM> -volume <VOL> -fields security-style
```

* If it says `ntfs`: NFS access relies on **UNIX→Windows name mapping**.
* If it says `unix`: NFS access uses POSIX mode bits, no SID mapping needed.
* If it says `mixed`: First protocol (NFS or SMB) sets the ACL type.

---

# ✅ Step 2: Check Export Policy

Make sure your RHEL host/subnet is allowed:

```bash
volume show -vserver <SVM> -volume <VOL> -fields policy
export-policy rule show -vserver <SVM> -policyname <POLICY>
```

Look for:

* `protocol nfs` included
* `rorule` / `rwrule` not set to `never`
* `superuser` rule if root access is needed

---

# ✅ Step 3: Inspect Name Mappings

Show current mappings:

```bash
vserver name-mapping show -vserver <SVM>
```

You might see something like:

```
Vserver: lime_svm
Direction: unix-win
Position: 1
Pattern: (.*)
Replacement: LIME\unix_$1
```

That means any UNIX user is mapped to `LIME\unix_<username>`.

---

# ✅ Step 4: Test a User Mapping

From ONTAP:

```bash
vserver security login mapping show -vserver <SVM> -authmethod nsswitch -user <unix-user>
```

Example:

```bash
vserver security login mapping show -vserver lime_svm -authmethod nsswitch -user gary
```

Expected result: a Windows user (SID) is returned.

If it fails → mapping is missing.

---

# ✅ Step 5: Create/Adjust Name Mapping Rules

### Example: Map all UNIX users to a single AD account

```bash
vserver name-mapping create -vserver lime_svm -direction unix-win \
  -position 1 -pattern .* -replacement LIME\nfsuser
```

### Example: Map a specific UNIX user → AD user

```bash
vserver name-mapping create -vserver lime_svm -direction unix-win \
  -position 2 -pattern gary -replacement LIME\garyd
```

### Example: Map UNIX group → AD group (for GID alignment)

```bash
vserver name-mapping create -vserver lime_svm -direction unix-win \
  -position 3 -pattern :1001 -replacement LIME\DevOpsTeam
```

---

# ✅ Step 6: Verify Group Membership

From ONTAP:

```bash
vserver security file-directory show -vserver lime_svm -path /vol/ntfsvol/testfile -expand-groups
```

This shows effective permissions, including AD groups, for the mapped user.

---

# ⚠️ Important Notes

* **Order matters** → NetApp evaluates name-mapping rules in order (`position`).
* **Regex patterns** → `.*` matches everything, specific rules should be placed higher.
* **Fallback user** → If no match, user maps to `pcuser` (by default).

---

# 🧩 TL;DR

1. Confirm **volume security style** (`ntfs` → mapping required).
2. Confirm **export policy** allows NFS clients.
3. Inspect **name-mapping rules** (`vserver name-mapping show`).
4. Test mappings (`vserver security login mapping show`).
5. Add rules if missing (`vserver name-mapping create`).
6. Verify access with `file-directory show -expand-groups`.

