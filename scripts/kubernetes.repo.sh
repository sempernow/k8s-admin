#!/usr/bin/env bash
ver="v${1:-1.30}"
cat << EOF |sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/$ver/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/$ver/rpm/repodata/repomd.xml.key
EOF

