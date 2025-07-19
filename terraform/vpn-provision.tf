resource "null_resource" "vpn_provision" {
  count      = var.lb_ip == "127.0.0.1" ? 0 : 1
  depends_on = [oci_core_instance.vpn_instance]

  # Force recreation when key parameters change
  triggers = {
    instance_id = oci_core_instance.vpn_instance.id
    lb_ip       = var.lb_ip
    domain      = var.domain
  }

  provisioner "remote-exec" {
    # Use a single multi-line script block instead of inline = [...] to allow proper heredocs
    script = <<-EOF
      #!/usr/bin/env bash
      set -euo pipefail
      export DEBIAN_FRONTEND=noninteractive

      # Prepare logging
      sudo touch /tmp/vpn-provision.log
      sudo chmod 666 /tmp/vpn-provision.log
      exec > >(sudo tee -a /tmp/vpn-provision.log) 2>&1

      log_and_exit() {
        echo "ERROR: $1" | sudo tee -a /tmp/vpn-provision.log
        exit 1
      }

      echo "Starting VPN provisioning at $(date)"

      echo "Step 1: Updating packages"
      sudo apt-get update -y || log_and_exit "Package update failed"

      echo "Step 2: Installing packages"
      sudo timeout 300 apt-get install -y --no-install-recommends wireguard dnsmasq resolvconf \
        || log_and_exit "Package installation failed"

      echo "Step 3: Enabling IP forwarding"
      echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf \
        || log_and_exit "Failed to configure IP forwarding"
      sudo sysctl -p       || log_and_exit "Failed to apply sysctl settings"

      echo "Step 4: Validating WireGuard private key length"
      WG_PRIV_KEY='${var.vpn_wireguard_private_key}'
      if [ ${#WG_PRIV_KEY} -ne 44 ]; then log_and_exit "Invalid WireGuard private key length"; fi

      echo "Step 5: Creating WireGuard config"
      sudo mkdir -p /etc/wireguard || log_and_exit "Failed to create wireguard directory"
      cat <<WGEOF | sudo tee /etc/wireguard/wg0.conf > /dev/null || log_and_exit "Failed to create WireGuard config"
      [Interface]
      Address    = 10.200.200.1/24
      PrivateKey = ${var.vpn_wireguard_private_key}
      ListenPort = 51820
      PostUp     = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
      PostDown   = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
      WGEOF
      sudo chmod 600 /etc/wireguard/wg0.conf

      echo "Step 6: Starting WireGuard"
      sudo systemctl enable wg-quick@wg0 || log_and_exit "Failed to enable WireGuard service"
      sudo systemctl start wg-quick@wg0  || { sudo journalctl -u wg-quick@wg0 --no-pager -l; log_and_exit "WireGuard failed to start"; }
      sleep 5
      sudo systemctl status wg-quick@wg0 --no-pager || echo "WireGuard status check returned non-zero"

      echo "Step 7: Configuring dnsmasq"
      sudo mkdir -p /etc/dnsmasq.d || log_and_exit "Failed to create dnsmasq directory"
      cat <<DNSEOF | sudo tee /etc/dnsmasq.d/locke-dns.conf > /dev/null || log_and_exit "Failed to create dnsmasq config"
      address=/n8n-admin.${var.domain}/${var.lb_ip}
      address=/pgadmin.${var.domain}/${var.lb_ip}
      listen-address=127.0.0.1
      listen-address=10.200.200.1
      DNSEOF

      echo "Step 8: Restarting dnsmasq"
      sudo systemctl restart dnsmasq || { sudo journalctl -u dnsmasq --no-pager -l; log_and_exit "dnsmasq failed to restart"; }
      sleep 3
      sudo systemctl status dnsmasq --no-pager || echo "dnsmasq status check returned non-zero"

      echo "Step 9: Configuring systemd-resolved"
      sudo mkdir -p /etc/systemd/resolved.conf.d || log_and_exit "Failed to create resolved config directory"
      cat <<RESEOF | sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null || log_and_exit "Failed to create resolved config"
      [Resolve]
      DNS=127.0.0.1 10.200.200.1
      FallbackDNS=1.1.1.1 8.8.8.8
      DNSStubListener=yes
      RESEOF

      echo "Step 10: Restarting systemd-resolved"
      sudo systemctl restart systemd-resolved || echo "systemd-resolved restart failed, continuing"
      sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf || true

      echo "Step 11: Creating client config"
      WG_CLIENT_KEY='${var.vpn_client_private_key}'
      if [ ${#WG_CLIENT_KEY} -ne 44 ]; then log_and_exit "Invalid WireGuard client private key length"; fi
      cat <<CLIENTEOF > /tmp/wg0-client.conf || log_and_exit "Failed to create client config"
      [Interface]
      PrivateKey = ${var.vpn_client_private_key}
      Address    = 10.200.200.2/24
      DNS        = 10.200.200.1

      [Peer]
      PublicKey        = ${var.vpn_wireguard_public_key}
      Endpoint         = ${oci_core_instance.vpn_instance.public_ip}:51820
      AllowedIPs       = 0.0.0.0/0
      PersistentKeepalive = 25
      CLIENTEOF
      sudo cp /tmp/wg0-client.conf /home/ubuntu/wg0-client.conf || log_and_exit "Failed to copy client config"
      sudo chown ubuntu:ubuntu /home/ubuntu/wg0-client.conf || log_and_exit "Failed to set client config ownership"

      echo "VPN provisioning completed successfully at $(date)"
    EOF

    connection {
      type        = "ssh"
      host        = oci_core_instance.vpn_instance.public_ip
      user        = "ubuntu"
      private_key = var.vpn_private_key
      timeout     = "15m"
      agent       = false
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "echo \"VPN provisioner destroyed at $(date)\""
  }
}
