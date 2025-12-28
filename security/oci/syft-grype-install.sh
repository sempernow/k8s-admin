#!/usr/bin/env bash
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh |
    sudo sh -s -- -b /usr/local/bin
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh |
    sudo sh -s -- -b /usr/local/bin
