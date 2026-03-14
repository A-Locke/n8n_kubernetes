# OCI Infra Pipeline -- CI/CD on Oracle Cloud Free Tier

This repository provides a **GitHub Actions CI/CD pipeline** for
deploying an **Oracle Cloud Infrastructure (OCI) Kubernetes cluster**,
installing components (Cert-Manager, Ingress-Nginx, PostgreSQL, pgAdmin,
n8n), and provisioning a **WireGuard VPN** for secure access. It also
includes a full guide to generating and managing required **GitHub
Secrets**.

------------------------------------------------------------------------

## Table of Contents

-   Overview
-   n8n Modes
-   Oracle Free Tier Resources
-   Cost Comparison
-   Infrastructure Layout
-   Prerequisites
-   Secrets Setup
-   Script: generate-secrets.sh
-   Pipeline Overview
-   Triggering the Workflow
-   Next Steps
-   Safety Tips

------------------------------------------------------------------------

## Overview

The pipeline provisions the following:

-   **OKE Kubernetes Cluster** on Always Free Ampere A1 nodes
-   **Helm-managed deployments**: Cert-Manager, Ingress-Nginx,
    PostgreSQL, pgAdmin, Valkey, n8n (v2, queue mode), and Prometheus + Grafana
-   **Kubernetes hardening**: RBAC, NetworkPolicy, HPA, ResourceQuota,
    LimitRange, and PodDisruptionBudget via manifests in `k8s/`
-   **WireGuard VPN** hosted on a free AMD instance — sole access path to n8n, pgAdmin, and Grafana
-   **Ansible provisioning** for VPN configuration and Cloudflare DNS (replaces Terraform null_resource)
-   **Cloudflare DNS automation** for certificate issuance via DNS01 challenge

------------------------------------------------------------------------

## n8n Modes: Regular vs Queue

**Regular Mode (default)**
- All components run in a single container.
- Simple to start, but scales poorly under load.

**Queue Mode (recommended for production)**
- Separates **webhook listener** and **workflow workers**.
- Workers consume from a queue (via Valkey).
- Enables **independent horizontal scaling**.

*Example: 40 workflows enqueue quickly → listener stays responsive → 20
workers clear the backlog in parallel.*

------------------------------------------------------------------------

## Oracle Free Tier Resources

-   **2× Ampere A1 Compute (VM.Standard.A1.Flex)** --- up to 4 OCPUs &
    24 GB RAM each (K8s node pool).
-   **1× AMD Compute Instance (VM.Standard.E2.1)** --- for sidecar
    services (VPN, DNS).
-   **Block Volumes, Object Storage, Load Balancer, Networking** ---
    within free limits.

Always choose shapes marked **"Always Free Eligible."**

------------------------------------------------------------------------

## CI/CD Infrastructure Cost Comparison

| Component                     | Oracle Cloud (Free Tier)                      | AWS (EKS)            | Azure (AKS)                               |
|------------------------------|-----------------------------------------------|----------------------|-------------------------------------------|
| Kubernetes Control Plane     | ✅ Free (OKE)                                  | ❌ $72/mo            | ✅ Free (basic)<br>❌ $72/mo (SLA)         |
| Compute Nodes                | ✅ 2× A1.Flex                                  | ❌ $98/mo            | ❌ $140/mo                                |
| VM for VPN and DNS           | ✅ Free                                        | ❌ $7/mo             | ❌ $6/mo                                  |
| Storage (200 GB)             | ✅ Included                                    | ❌ ~$45/mo           | ❌ ~$30/mo                                |
| Load Balancer                | ✅ 1 basic LB included (10 Mbps)               | ❌ $20–25/mo         | ✅ Basic Free<br>❌ Standard ~$18/mo       |
| Outbound Traffic (100 GB)    | ✅ Free (up to 10 TB/mo)                       | ❌ $9/mo             | ❌ $8–9/mo                                |
| **Total Monthly Cost**       | 🟢 **$0**                                      | 🔴 **$250+**         | 🟡 **$195+** / 🔴 **$267+**               |

## Infrastructure Layout

1.  **Kubernetes Node Pool**: 2× Ampere A1 free-tier nodes running OKE.
2.  **AMD Compute Instance**: Runs DNS resolver and WireGuard VPN.

------------------------------------------------------------------------

## Prerequisites

-   **OCI account** with compartment, bucket, namespace.
-   **GitHub repository** with pipeline code.
-   Installed locally: `kubectl`, `helm`, `terraform`, `openssl`,
    `ssh-keygen`, `wg`.
-   **PowerShell** (Windows) or **bash** (Linux/macOS).

------------------------------------------------------------------------

## Overview of Secrets

> **Legend**  
> 🔒 = keep secret; 🧾 = copy from provider console; 🧮 = derived by the script; 🧩 = choose/set yourself

