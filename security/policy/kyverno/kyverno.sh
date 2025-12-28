#!/usr/bin/env bash
# REF: https://kyverno.io/docs/installation/methods/#high-availability-installation

v=v1.11.1
wget -O kyverno.$v.yaml https://github.com/kyverno/kyverno/releases/download/$v/install.yaml &&
    echo kubectl apply -f kyverno.$v.yaml
