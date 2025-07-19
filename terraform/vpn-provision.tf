resource "null_resource" "vpn_provision" {
  count      = var.lb_ip == "127.0.0.1" ? 0 : 1
  depends_on = [oci_core_instance.vpn_instance]

  # 1) Upload a self-contained setup script
  provisioner "file" {
    content = <<-EOF
      #!/usr/bin/env bash
      set -euo pipefail

      # 1. Bootstrap DNS so apt won't stall on resolution
      sudo tee /etc/resolv.conf > /dev/null <<DNSCONF
      nameserver 1.1.1.1
      nameserver 8.8.8.8
      DNSCONF

      # 2. Install WireGuard + DNS tooling non-interactively
      export DEBIAN_FRONTEND=noninteractive
      sudo apt-get update -q
      sudo DEBIAN_FRONTEND=noninteractive apt-get -qy install wireguard dnsmasq resolvconf

      # 3. Enable IPv4 forwarding
      echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
      sudo sysctl -p

      # 4. Write WireGuard server config
      sudo tee /etc/wireguard/wg0.conf > /dev/null <<WGCONF
      [Interface]
      Address = 10.200.200.1/24
      PrivateKey = ${var.vpn_wireguard_private_key}
      ListenPort = 51820
      PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
      PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
      WGCONF

      sudo chmod 600 /etc/wireguard/wg0.conf
      sudo systemctl enable wg-quick@wg0
      sudo systemctl start wg-quick@wg0

      # 5. Configure dnsmasq for internal hostnames
      sudo tee /etc/dnsmasq.d/locke-dns.conf > /dev/null <<DNSMASQ
      address=/n8n-admin.${var.domain}/${var.lb_ip}
      address=/pgadmin.${var.domain}/${var.lb_ip}
      listen-address=127.0.0.1
      listen-address=10.200.200.1
      DNSMASQ

      sudo systemctl restart dnsmasq

      # 6. Point system resolver at dnsmasq
      sudo mkdir -p /etc/systemd/resolved.conf.d
      sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null <<RESOLV
      [Resolve]
      DNS=127.0.0.1 10.200.200.1
      FallbackDNS=1.1.1.1 8.8.8.8
      DNSStubListener=yes
      RESOLV
      sudo systemctl restart systemd-resolved
      sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

      # 7. Generate the client config
      sudo tee /home/ubuntu/wg0-client.conf > /dev/null <<CLIENTCONF
      [Interface]
      PrivateKey = ${var.vpn_client_private_key}
      Address    = 10.200.200.2/24
      DNS        = 10.200.200.1

      [Peer]
      PublicKey           = ${var.vpn_wireguard_public_key}
      Endpoint            = ${oci_core_instance.vpn_instance.public_ip}:51820
      AllowedIPs          = 0.0.0.0/0
      PersistentKeepalive = 25
      CLIENTCONF

      sudo chown ubuntu:ubuntu /home/ubuntu/wg0-client.conf
    EOF

    destination = "/home/ubuntu/vpn-setup.sh"
  }

  # 2) Execute it under a timeout so Terraform can fail fast
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/vpn-setup.sh",
      "timeout 10m sudo bash /home/ubuntu/vpn-setup.sh"
    ]

    connection {
      type        = "ssh"
      host        = oci_core_instance.vpn_instance.public_ip
      user        = "ubuntu"
      private_key = var.vpn_private_key
      timeout     = "2m"  # SSH connect timeout
    }
  }
}