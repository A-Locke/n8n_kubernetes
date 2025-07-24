# OCI Infra Pipeline

This repository provides a GitHub Actions CI/CD pipeline to deploy an Oracle Cloud Infrastructure (OCI) Kubernetes cluster, install components (Cert‑Manager, Ingress‑Nginx, PostgreSQL, pgAdmin, n8n), and provision a WireGuard VPN for secure access.

---

## n8n Modes: Regular vs Queue

n8n can run in two modes:

**Regular Mode (default)**
- All components—webhook listener, workflow workers, database—run in a single container.
- Easy to get started but can become CPU‑ and memory‑bound under load.
- Scaling requires duplicating the entire pod, which affects both listener and workers.

**Queue Mode (production grade)**
- Separates the **webhook listener** from **workflow workers**.
- Incoming requests are enqueued (e.g., via Redis) and processed by a pool of worker pods.
- Enables independent horizontal scaling of workers without impacting the listener.
- **Example**: A burst of 40 simultaneous chat‑triggered workflows enqueues quickly; the listener remains responsive while 10–20 worker pods spin up to process the backlog in parallel, clearing the queue in seconds.

---

## Oracle Free Tier Resources

Leverage OCI’s Always Free tier:

1. **2× Ampere A1 Compute** (`VM.Standard.A1.Flex`, ARM‑based): up to 4 OCPUs & 24 GB RAM each for your Kubernetes Node Pool.
2. **1× AMD Compute Instance** (`VM.Standard.E2.1`): 1 OCPU & 8 GB RAM for sidecar services (DNS cache, VPN).
3. **Block Volumes**, **Object Storage**, **Load Balancer**, **Networking** within free limits.

*Always choose shapes labeled **“Always Free Eligible”**.*

---

## Infrastructure Layout

1. **Kubernetes Node Pool**
   - Two **Ampere A1** free‑tier shapes running OKE (ARM‑optimized).  
2. **AMD Compute Instance**
   - Hosts a **DNS resolver** (e.g., CoreDNS cache) and **WireGuard VPN** server.  
   - Provides secure access to cluster ingresses (e.g., n8n webhook endpoints).

---

## Table of Contents

