resource "null_resource" "vpn_provision" {
  count      = var.lb_ip == "127.0.0.1" ? 0 : 1
  depends_on = [oci_core_instance.vpn_instance]

  # 1) Upload a self-contained setup script
  provisioner "file" {
    content = <<-EOF
      #!/usr/bin/env bash
      set -euo pipefail

      # 1. Bootstrap DNS to avoid resolution stalls
      sudo tee /etc/resolv.conf > /dev/null <<DNSCONF
      nameserver 1.1.1.1
      nameserver 8.8.8.8
      DNSCONF

      # 2. Install WireGuard + DNS tooling non-interactively
      export DEBIAN_FRONTEND=noninteractive
      sudo apt-get update -q
      sudo DEBIAN_FRONTEND=noninteractive apt-get -qy install wireguard dnsmasq resolvconf

      # 3. Disable systemd-resolved to free port 53 for dnsmasq
      
	  sudo systemctl stop    systemd-resolved      resolvconf.service  || true
	  sudo systemctl disable systemd-resolved      resolvconf.service  || true
	  sudo systemctl mask   systemd-resolved       resolvconf.service  || true

	  # (Optional) Purge the stub-resolver package so no background agent re-installs it
	  sudo apt-get purge -y resolvconf systemd-resolved

      # 4. Enable IPv4 forwarding
      echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
      sudo sysctl -p
	  
	  # 4.5. Open firewall ports for WireGuard (UDP/51820) and DNS (TCP/UDP/53)
      sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT
      sudo iptables -I INPUT -p udp --dport 53    -j ACCEPT
      sudo iptables -I INPUT -p tcp --dport 53    -j ACCEPT
	  # (Optional) Persist your rules so they survive reboots
      sudo apt-get install -y iptables-persistent
      sudo netfilter-persistent save

      # 5. Write WireGuard server config
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

      # 6. Configure dnsmasq …
      sudo tee /etc/dnsmasq.d/locke-dns.conf > /dev/null <<DNSMASQ
      listen-address=127.0.0.1
      listen-address=10.200.200.1
      bind-interfaces
      address=/n8n-admin.${var.domain}/${var.lb_ip}
      address=/pgadmin.${var.domain}/${var.lb_ip}
      DNSMASQ

      sudo systemctl restart dnsmasq || true

      # 7. Generate DNS resolver override
      sudo mkdir -p /etc/systemd/resolved.conf.d
      sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null <<RESOLV
      [Resolve]
      DNS=127.0.0.1 10.200.200.1
      FallbackDNS=1.1.1.1 8.8.8.8
      DNSStubListener=no
      RESOLV
      sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

      # 8. Generate the WireGuard client config
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

    connection {
      type        = "ssh"
      host        = oci_core_instance.vpn_instance.public_ip
      user        = "ubuntu"
      private_key = var.vpn_private_key
      timeout     = "2m"
    }
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
      timeout     = "2m"
    }
  }
}
