#!/usr/bin/env bash
set -euo pipefail

# Where to put generated material
OUT_DIR="${1:-./secrets}"
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

note() { printf "\n[+] %s\n" "$*"; }
err()  { printf "[!] %s\n" "$*" >&2; }

# --- helper: base64 inline (GNU and BSD compatible) ---
b64() {
  # No line wraps; works on macOS and Linux
  if command -v base64 >/dev/null 2>&1; then
    if base64 --help 2>&1 | grep -q "-w"; then
      base64 -w 0
    else
      base64 | tr -d '\n'
    fi
  else
    err "base64 not found"; exit 1
  fi
}

# --- 1) OCI API key (RSA 2048) ---
note "Generating OCI API key pair (RSA 2048)"
openssl genrsa -out "$OUT_DIR/oci_api_key.pem" 2048 >/dev/null 2>&1
openssl rsa -in "$OUT_DIR/oci_api_key.pem" -pubout -out "$OUT_DIR/oci_api_key_public.pem" >/dev/null 2>&1
chmod 600 "$OUT_DIR/oci_api_key.pem"

# Compute fingerprint (colon-separated SHA1 of DER-encoded public key)
FINGERPRINT=$(openssl rsa -pubout -outform DER -in "$OUT_DIR/oci_api_key.pem" 2>/dev/null | openssl sha1 -r | awk '{print $1}' | sed -E 's/(..)/\1:/g;s/:$//')

TF_PRIVATE_KEY_B64=$(b64 < "$OUT_DIR/oci_api_key.pem")

# --- 2) SSH keys for OKE & VPN (ed25519) ---
for NAME in oke vpn; do
  note "Generating SSH key for $NAME (ed25519)"
  ssh-keygen -t ed25519 -N '' -C "$NAME-key" -f "$OUT_DIR/${NAME}_ssh_key" >/dev/null
  chmod 600 "$OUT_DIR/${NAME}_ssh_key"
  chmod 644 "$OUT_DIR/${NAME}_ssh_key.pub"

done

TF_OKE_SSH_KEY_B64=$(b64 < "$OUT_DIR/oke_ssh_key.pub")
TF_VPN_SSH_KEY_B64=$(b64 < "$OUT_DIR/vpn_ssh_key.pub")
TF_VPN_PRIVATE_KEY_B64=$(b64 < "$OUT_DIR/vpn_ssh_key")

# --- 3) WireGuard server & client keys ---
if ! command -v wg >/dev/null 2>&1; then
  err "wg (WireGuard) not found. Install wireguard-tools (wg, wg-quick) and re-run."; exit 1
fi

note "Generating WireGuard keys (server & client)"
# server
wg genkey | tee "$OUT_DIR/wg_server_private.key" > /dev/null
wg pubkey < "$OUT_DIR/wg_server_private.key" > "$OUT_DIR/wg_server_public.key"
# client
wg genkey | tee "$OUT_DIR/wg_client_private.key" > /dev/null
wg pubkey < "$OUT_DIR/wg_client_private.key" > "$OUT_DIR/wg_client_public.key"

chmod 600 "$OUT_DIR/wg_server_private.key" "$OUT_DIR/wg_client_private.key"
chmod 644 "$OUT_DIR/wg_server_public.key" "$OUT_DIR/wg_client_public.key"

VPN_WIREGUARD_PRIV_KEY_B64=$(b64 < "$OUT_DIR/wg_server_private.key")
VPN_WIREGUARD_PUB_KEY=$(cat "$OUT_DIR/wg_server_public.key")
VPN_CLIENT_PRIVATE_KEY_B64=$(b64 < "$OUT_DIR/wg_client_private.key")
VPN_CLIENT_PUBLIC_KEY_B64=$(b64 < "$OUT_DIR/wg_client_public.key")
VPN_WIREGUARD_CLIENT_PUB_KEY=$(cat "$OUT_DIR/wg_client_public.key")

# --- 4) Emit GitHub Secrets file ---
OUT_SECRETS="$OUT_DIR/github-secrets.out"
cat > "$OUT_SECRETS" <<EOF
# Paste these into GitHub → Settings → Secrets and variables → Actions
# (Values left blank require you to fill from provider consoles.)

# OCI core
TENANCY_OCID=
USER_OCID=
REGION=
AVAILABILITY_DOMAIN=
FINGERPRINT=${FINGERPRINT}
TF_PRIVATE_KEY_B64=${TF_PRIVATE_KEY_B64}
OCI_TF_BUCKET=
OCI_NAMESPACE=
COMPARTMENT_OCID=
VCN_CIDR_BLOCK=
OKE_K8S_VERSION=
OKE_NODE_SHAPE=
OKE_IMAGE_OCID=
VPN_INSTANCE_SHAPE=
VPN_IMAGE_OCID=
BUDGET_ALERT_EMAIL=

# SSH for provisioning
TF_OKE_SSH_KEY_B64=${TF_OKE_SSH_KEY_B64}
TF_VPN_SSH_KEY_B64=${TF_VPN_SSH_KEY_B64}
TF_VPN_PRIVATE_KEY_B64=${TF_VPN_PRIVATE_KEY_B64}

# WireGuard
VPN_WIREGUARD_PRIV_KEY_B64=${VPN_WIREGUARD_PRIV_KEY_B64}
VPN_WIREGUARD_PUB_KEY=${VPN_WIREGUARD_PUB_KEY}
VPN_CLIENT_PRIVATE_KEY_B64=${VPN_CLIENT_PRIVATE_KEY_B64}
VPN_CLIENT_PUBLIC_KEY_B64=${VPN_CLIENT_PUBLIC_KEY_B64}
VPN_WIREGUARD_CLIENT_PUB_KEY=${VPN_WIREGUARD_CLIENT_PUB_KEY}

# Cloudflare
CLOUDFLARE_API_TOKEN=
CLOUDFLARE_ZONE_ID=

# Apps / Ingress / Data
DOMAIN=
PGADMIN_EMAIL=
POSTGRES_ADMIN_PASSWORD=
POSTGRES_USER_PASSWORD=
EOF

note "Generated: $OUT_SECRETS"

# --- 5) Human-readable summary ---
cat <<SUM

================= SUMMARY =================
Output directory: $OUT_DIR

Generated keys:
- OCI API private key:         $OUT_DIR/oci_api_key.pem
- OCI API public key:          $OUT_DIR/oci_api_key_public.pem  (upload to OCI User → API Keys)
- OKE SSH keypair:             $OUT_DIR/oke_ssh_key{,.pub}
- VPN SSH keypair:             $OUT_DIR/vpn_ssh_key{,.pub}
- WireGuard server keys:       $OUT_DIR/wg_server_{private,public}.key
- WireGuard client keys:       $OUT_DIR/wg_client_{private,public}.key

Computed fingerprint (verify after upload in OCI):
- FINGERPRINT=$FINGERPRINT

GitHub secrets file with values to paste:
- $OUT_SECRETS
===========================================
SUM