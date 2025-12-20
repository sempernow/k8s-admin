#!/usr/bin/env bash
########################################
# Configure kernel for local DNS
# - Idempotent
########################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "⚠️  ERR : MUST run as root" >&2

    exit 11
}

ip4(){
    ip -c --color=never -4 -brief addr "$@" |
        command grep -v -e lo -e docker |
            command grep UP |
                head -n1 |
                    awk '{print $3}' |
                        cut -d'/' -f1
}
export -f ip4

## Add FQDN and shortname of host to its /etc/hosts file, if not there already.
grep $(ip4) /etc/hosts && exit 0

type -t ip4 &&
    echo "$(ip4) $(hostname -f) $(hostname -s)" |tee -a /etc/hosts &&
        exit

echo "⚠️  ERR : ${BASH_SOURCE##*/} REQUIREs function: ip4" >&2

exit 22

