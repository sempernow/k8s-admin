#!/usr/bin/env bash
#######################################################################
# Join THIS HOST into cluster as control node
# 
# ARGs: THIS_NODE_INTERFACE  K8S_KUBEADM_CONF_JOIN
#
# REQUIREs: discovery file at target host ~/ : K8S_JOIN_KUBECONFIG
#######################################################################
[[ -r $2 ]] || exit 88
[[ -r discovery.yaml ]] || exit 99

# Must run `kubeadm join` as root 
[[ "$(whoami)" == 'root' ]] || exit 11

sed -i "s,THIS_NODE_NAME,$(hostname),g" $2 || exit 22
ip="$(command ip -4 -brief addr show dev $1 |awk '{print $3}' |cut -d'/' -f1)"
[[ $ip ]] && sed -i "s,THIS_NODE_IP,$ip,g" $2 || exit 23

clear 
cat $2

# Join requires valid (ephemeral) PKI.
kubeadm join -v5 --config $2
