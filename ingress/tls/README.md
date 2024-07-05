# TLS

## AD CS 

Certificate issuance under Microsoft's manual PKI hellscape

## [Automated TLS Management (Enterprise Grade)](https://chatgpt.com/share/6897a869-d390-8009-b873-da33b20e8e0b "ChatGPT 5")

- [__cert-manager__](https://github.com/cert-manager)
- Private Issuers (Backends):
    - Smallstep [__`step-ca`__](https://smallstep.com/docs/step-ca/ "smallstep.com")  
    An online CA for secure, automated X.509 and SSH certificate management. It's the server counterpart to `step` CLI. Run step-ca (internal ACME) + `step-issuer` or use `cert-manager`’s ACME issuer pointed at `step-ca`. Provides air-gapped ACME + tight Kubernetes integration.
        - Generate TLS certificates for private infrastructure using the ACME protocol.
        - Automate TLS certificate renewal.
        - Add Automated Certificate Management Environment (ACME) support to a legacy subordinate CA.
        - Issue short-lived SSH certificates via OAuth OIDC single sign on.
        - Issue customized X.509 and SSH certificates.
    - __Hashicorp Vault PKI__ | [__OpenBao PKI__](https://openbao.org/docs/secrets/pki/)
    - __Venafi TLS Protect for Kubernetes__ (the commercial successor to __Jetstack__ Secure): central policy/visibility across clusters and CAs (public or private). If you want enterprise governance and inventory at scale, this is the “batteries-included” option.

### Recommendations 

__Per environment__:

- Air-gapped / Regulated:   
  __cert-manager + Vault PKI__ (__or step-ca__ if you want ACME everywhere). Both are proven, policy-driven, and keep keys/CAs entirely under your control. 
- Large enterprise needing fleet-wide governance:   
  V__enafi TLS Protect for Kubernetes__ integrated with __cert-manager__ (__or Venafi issuer__) for policy, workflows, and inventory. 
- AWS-only edge:   
  ACM + AWS Load Balancer Controller for public ingress, optionally cert-manager + Vault/step-ca for internal services and mTLS.

---

## [ACME](https://en.wikipedia.org/wiki/Automatic_Certificate_Management_Environment) 

__Automated Certificate Management Environment__ (ACME) 

An ACME server is a trusted CA endpoint 
that issues certs after validating the 
client requestor has domain control.

* **Origin:** ACME is an IETF standard (RFC 8555) created by the __Let's Encrypt__ project to automate the issuance of publicly trusted TLS certificates.
* **Purpose:** Automates domain-validated (DV) certificate requests and renewals from a Certificate Authority (CA).
* **Focus:**
    * Primarily for *internet-facing* services.
    * Proves control of DNS names via challenges  
    (HTTP-01, DNS-01, TLS-ALPN-01) 
    to prove the requestor has domain control.
    * Result: an X.509 certificate signed by a public CA.
* __Private/Internal ACME Servers__
    * Smallstep Certificates (open-source & enterprise versions)
    * HashiCorp Vault (with ACME support)
    * Boulder (OSS version of __Let's Encrypt's__ CA software).

 