# Scan OCI image for CVEs


## Trivy

```bash
# Generate SBOM of OCI image
image=openeuler/openeuler:24.03-lts-sp2
trivy image --scanners vuln --format spdx-json -o sbom.sdx.json $image
# or
trivy image --scanners vuln --format cyclonedx -o sbom.cdx.json $image 

# Scan/Audit SBOM file for CVEs of declared severities
sbom=sbom.cdx
trivy sbom --severity CRITICAL,HIGH --format json -o $sbom.audit.json $sbom.json

```

## Syft / Grype

- [__`syft`__](https://github.com/anchore/syft "GitHub.com/Anchore/") (SBOM) 
- [__`grype`__](https://github.com/anchore/grype "GitHub.com/Anchore/") (CVEs)

```bash
# Install 
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh |
    sudo sh -s -- -b /usr/local/bin
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh |
    sudo sh -s -- -b /usr/local/bin
```

```bash
syft $img -o json |grype --fail-on high
```

```bash
img=openeuler/openeuler:24.03-lts-sp2
sbom="${img////}"
name_tag="${sbom//:/_}"
sbom="$name_tag.sbom.json"

# Capture CycloneDX SBOM
syft $img --output cyclonedx-json="$sbom"

# Scan the SBOM 
grype $sbom --output cyclonedx-json --file $name_tag.cdx.json

```
- `--output`, `-o` : `json`, `cyclonedx-json`, `spdx-json`