* [Prerequisites](#prerequisites)
* [Secrets Setup](#secrets-setup)
  * [1) Oracle Variables (Free Tier)](#1-oracle-variables-free-tier)
  * [2) Generated Keys & Base64](#2-generated-keys--base64)
  * [3) Cloudflare](#3-cloudflare)
  * [4) Other Secrets](#4-other-secrets)
* [Pipeline Overview](#pipeline-overview)
  * [Terraform Apply Job](#terraform-apply-job)
  * [Helm Install Charts Job](#helm-install-charts-job)
  * [Post-Helm VPN Provision Job](#post-helm-vpn-provision-job)
* [Triggering the Workflow](#triggering-the-workflow)
* [Next Steps](#next-steps)

---

## Prerequisites

1. **OCI account** with:
   - A compartment for resources
   - Object Storage bucket & namespace
   - Cloud Shell or local `oci` CLI configured
2. **GitHub repository** with this code
3. **kubectl**, **helm**, **terraform** installed locally
4. **PowerShell** (Windows) or **bash** (Linux/macOS) for key generation

---

## Secrets Setup

Organize and store all secrets as GitHub Actions repository secrets.

### 1) Oracle Variables (Free Tier)
Extract the following from the OCI Console (Identity & Security → Users, Compartments, Networking, Compute):
- **TENANCY_OCID**, **USER_OCID**, **FINGERPRINT** (API Key → Add API Key).  
- **REGION**, **COMPARTMENT_OCID** (Compartments).  
- **VCN_CIDR_BLOCK**, **SUBNET_OCIDs**, **AVAILABILITY_DOMAIN** (Networking → Virtual Cloud Networks).  
- **OKE_NODE_SHAPE**: `VM.Standard.A1.Flex` (Max 4 OCPUs, 24 GB RAM).  
- **VPN_INSTANCE_SHAPE**: `VM.Standard.E2.1`  

> **Note**: Only use shapes marked **“Always Free Eligible”**.

### 2) Generated Keys & Base64
Generate locally and encode to single‑line Base64:

#### SSH Keys
```bash
ssh-keygen -t rsa -b 4096 -f oke_ssh_key -N ""
ssh-keygen -t rsa -b 4096 -f vpn_ssh_key -N ""
base64 -w 0 oke_ssh_key      > oke_ssh_key_b64.txt
base64 -w 0 oke_ssh_key.pub  > oke_ssh_pub_b64.txt
base64 -w 0 vpn_ssh_key      > vpn_ssh_key_b64.txt
base64 -w 0 vpn_ssh_key.pub  > vpn_ssh_pub_b64.txt
```

#### WireGuard Keys
```bash
wg genkey | tee wg_private.key    | wg pubkey > wg_public.key
wg genkey | tee client_private.key | wg pubkey > client_public.key
base64 -w 0 wg_private.key       > wg_priv_b64.txt
base64 -w 0 wg_public.key        > wg_pub_b64.txt
base64 -w 0 client_private.key   > client_priv_b64.txt
base64 -w 0 client_public.key    > client_pub_b64.txt
```

> PowerShell users can replace `base64 -w 0` with:
> ```powershell
> Get-Content .\<file> -Encoding byte | [Convert]::ToBase64String($_) | Out-File <out>.txt -NoNewline
> ```

### 3) Cloudflare
- **CLOUDFLARE_API_TOKEN**: scoped to DNS & certificate issuance  
- **CLOUDFLARE_ZONE_ID**: your domain’s zone ID

### 4) Other Secrets
- **DOMAIN**: your public domain (e.g., `example.com`)  
- **ADMIN_EMAIL**: for Let’s Encrypt & notifications  

---

## Pipeline Overview

### Terraform Apply Job

1. Checkout & set up Terraform
2. Decode base64 secrets into key files
3. Generate `terraform.tfvars`
4. Render backend override
5. `terraform init/validate/plan/apply`
6. Extract `kubeconfig`; upload as artifact
7. Capture Load Balancer Subnet & VPN Public IP (Base64)

### Helm Install Charts Job

1. Checkout & download `kubeconfig`
2. Configure `kubectl` & OCI CLI
3. Add Helm repos (Jetstack, Nginx Ingress, Bitnami, Runix)
4. Install:
   - cert-manager  
   - ingress-nginx (OCI LB annotations)  
   - PostgreSQL & pgAdmin  
   - n8n (queue mode)  
5. Wait for LoadBalancer IP; upload as artifact

### Post-Helm VPN Provision Job

1. Decode WireGuard & VPN SSH keys
2. Terraform init & test SSH
3. `null_resource.vpn_provision` (runs setup script)
4. Create Cloudflare DNS A record for `n8n-webhook`
5. Fetch `wg0-client.conf`; upload as artifact

---

## Triggering the Workflow

In GitHub, go to **Actions → OCI Infra Pipeline → Run workflow**. Customize branch or inputs if needed.

---

## Next Steps

1. **Autoscaling Helm Chart**
   - Switch n8n Helm config from fixed replica counts to **HorizontalPodAutoscaler** for `worker` & `webhook` deployments.
2. **Monitoring & Alerting**
   - Deploy **Prometheus** & **Grafana** via Helm.  
   - Scrape n8n metrics (queue length, workflow duration), node CPU/RAM, VPN throughput.  
   - Configure dashboards and alerts (e.g., high queue backlog, node pressure).
3. **RBAC & Backups**
   - Define granular Kubernetes roles for CI/CD, monitoring, ops.  
   - Schedule database backups to OCI Object Storage (e.g., Velero or `pg_dump`).
4. **Contributions**
   - Submit PRs to improve modules, charts, or docs.

*Feel free to iterate on Terraform modules under `./terraform` and Helm values in `./helm`.*

