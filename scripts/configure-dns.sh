#!/usr/bin/env bash
#################################################
# Configure host for local DNS resolution 
# of its hostname to its public IPv4 address
# for lower DNS latency and higher reliability.
# - Idempotent
#################################################
[[ "$(id -u)" -ne 0 ]] && {
    echo "❌  ERR : MUST run as root" >&2

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

## Add this host's FQDN (and shortname if it differs) to its /etc/hosts file (once).
grep $(ip4) /etc/hosts &&
    exit 0

fqdn="$(hostname -f)"
short="$(hostname -s)"

[[ $fqdn == $short ]] &&
    resolve="$fqdn" ||
        resolve="$fqdn $short"

type -t ip4 > /dev/null 2>&1 &&
    echo "$(ip4) $resolve" |tee -a /etc/hosts &&
        exit

e=22; echo "❌️  ERR : $e : ${BASH_SOURCE##*/} REQUIREs function: ip4" >&2

exit $e