### Oracle Cloud Infrastructure (OCI / OKE)
- **TENANCY_OCID** (🧾) — Your tenancy OCID.  
  *OCI Console → Profile menu (top‑right) → **Tenancy: <name>** → Tenancy OCID.*
- **USER_OCID** (🧾) — Your user OCID.  
  *OCI Console → Profile menu → **User Settings** → OCID.*
- **REGION** (🧾) — Short region key, e.g. `eu-frankfurt-1`.
- **AVAILABILITY_DOMAIN** (🧾) — e.g. `kIdk:EU-FRANKFURT-1-AD-1`.  
  *OCI Console → Compute → Instances → Create → see AD list (or API).*
- **FINGERPRINT** (🧾 after upload) — API key fingerprint.  
  *Shown after you upload the API public key to your user (see steps below).*  
- **TF_PRIVATE_KEY_B64** (🔒🧮) — **Base64 of the OCI API private key PEM** used by Terraform and OCI CLI.  
- **OCI_TF_BUCKET** (🧾/🧩) — Object Storage bucket name used for the Terraform backend.  
  *OCI Console → Object Storage → Buckets.*
- **OCI_NAMESPACE** (🧾) — Object Storage **namespace** (account‑wide).  
  *Shown in Object Storage list header.*
- **COMPARTMENT_OCID** (🧾) — Target compartment OCID.  
  *Identity & Security → Compartments.*
- **VCN_CIDR_BLOCK** (🧩) — Chosen CIDR, e.g. `10.0.0.0/16`.
- **OKE_K8S_VERSION** (🧾/🧩) — E.g. `v1.29.x` supported in your region.  
- **OKE_NODE_SHAPE** (🧾/🧩) — Worker shape, e.g. `VM.Standard3.Flex`.
- **OKE_IMAGE_OCID** (🧾) — Image OCID for node pools in your region.  
- **VPN_INSTANCE_SHAPE** (🧾/🧩) — VM shape for VPN host.  
- **VPN_IMAGE_OCID** (🧾) — Image OCID used for the VPN instance.
- **BUDGET_ALERT_EMAIL** (🧩) — Email for budget alerts.

### SSH keys for provisioning (Terraform / SSH to instances)
- **TF_OKE_SSH_KEY_B64** (🔒🧮) — **Base64 of the OKE SSH public key**.  
- **TF_VPN_SSH_KEY_B64** (🔒🧮) — **Base64 of the VPN SSH public key**.  
- **TF_VPN_PRIVATE_KEY_B64** (🔒🧮) — **Base64 of the VPN SSH private key** (PEM) used by the workflow to SSH to the VPN host.

### WireGuard / VPN
- **VPN_WIREGUARD_PRIV_KEY_B64** (🔒🧮) — **Base64 of the WireGuard server private key**.
- **VPN_WIREGUARD_PUB_KEY** (🔒🧮) — WireGuard server public key (plain text, not Base64).
- **VPN_CLIENT_PRIVATE_KEY_B64** (🔒🧮) — **Base64 of the WireGuard client private key**.
- **VPN_CLIENT_PUBLIC_KEY_B64** (🔒🧮) — **Base64 of the WireGuard client public key** (the workflow decodes this to `client.pub`).
- **VPN_WIREGUARD_CLIENT_PUB_KEY** (🔒🧮) — Client public key (plain text) used by Terraform at apply time.

### Cloudflare (DNS + cert-manager DNS01)
- **CLOUDFLARE_API_TOKEN** (🔒🧾) — Token with permissions: *Zone → DNS:Edit*, *Zone:Read* (and account as needed).
  *Cloudflare Dashboard → My Profile → API Tokens.*

### Applications / Ingress / Data
- **DOMAIN** (🧩) — Base domain for ingress, e.g. `example.com`.
- **PGADMIN_EMAIL** (🧩) — Email for pgAdmin login and as cert-manager Issuer email.
- **POSTGRES_ADMIN_PASSWORD** (🔒🧩) — Strong password for `postgres` superuser.
- **POSTGRES_USER_PASSWORD** (🔒🧩) — Strong password for application DB user.
- **GRAFANA_ADMIN_PASSWORD** (🔒🧩) — Strong password for Grafana admin login.

---

## Step 1 — Generate Keys & Encodings

Use the script below (**`./generate-secrets.sh`**) to generate:
- OCI API key pair (PEM)  
- SSH key pairs for OKE & VPN (ed25519)
- WireGuard server & client keys
- Base64 encodings for all secrets that require them

Outputs are written under `./secrets/` and a summary file `./secrets/github-secrets.out` with `NAME=VALUE` lines you can paste into GitHub → *Settings → Secrets and variables → Actions*.

> **Note:** For the OCI API key, you must upload the **public** key to your OCI user after generation to obtain the **FINGERPRINT** value (shown in the console). The script prints the fingerprint it computes for convenience; verify it matches OCI after upload.

---

