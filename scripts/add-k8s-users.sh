#!/usr/bin/env bash
################################################################
# Dynamically add system user/group for each container UID/GID.
# - Run on all nodes that allow workloads.
# - Captures pod-level and container-level securityContext.
# - Includes initContainers and ephemeralContainers.
################################################################
# v0.0.2-claude.ai
set -euo pipefail

[[ "$(id -u)" -ne 0 ]] && {
    echo "❌  ERR: Must run as root" >&2
    exit 1
}

for cmd in yq kubectl; do
    command -v "$cmd" >/dev/null || {
        echo "❌  ERR: $cmd not found" >&2
        exit 2
    }
done

kubeconfig="${1:-/etc/kubernetes/admin.conf}"
[[ -f "$kubeconfig" ]] || {
    echo "❌  ERR: kubeconfig not found: $kubeconfig" >&2
    exit 3
}

echo "=== Fetching pod securityContexts..."

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

if ! kubectl get pod -A --kubeconfig="$kubeconfig" -o yaml > "$tmpfile.raw" 2>&1; then
    echo "❌  ERR: kubectl failed:" >&2
    cat "$tmpfile.raw" >&2
    exit 4
fi

# Extract UIDs/GIDs from pod-level, containers, initContainers, ephemeralContainers
yq '[
  .items[] | (
    (.spec.securityContext | select(.) | {"uid":.runAsUser,"gid":.runAsGroup}),
    (.spec.containers[]?.securityContext | select(.) | {"uid":.runAsUser,"gid":.runAsGroup}),
    (.spec.initContainers[]?.securityContext | select(.) | {"uid":.runAsUser,"gid":.runAsGroup}),
    (.spec.ephemeralContainers[]?.securityContext | select(.) | {"uid":.runAsUser,"gid":.runAsGroup})
  ) | select(.uid != null or .gid != null)
] | unique' "$tmpfile.raw" > "$tmpfile"

rm -f "$tmpfile.raw"

# Get local UID/GID boundaries (skip AD/LDAP ranges)
maxLocalUID="$(awk '/^UID_MAX/ {print $2}' /etc/login.defs)"
maxLocalGID="$(awk '/^GID_MAX/ {print $2}' /etc/login.defs)"
: "${maxLocalUID:=60000}"
: "${maxLocalGID:=60000}"

echo "=== Local UID max: $maxLocalUID, GID max: $maxLocalGID"

echo "=== Adding users for container UIDs..."
while read -r uid; do
    [[ "$uid" == "null" || -z "$uid" ]] && continue
    (( uid > maxLocalUID )) && continue
    
    if id "k8s-${uid}" &>/dev/null; then
        #echo "  Exists: k8s-${uid}"
        continue
    fi
    
    if useradd --system --no-create-home --shell /usr/sbin/nologin "k8s-${uid}" --uid "$uid" 2>/dev/null; then
        usermod --lock "k8s-${uid}"
        echo "  Added: k8s-${uid} (uid=$uid)"
    fi
done < <(yq '.[].uid' "$tmpfile" 2>/dev/null | sort -nu)

echo "=== Adding groups for container GIDs..."
while read -r gid; do
    [[ "$gid" == "null" || -z "$gid" ]] && continue
    (( gid > maxLocalGID )) && continue
    
    if getent group "k8s-${gid}" &>/dev/null; then
        #echo "  Exists: k8s-${gid}"
        continue
    fi
    
    # Check if GID already taken by another group
    if getent group "$gid" &>/dev/null; then
        existing="$(getent group "$gid" | cut -d: -f1)"
        #echo "  Skipped: GID $gid already used by group '$existing'"
        continue
    fi
    
    if groupadd --system "k8s-${gid}" --gid "$gid" 2>/dev/null; then
        echo "  Added: k8s-${gid} (gid=$gid)"
    fi
done < <(yq '.[].gid' "$tmpfile" 2>/dev/null | sort -nu)

echo ""
echo "=== List k8s-* users in /etc/passwd:"
grep '^k8s-' /etc/passwd || echo "  (none)"

echo ""
echo "=== List k8s-* groups in /etc/group:"
grep '^k8s-' /etc/group || echo "  (none)"

echo ""

exit $?
#######

#!/usr/bin/env bash
################################################################
# Dynamically add system user/group for each container UID/GID.
# - Run on all nodes that allow workloads.
################################################################
## v0.0.1

[[ "$(id -u)" -ne 0 ]] && {
    echo "❌  ERR : MUST run as root" >&2
    
    exit 1
}
type yq >/dev/null || exit 2

kubeconfig=${1:-/etc/kubernetes/admin.conf}
list=ctnr_uid_gid_list.yaml
kubectl get pod -A --kubeconfig=$kubeconfig -o yaml |
    yq '.items[].spec.containers[].securityContext 
          |select(.runAsUser != null or .runAsGroup != null) 
          | [{"uid":.runAsUser,"gid":.runAsGroup}]
    ' > $list

## No need to add non-local (AD) UID/GID
maxLocalUID="$(grep '\bUID_MAX\b' /etc/login.defs |awk '{printf $2}')"
maxLocalGID="$(grep '\bGID_MAX\b' /etc/login.defs |awk '{printf $2}')"

echo === Add Orphan UIDs
## Add GID on orphan UID so that probability of mixed contexts (non-k8s GID) is lower.
yq .[].uid $list |sort -nu |xargs -IX /bin/bash -c '
    [[ $1 == "null" ]] && exit 
    [[ $0 && ( $1 -gt $0 ) ]] && exit
    useradd --system --no-create-home --shell /usr/sbin/nologin "k8s-$1" --uid "$1" 2>/dev/null &&
        echo "  Added: k8s-$1" &&
            usermod --lock k8s-$1 ||
                true
    groupadd --system "k8s-$1" --gid "$1" 2>/dev/null || true
' "$maxLocalUID" X

echo === Add Orphan GIDs
yq .[].gid $list |sort -nu |xargs -IX /bin/bash -c '
    [[ $1 == "null" ]] && exit 
    [[ $0 && ( $1 -gt $0 ) ]] && exit
    groupadd --system "k8s-$1" --gid "$1" 2>/dev/null &&
        echo "  Added: k8s-$1" ||
            true
' "$maxLocalGID" X

echo '=== List k8s-* UIDs'
grep k8s /etc/passwd

echo '=== List k8s-* GIDs'
grep k8s /etc/group

