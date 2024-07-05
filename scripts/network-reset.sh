#!/usr/bin/env bash
################################################
## DEPRICATED : Use teardown.sh
################################################
[[ "$(whoami)" == 'root' ]] || exit 11

systemctl disable --now firewalld
#systemctl stop iptables
systemctl disable --now nftables

# Define the prefixes commonly used by CNI plugins
CNI_PREFIXES=("CNI-" "KUBE-" "CALICO-" "CILIUM-" "FLANNEL-")

# Tables to clean: iptables tables where CNI rules might exist
TABLES=("filter" "nat" "mangle" "raw")

echo "Starting cleanup of CNI-related chains and rules..."

# Function to flush and delete chains
cleanup_chains() {
    local table=$1
    echo "Processing table: $table"

    for prefix in "${CNI_PREFIXES[@]}"; do
        # List chains in the current table
        chains=$(iptables -t "$table" -S |awk '{print $2}' |grep "^$prefix" || true)

        for chain in $chains; do
            echo "Flushing and deleting chain: $chain in table: $table"
            iptables -t "$table" -F "$chain" 2>/dev/null ||
                echo "=== ERR : Failed to flush chain $chain in $table"
            iptables -t "$table" -X "$chain" 2>/dev/null ||
                echo "=== ERR : Failed to delete chain $chain in $table"
        done
    done
}

# Loop through each table and clean up chains
for table in "${TABLES[@]}"; do
    cleanup_chains "$table"
done

# Reset default policies (optional)
echo "Resetting default policies for all tables..."
for table in "${TABLES[@]}"; do
    iptables -t "$table" -P INPUT ACCEPT 2>/dev/null
    iptables -t "$table" -P FORWARD ACCEPT 2>/dev/null
    iptables -t "$table" -P OUTPUT ACCEPT 2>/dev/null
done

iptables -F    # Flush all rules in the filter table
iptables -X    # Delete all user-defined chains in the filter table
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X
iptables -t security -F
iptables -t security -X

iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT

nft flush ruleset

# echo "" > /etc/sysconfig/nftables.conf
# rm -rf /etc/firewalld
# rm -rf /var/lib/firewalld
# dnf -y reinstall firewalld

systemctl enable --now nftables
#systemctl start iptables
#systemctl enable --now firewalld

# Verify
# iptables -L -n -v
# nft list ruleset
# firewall-cmd --list-all
