#!/usr/bin/env bash
# Print MiB of RSS (actual physical memory) used per process
# ARGs: [COMMAND_NAME | N(Number of Top processes)] (Default N=12)
_psrss (){
    e=-e # Every process else that declared ($1)
    [[ "$1" =~ ^-?[0-9]+$ ]] && n=$1 || {
        n=12;[[ -n $1 ]] && unset e
    }

    # Header
    ps -o pid,comm,rss,pmem,pcpu --sort=-rss \
        |awk '{ printf "%-8s %-22s %s[MiB]   %5s %5s\n", $1, $2, $3, $4,$5}' \
        |head -1

    # Top $1 processes by RSS usage
    [[ -n $e ]] &&
        ps $e -o pid,comm,rss,pmem,pcpu --sort=-rss --no-headers \
            |awk '{ printf "%-8s %-20s %6.0f       %5s %5s\n", $1, $2, $3/1024, $4, $5}' \
            |head -$n

    # Process $1
    [[ -n $e ]] ||
        ps -C $1 -o pid,comm,rss,pmem,pcpu --sort=-rss --no-headers \
            |awk '{ printf "%-8s %-20s %6.0f       %5s %5s\n", $1, $2, $3/1024, $4, $5}' \
            |head -$n
}
_psrss "$@" || echo ERR: $?
