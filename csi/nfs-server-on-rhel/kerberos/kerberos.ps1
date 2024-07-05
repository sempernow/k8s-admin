# @ PowerShell @ AD KDC (Key Distribution Center)
# Regards tickets of this host only; not other (RHEL) hosts under this DC. 
Get-Service KDC             # Verify Kerberos KDC is running
klist C:\\                  # Use single backslash at PowerShell
klist tickets               # List all tickets 

nslookup -type=SRV _kerberos._tcp.lime.lan # Verify AD DNS records for Kerberos
dir \\dc1.lime.lan\sysvol # Verify host is using Kerberos to authenticate

# Delete and then create new tickets at AD KDC 
# to delete all tickets at all (RHEL) hosts of the domain.
# This does not prevent login, and so useful 
# for recreating kerberos tickets at those hosts too.
klist purge               # Delete all tickets
klist get krbtgt/LIME.LAN # Create ticket (two; primary and backup)
klist get krbtgt/LIME.LAN /renew # Create ticket without using local cache

# Create keytab file for RHEL NFS server
# (This should be handled automatically by a realm and sssd)
ktpass -out "C:\nfs_a0.keytab" `
    -princ "nfs/a0.lime.lan@LIME.LAN" `
    -mapuser "LIME\A0$" `
    -crypto AES256-SHA1 `
    -ptype KRB5_NT_PRINCIPAL `
    -pass +rndpass

klist -k C:\nfs_a0.keytab   # Verify : List keys of the keytab

# Verify SPN (Service Principal Name) exists
setspn -Q nfs/a0.lime.lan