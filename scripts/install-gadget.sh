#!/usr/bin/env bash
# Inspektor Gadget : Install
# https://github.com/inspektor-gadget/inspektor-gadget

kubectl version >/dev/null || exit 100
kubectl krew version >/dev/null || exit 101

kubectl krew install gadget
kubectl gadget deploy
kubectl gadget run trace_open:latest

exit $? 
#######