## Step 2 — Upload OCI API Public Key & Record Fingerprint
1. Open *OCI Console → Profile → User Settings → API Keys* → **Add API Key** → *Paste Public Key*.
2. Paste contents of `./secrets/oci_api_key_public.pem`.
3. Copy the displayed **Fingerprint** and set it in GitHub as the `FINGERPRINT` secret.

---

## Step 3 — Create Remaining Provider Values
- **OCI_TF_BUCKET / OCI_NAMESPACE**: Create or choose an Object Storage bucket; copy the bucket name and the account namespace.
- **COMPARTMENT_OCID**: Use your target compartment’s OCID.
- **Images / Shapes / Versions**: Choose region‑valid values for `OKE_IMAGE_OCID`, `VPN_IMAGE_OCID`, `OKE_NODE_SHAPE`, `VPN_INSTANCE_SHAPE`, `OKE_K8S_VERSION`.
- **Cloudflare**: Create an API token (DNS:Edit), and copy your Zone ID from the domain’s Overview page.
- **Passwords**: Pick strong values and store them as secrets.

---

## Quick Mapping: Which Secrets Expect Base64?

**Expect Base64:**
- `TF_PRIVATE_KEY_B64`, `TF_OKE_SSH_KEY_B64`, `TF_VPN_SSH_KEY_B64`, `TF_VPN_PRIVATE_KEY_B64`
- `VPN_WIREGUARD_PRIV_KEY_B64`, `VPN_CLIENT_PRIVATE_KEY_B64`, `VPN_CLIENT_PUBLIC_KEY_B64`

**Plain (not Base64):**
- `TENANCY_OCID`, `USER_OCID`, `REGION`, `AVAILABILITY_DOMAIN`, `FINGERPRINT`, `OCI_TF_BUCKET`, `OCI_NAMESPACE`, `COMPARTMENT_OCID`, `VCN_CIDR_BLOCK`, `OKE_K8S_VERSION`, `OKE_NODE_SHAPE`, `OKE_IMAGE_OCID`, `VPN_INSTANCE_SHAPE`, `VPN_IMAGE_OCID`, `BUDGET_ALERT_EMAIL`, `DOMAIN`, `PGADMIN_EMAIL`, `CLOUDFLARE_API_TOKEN`, `POSTGRES_ADMIN_PASSWORD`, `POSTGRES_USER_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`, `VPN_WIREGUARD_PUB_KEY`, `VPN_WIREGUARD_CLIENT_PUB_KEY`.

---

# Script: `generate-secrets.sh`

## Usage

```bash
# Make executable and run (creates ./secrets by default)
chmod +x ./generate-secrets.sh
./generate-secrets.sh            # or: ./generate-secrets.sh ./my-secrets
```

Then:
1. Upload `oci_api_key_public.pem` to your OCI user (API Keys) and confirm the **fingerprint** matches.
2. Open the generated `./secrets/github-secrets.out`, copy/paste into GitHub *Actions Secrets*.  
3. Fill in the remaining provider values (bucket/namespace, compartment OCID, shapes/images/versions, Cloudflare token/zone, domain, emails, passwords).

---

## Pipeline Overview

1.  **Terraform Apply Job**: init, plan, apply, extract kubeconfig.
2.  **Helm Install Charts Job**: install Cert-Manager, Ingress-Nginx,
    PostgreSQL, pgAdmin, Valkey, n8n, Prometheus + Grafana, and metrics-server;
    apply RBAC, NetworkPolicy, HPA, ResourceQuota, LimitRange, and PDB manifests from `k8s/`.
3.  **Ansible Job**: provision WireGuard VPN, configure dnsmasq, update Cloudflare DNS, upload client config artifact.

Two artifacts are produced by each successful run:
- **`kubeconfig`** — cluster access for kubectl, Lens, and the Kubernetes MCP server
- **`wg0-client`** — WireGuard client config for VPN access to n8n, pgAdmin, and Grafana

------------------------------------------------------------------------

## Triggering the Workflow

In GitHub: `Actions → OCI Create Pipeline → Run workflow`.

------------------------------------------------------------------------

## AI Tooling

### Claude Code Skills
Five custom skills are included in `.claude/skills/` for use with Claude Code (VSCode extension or CLI):

| Skill | Purpose |
|---|---|
| `/k8s-status` | Cluster health overview — nodes, pods, PVCs, warning events |
| `/k8s-debug` | Debug a crashing pod — logs, describe, events |
| `/k8s-scale` | Scale a deployment and verify rollout |
| `/k8s-cost` | Resource usage vs Always Free limits |
| `/n8n-queue` | n8n queue depth, worker status, Valkey health |

### Claude Desktop — Kubernetes MCP
Connect Claude Desktop to your cluster for conversational cluster management.
See [mcp/README.md](mcp/README.md) for setup instructions.

------------------------------------------------------------------------

## Next Steps

-   n8n MCP server — connect Claude Desktop directly to n8n workflows post-deploy

------------------------------------------------------------------------

*Written with AI assistance (Claude by Anthropic).*
