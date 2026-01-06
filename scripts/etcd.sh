#!/usr/bin/env bash
##############################################
# etcd : Run as root on any K8s node.
#
# ARGs: METHOD [/path/to/backup/if/snapshot]
##############################################
[[ "$(id -u)" != "0" ]] && {
    echo "❌ ERR : MUST run as root" >&2

    exit 1
}

_etcdctl(){
    ETCDCTL_API=3 etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt \
        --cert=/etc/kubernetes/pki/etcd/server.crt \
        --key=/etc/kubernetes/pki/etcd/server.key \
        "$@" 
}
export -f _etcdctl

status(){
    for node in $@; do list="$list,https://$node:2379"; done
    _etcdctl --endpoints="${list/,/}" --write-out=table endpoint status

}
local(){
    for cmd in 'endpoint status' 'endpoint health --cluster' 'member list'; do
        echo "ℹ️ $cmd"
        _etcdctl --endpoints=https://127.0.0.1:2379 --write-out=table $cmd 
    done
}
defrag(){
    _etcdctl defrag
}
snapshot(){
    ## Source : pod.spec.volumes[].hostPath: /var/lib/etcd
    [[ $1 ]] && to="$1" || {
        mkdir -p /opt/backup/etcd
        cp --preserve=mode,timestamps etcd.sh /opt/backup/etcd/
        to="/opt/backup/etcd/etcd.snapshot.$(hostname).$(date -Id)"
    }
    _etcdctl snapshot save "$to" || return 11
    [[ -f $to ]] || return 22
    etcdutl snapshot status "$to" |tee "$to.status" || return 33
}
restore(){
    echo "⚠️ Method NOT IMPLEMENTED" >&2

    return 99
    
    # Total restore to a cluster having a single control-node with etcd WIPED beforehand
    db=/tmp/etcd/recovery/etcd.leader.2025-08-11.db
    host=a1
    ip=192.168.11.101
    ETCDCTL_API=3 etcdctl snapshot restore "$db" \
        --name "$host" \
        --data-dir /var/lib/etcd \
        --initial-advertise-peer-urls "https://$ip:2380" \
        --initial-cluster "$host=https://$ip:2380" \
        --initial-cluster-token "etcd-cluster-$host"
}

# etcd performs frequent fsync ops, especially on the WAL, to guarantee data durability. 
# High fsync latency (especially p99 and beyond) directly impacts:
# - Write latency (especially for PUT, CREATE, DELETE)
# - Raft election stability (slow followers can trigger unnecessary elections)
# - Cluster throughput
# Docs at etcd recommend: fsync p99 < 2ms (2000µs)

