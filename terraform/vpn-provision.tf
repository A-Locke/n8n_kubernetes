resource "null_resource" "vpn_provision" {
  count = var.lb_ip == "127.0.0.1" ? 0 : 1
  depends_on = [oci_core_instance.vpn_instance]
  
  # Add triggers to force recreation when key variables change
  triggers = {
    instance_id = oci_core_instance.vpn_instance.id
    lb_ip = var.lb_ip
    domain = var.domain
  }
  
provisioner "remote-exec" {
    # Use a single, multi-line HEREDOC:
    script = <<-EOF
      #!/usr/bin/env bash
      set -euo pipefail
      export DEBIAN_FRONTEND=noninteractive

      log_and_exit() {
        echo "ERROR: $1" | sudo tee -a /tmp/vpn-provision.log
        exit 1
      }

      echo "Starting VPN provisioning at $(date)" | sudo tee /tmp/vpn-provision.log

      # 1. Update & install
      sudo apt-get update -y || log_and_exit 'Package update failed'
      sudo timeout 300 apt-get install -y --no-install-recommends wireguard dnsmasq resolvconf \
        || log_and_exit 'Package installation failed'

      # 2. Enable forwarding
      echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf \
        || log_and_exit 'Failed to configure IP forwarding'
      sudo sysctl -p || log_and_exit 'Failed to apply sysctl'

      # 3. Validate WireGuard key length
      echo 'Validating WireGuard private key...'
      WG_PRIV_KEY='${var.vpn_wireguard_private_key}'
      if [ ${#WG_PRIV_KEY} -ne 44 ]; then log_and_exit 'Invalid WireGuard private key length'; fi

      # 4. Create wg0.conf
      cat <<WGEOF | sudo tee /etc/wireguard/wg0.conf > /dev/null \
        || log_and_exit 'Failed to create WireGuard config'
      [Interface]
      Address     = 10.200.200.1/24
      PrivateKey  = ${var.vpn_wireguard_private_key}
      ListenPort  = 51820
      PostUp      = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
      PostDown    = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
      WGEOF
      sudo chmod 600 /etc/wireguard/wg0.conf

      # … rest of your steps likewise …
      echo "VPN provisioning completed successfully at $(date)" | sudo tee -a /tmp/vpn-provision.log
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

  # now fix your destroy hook so Terraform doesn’t parse the inner $(date) as an HCL interpolation:
  provisioner "local-exec" {
    when    = destroy
    # escape the inner double-quotes
    command = "echo \\\"VPN provisioner destroyed at $(date)\\\""
  }
}