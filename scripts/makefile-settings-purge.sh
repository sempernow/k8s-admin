#!/usr/bin/env bash
cat <<-EOH |tee Makefile.bootstrap.settings
## This file is DYNAMICALLY GENERATED at make recipes
export K8S_CERTIFICATE_KEY ?=
export K8S_CA_CERT_HASH    ?=
export K8S_BOOTSTRAP_TOKEN ?=
EOH
