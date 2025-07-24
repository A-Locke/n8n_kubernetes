# OCI Infra Pipeline

This repository provides a GitHub Actions CI/CD pipeline to deploy an Oracle Cloud Infrastructure (OCI) Kubernetes cluster, install components (Cert‑Manager, Ingress‑Nginx, PostgreSQL, pgAdmin, n8n), and provision a WireGuard VPN for secure access.

## Table of Contents

* [Prerequisites](#prerequisites)
* [Generating Keys & Base64 Encoding](#generating-keys--base64-encoding)

  * [OCI API Key](#oci-api-key)
  * [SSH Keys](#ssh-keys)
  * [WireGuard Keys](#wireguard-keys)
* [Creating GitHub Secrets](#creating-github-secrets)
* [Pipeline Overview](#pipeline-overview)

  * [Terraform Apply Job](#terraform-apply-job)
  * [Helm Install Charts Job](#helm-install-charts-job)
  * [Post-Helm VPN Provision Job](#post-helm-vpn-provision-job)
* [Triggering the Workflow](#triggering-the-workflow)
* [Next Steps](#next-steps)

---

## Prerequisites

1. **OCI account** with:

   * A compartment for resources
   * Object Storage bucket and namespace
   * Cloud Shell or local `oci` CLI configured
2. **GitHub repository** with this code
3. **kubectl**, **helm**, **terraform** installed locally for testing
4. **PowerShell** (Windows) or **bash** (Linux/macOS) to generate and encode keys

---

## Generating Keys & Base64 Encoding

All private and public key files must be stored as Base64 strings in GitHub Actions secrets.

### OCI API Key

1. In the OCI console, go to **Identity & Security → Users**.
2. Click your user → **API Keys → Add API Key**.
3. Download the private key (e.g., `oci_api_key.pem`).

**Base64 encode (bash)**:

```bash
base64 -w 0 oci_api_key.pem > oci_api_key_b64.txt
```

**Base64 encode (PowerShell)**:

```powershell
Get-Content .\oci_api_key.pem -Encoding byte | \n  [Convert]::ToBase64String(\$\_) | Out-File oci_api_key_b64.txt -NoNewline
```

### SSH Keys for OKE & VPN

Generate separate key pairs for Kubernetes node SSH and VPN instance SSH:

```bash
ssh-keygen -t rsa -b 4096 -f oke_ssh_key  -N ""
ssh-keygen -t rsa -b 4096 -f vpn_ssh_key -N ""
```

Encode both **public** and **private** keys:

```bash
base64 -w 0 oke_ssh_key.pub  > oke_ssh_key_b64.txt
base64 -w 0 vpn_ssh_key.pub  > tf_vpn_ssh_key_b64.txt
base64 -w 0 vpn_ssh_key      > tf_vpn_private_key_b64.txt
```

PowerShell equivalent:

```powershell
# .pub files
Get-Content .\oke_ssh_key.pub -Encoding byte | [Convert]::ToBase64String(\$\_) | Out-File oke_ssh_key_b64.txt -NoNewline
# private
Get-Content .\vpn_ssh_key -Encoding byte | [Convert]::ToBase64String(\$\_) | Out-File tf_vpn_private_key_b64.txt -NoNewline
```

### WireGuard Keys

```bash
wg genkey  | tee wg_private.key | wg pubkey > wg_public.key
wg genkey  | tee client_private.key | wg pubkey > client_public.key
```

Encode:

```bash
base64 -w 0 wg_private.key     > vpn_wireguard_priv_key_b64.txt
base64 -w 0 wg_public.key      > vpn_wireguard_pub_key_b64.txt
base64 -w 0 client_private.key > vpn_client_private_key_b64.txt
base64 -w 0 client_public.key  > vpn_client_public_key_b64.txt
```

PowerShell:

```powershell
Get-Content .\wg_private.key -Encoding byte | [Convert]::ToBase64String(\$\_) | Out-File vpn_wireguard_priv_key_b64.txt -NoNewline
```

---

## Creating GitHub Secrets

In your GitHub repo, go to **Settings → Secrets and variables → Actions → New repository secret**. Add the following secrets using the Base64-encoded files or values:

| Secret Name                  | Description                                               |
| ---------------------------- | --------------------------------------------------------- |
| `TENANCY_OCID`               | OCI Tenancy OCID                                          |
| `USER_OCID`                  | OCI User OCID                                             |
| `FINGERPRINT`                | OCI API Key fingerprint (from the public key)             |
| `REGION`                     | OCI region (e.g., `us-ashburn-1`)                         |
| `AVAILABILITY_DOMAIN`        | OCI Availability Domain (e.g., `Uocm:PHX-AD-1`)           |
| `COMPARTMENT_OCID`           | OCI Compartment OCID                                      |
| `VCN_CIDR_BLOCK`             | VCN CIDR (e.g., `10.0.0.0/16`)                            |
| `OKE_K8S_VERSION`            | Kubernetes version for OKE (e.g., `v1.26.x`)              |
| `OKE_NODE_SHAPE`             | Compute shape for OKE nodes (e.g., `VM.Standard.E3.Flex`) |
| `OKE_IMAGE_OCID`             | OCID of the OKE worker image                              |
| `VPN_IMAGE_OCID`             | OCID of the VPN instance image                            |
| `VPN_INSTANCE_SHAPE`         | Compute shape for VPN (e.g., `VM.Standard.E2.1`)          |
| `BUDGET_ALERT_EMAIL`         | Email to receive budget alerts                            |
| `OCI_TF_BUCKET`              | Object Storage bucket for Terraform state                 |
| `OCI_NAMESPACE`              | Object Storage namespace                                  |
| **Base64 Secrets:**          |                                                           |
| `TF_PRIVATE_KEY_B64`         | Base64 of `oci_api_key.pem`                               |
| `TF_OKE_SSH_KEY_B64`         | Base64 of `oke_ssh_key.pub`                               |
| `TF_VPN_SSH_KEY_B64`         | Base64 of `vpn_ssh_key.pub`                               |
| `TF_VPN_PRIVATE_KEY_B64`     | Base64 of `vpn_ssh_key`                                   |
| `POSTGRES_ADMIN_PASSWORD`    | Postgres admin password                                   |
| `POSTGRES_USER_PASSWORD`     | Postgres user password                                    |
| `PGADMIN_EMAIL`              | Email for pgAdmin login                                   |
| `CLOUDFLARE_API_TOKEN`       | Cloudflare API token for DNS and Cert-manager             |
| `CLOUDFLARE_ZONE_ID`         | Cloudflare Zone ID                                        |
| `DOMAIN`                     | Your public domain (e.g., `example.com`)                  |
| **WireGuard Base64 Keys:**   |                                                           |
| `VPN_WIREGUARD_PRIV_KEY_B64` | Base64 of `wg_private.key`                                |
| `VPN_WIREGUARD_PUB_KEY_B64`  | Base64 of `wg_public.key`                                 |
| `VPN_CLIENT_PRIVATE_KEY_B64` | Base64 of `client_private.key`                            |
| `VPN_CLIENT_PUBLIC_KEY_B64`  | Base64 of `client_public.key`                             |

---

## Pipeline Overview

### Terraform Apply Job

1. **Set up Terraform**
2. **Decode** base64 secrets into key files
3. **Generate** `terraform.tfvars` with decoded values
4. **Render** backend\_override from template
5. **Init**, **Validate**, **Plan**, **Apply** infrastructure
6. **Extract** `kubeconfig` and artifact the file
7. **Capture** Load Balancer Subnet (as Base64) and VPN Public IP

### Helm Install Charts Job

1. **Checkout** and **download** `kubeconfig`
2. **Configure** `kubectl` and OCI CLI
3. **Add** Helm repos (Jetstack, Nginx Ingress, Bitnami, Runix, community)
4. **Install**:

   * cert-manager
   * ingress-nginx with OCI LB annotations
   * PostgreSQL
   * pgAdmin
   * n8n (queue mode)
5. **Wait** for LoadBalancer IP, **artifact** result

### Post-Helm VPN Provision Job

1. **Decode** WireGuard & VPN SSH keys
2. **Terraform Init** & **Test SSH**
3. **Apply** `null_resource.vpn_provision` (runs setup script on VPN)
4. **Create** Cloudflare DNS A record for `n8n-webhook` using CF API
5. **Fetch** WireGuard client config
6. **Artifact** `wg0-client.conf`

---

## Triggering the Workflow

In GitHub, go to **Actions → OCI Infra Pipeline → Run workflow**. You can customize branch or inputs if configured.

---

## Next Steps

* Review Terraform modules under `./terraform`
* Customize Helm chart values under `./helm`
* Enhance monitoring, RBAC, and backups
* Contribute improvements via pull requests!