p99_1(){
    # Test volume endurance, and handling of sustatined load
    dir=${1:-/var/lib/etcd}
    echo "ℹ️  @ $dir : Want : fsync 99.0th < 2000 (usec)"
    file=wal.text
    fio --name=etcd-fsync \
        --directory=$dir \
        --size=256m \
        --filename=$file \
        --bs=8k \
        --ioengine=libaio \
        --numjobs=1 \
        --fdatasync=1 \
        --iodepth=1 \
        --rw=write \
        --runtime=120 \
        --time_based=1 \
        --group_reporting=1 \
        --lat_percentiles=1 \
        --percentile_list=99,99.5,99.9 \
        |tee fio.etcd.fsync.p99.log

    rm $dir/$file
}
p99_2(){
    # Test sync behavior
    dir=${1:-/var/lib/etcd}
    echo "ℹ️  @ $dir : Want : fsync 99.0th < 2000 (usec)"
    file=wal.text
    fio --name=etcd-fsync \
        --rw=write \
        --directory=$dir \
        --filename=$file \
        --bs=2300 \
        --size=64m \
        --ioengine=sync \
        --fdatasync=1 \
        --runtime=60 \
        --time_based=1 \
        --numjobs=1 \
        --percentile_list=99,99.5,99.9 \
        --lat_percentiles=1 \
        |tee fio.etcd.fsync.p99.log

    rm $dir/$file
}
etcdLVM(){
    blk=sdb
    dev=/dev/$blk
    pv=${dev}1
    vg=static
    lv=etcd
    
    # Abort if block device does not exist
    lsblk -ndo NAME,SIZE,TYPE,MODEL |grep -q "\b$blk\b" ||
        exit 11

    # Abort if PV is mounted
    mount |grep -q $pv &&
        exit 22

    # 0. Partition device if not already
    isParted(){ lsblk -no TYPE "$pv" |grep part; }
    isParted || {
        parted -s $dev mklabel gpt
        parted -s $dev mkpart pv 1MiB 100%
        parted -s $dev set 1 lvm on
        partprobe "$dev"
        # Allow udev to catch up
        while ! isParted; do sleep 1 >/dev/null; done 
        udevadm settle
    }

    # 1. Create PV if not already
    pvs "$pv" ||
        pvcreate $pv

    # 2. Create VG if not already
    vgs "$vg" ||
        vgcreate "$vg" "$pv"

    # 3. Create LV if not already
    lvs "$vg/$lv" ||
        lvcreate -n "$lv" -l 100%FREE "$vg"

    # 4. Format with XFS if not already
    blkid "/dev/$vg/$lv" |grep 'TYPE="xfs"' ||
        mkfs.xfs /dev/$vg/$lv

    # 5. Mount it / Swap old to tmp
    # See LOG : "Create LVM/XFS volume at node (Guest VM)"
    tmpMount(){
        # Temporary mount 
        tmp=/mnt/etcd-tmp
        mkdir -p $tmp
        mount /dev/$vg/$lv $tmp
        # Copy data (with etcd stopped)
        src=/var/lib/etcd
        rsync -aHAX --numeric-ids --inplace --delete --fsync \
            $src/  $tmp/

        sync -f $tmp

        # Fix permissions
        chown -R root:root $tmp
        chmod 700 $tmp/member 2>/dev/null || true
    }
}
etcdLVMTeardown(){
    blk=sdb
    dev=/dev/sdb
    pv=${dev}1
    vg=static
    lv=etcd
    mnt=/var/lib/etcd

    # Abort if block device does not exist
    lsblk -ndo NAME,SIZE,TYPE,MODEL |grep -q "\b$blk\b" ||
        exit 11

    # Abort if PV is mounted
    mount |grep -q $pv &&
        exit 22

    # 1. Unmount the LV
    #umount $mnt 2>/dev/null || true

    # 2. Disable swap, else no-op, then deactivate LV
        # How to check for swaps
        #cat /proc/swaps
        #swapon --summary
    swapoff /dev/$vg/$lv 2>/dev/null || true
    lvchange -an /dev/$vg/$lv

    # 3. Delete the Logical Volume
    lvremove -y /dev/$vg/$lv

    # 4. Remove the Volume Group
    vgremove -y $vg

    # 5. Remove the Physical Volume
    pvremove $pv

    # 6. Wipe filesystem signatures and partition table
    wipefs -a $pv
    wipefs -a $dev 

    # 7. Zap partition table completely (optional and destructive)
    sgdisk --zap-all $dev
    partprobe $dev

    # Validate : Want no trace of that LVM construct
    lsblk $dev
    pvs; vgs; lvs
    blkid
}

"$@"

exit
####

# Confirm cluster has quorum first
# - ERRORS column empty
# - LEADER : 1 true; others false
_etcdctl(){
    etcdctl \
        --cacert /etc/kubernetes/pki/etcd/ca.crt \
        --cert /etc/kubernetes/pki/etcd/server.crt \
        --key /etc/kubernetes/pki/etcd/server.key \
        "$@"
}
export -f _etcdctl 
export eps="https://a1:2379,https://a2:2379,https://a3:2379"
## --endpoints=https://127.0.0.1:2379

_etcdctl --endpoints="$eps" endpoint status -w table

## Verify all endpoints are healthy
_etcdctl --endpoints="$eps" endpoint health -w table

## Verify all voters present (and usually not learners)
_etcdctl --endpoints="$eps" member list -w table

## Remove member by ID
id=''
_etcdctl --endpoints=https://127.0.0.1:2379 member remove $id 

## Transfer lead to another member
LEADER_EP="https://$leader:2379"    # Endpoint of the leader.
TRANSFEREE_ID="1234567890abcdef"    # Member ID of the target; a healthy follower.
_etcdctl --endpoints="$LEADER_EP" move-leader "$TRANSFEREE_ID"

