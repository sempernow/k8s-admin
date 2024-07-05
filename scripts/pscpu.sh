#!/usr/bin/env bash
# Snapshot of processes sorted by %CPU
# ARGs: [COMMAND_NAME | N(Number of Top processes)] (Default N=12)
_pscpu (){
    e=-e # Every process else that declared ($1)
    [[ "$1" =~ ^-?[0-9]+$ ]] && n=$1 || {
        n=12;[[ -n $1 ]] && unset e
    }

    # Header
    ps -o pid,comm,rss,pmem,pcpu --sort=-pcpu \
        |awk '{ printf "%-8s %-22s %s[MiB]   %5s %5s\n", $1, $2, $3, $4,$5}' \
        |head -1

    # Top $1 (else default) number of processes by CPU usage
    [[ -n $e ]] &&
        ps $e -o pid,comm,rss,pmem,pcpu --sort=-pcpu --no-headers \
            |awk '{ printf "%-8s %-20s %6.0f       %5s %5s\n", $1, $2, $3/1024, $4, $5}' \
            |head -$n

    # Else process $1
    [[ -n $e ]] ||
        ps -C $1 -o pid,comm,rss,pmem,pcpu --sort=-pcpu --no-headers \
            |awk '{ printf "%-8s %-20s %6.0f       %5s %5s\n", $1, $2, $3/1024, $4, $5}' \
            |head -$n
}
_pscpu "$@" || echo ERR: $?
