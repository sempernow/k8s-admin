#!/usr/bin/env bash
###########################################################
# SELinux : Set to Permissive|Enforcing (now and persist)
# - Idempotent
#
# ARGs: [Enforcing|Permissive(Default)]
###########################################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "⚠️  ERR : MUST run as root" >&2

    exit 11
}
conf=/etc/selinux/config
disabled=$(grep SELINUX=disabled $conf)
permissive=$(grep SELINUX=permissive $conf)
enforcing=$(grep SELINUX=enforcing $conf)

e(){
    [[ $permisive || $disabled ]] || return
    setenforce 1 # set to Enforcing : Unreliable and does NOT persist.
    sed -i -e 's/^SELINUX=disabled/SELINUX=eforcing/' $conf
    sed -i -e 's/^SELINUX=permissive/SELINUX=enforcing/' $conf
}
p(){
    [[ $enforcing || $disabled ]] || return
    setenforce 0 # set to Permissive : Unreliable and does NOT persist.
    sed -i -e 's/^SELINUX=disabled/SELINUX=permissive/' $conf
    sed -i -e 's/^SELINUX=enforcing/SELINUX=permissive/' $conf
}
export -f e
export -f p

was=$(getenforce)
want=$1
[[ $1 && $(echo $1 |grep -i $want) ]] && e || p
now=$(getenforce)

echo "🔍  SELinux : $(getenforce)"

[[ ${now} =~ $was ]] &&
    echo '✅  NO CHANGE to SELinux config' ||
        echo '🚧  REBOOT required for some SELinux CHANGEs to take effect.'
