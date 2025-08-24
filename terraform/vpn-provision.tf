resource "null_resource" "vpn_provision" {
  count      = var.lb_ip == "127.0.0.1" ? 0 : 1
  depends_on = [oci_core_instance.vpn_instance]

  connection {
    type        = "ssh"
    host        = oci_core_instance.vpn_instance.public_ip
    user        = "ubuntu"
    private_key = var.vpn_private_key
    timeout     = "2m"
  }

  # 1) Upload installer
  provisioner "file" {
    content = <<-EOF
      #!/usr/bin/env bash
      set -euo pipefail

      # 1. Install WireGuard, dnsmasq & iptables-persistent
      export DEBIAN_FRONTEND=noninteractive
      sudo apt-get update -q
      sudo apt-get install -qy wireguard dnsmasq iptables-persistent

      # 2. Disable any stub resolver now that apt worked
      sudo systemctl stop    systemd-resolved resolvconf.service    || true
      sudo systemctl disable systemd-resolved resolvconf.service    || true
      sudo systemctl mask   systemd-resolved resolvconf.service     || true
      sudo DEBIAN_FRONTEND=noninteractive apt-get purge -y resolvconf

      # 3. Enable IPv4 forwarding
      echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf
      sudo sysctl -p

      # 4. Open firewall for WireGuard & DNS
      sudo iptables -I INPUT -p udp --dport 51820 -j ACCEPT
      sudo iptables -I INPUT -p udp --dport 53    -j ACCEPT
      sudo iptables -I INPUT -p tcp --dport 53    -j ACCEPT
      # Remove any default REJECT in the FORWARD chain so VPN traffic is allowed
      sudo iptables -D FORWARD 1 || true
      sudo netfilter-persistent save
      sudo netfilter-persistent save

      # 5. Write WireGuard server config
      sudo tee /etc/wireguard/wg0.conf > /dev/null <<-WGCONF
      [Interface]
      Address = 10.200.200.1/24
      PrivateKey = ${var.vpn_wireguard_private_key}
      ListenPort = 51820
      PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
      PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
      [Peer]
      PublicKey    = ${var.vpn_wireguard_client_public_key}
      AllowedIPs   = 10.200.200.2/32
      WGCONF

      sudo chmod 600 /etc/wireguard/wg0.conf
      sudo systemctl enable wg-quick@wg0
      sudo systemctl start  wg-quick@wg0

      # 6. Configure dnsmasq for your internal names
      sudo tee /etc/dnsmasq.d/locke-dns.conf > /dev/null <<-DNSMASQ
      listen-address=10.200.200.1
      bind-interfaces
      address=/n8n.${var.domain}/${var.lb_ip}
      address=/pgadmin.${var.domain}/${var.lb_ip}
      DNSMASQ

      sudo systemctl restart dnsmasq

      # 7. Override systemd-resolved so it doesn’t steal port 53
      sudo mkdir -p /etc/systemd/resolved.conf.d
      sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null <<-RESOLV
      [Resolve]
      DNS=10.200.200.1
      FallbackDNS=1.1.1.1 8.8.8.8
      DNSStubListener=no
      RESOLV
      sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf

      # 8. Generate the WireGuard client config
      sudo tee /home/ubuntu/wg0-client.conf > /dev/null <<-CLIENTCONF
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

  # 2) Run it and log everything
  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/vpn-setup.sh",
      "sudo /home/ubuntu/vpn-setup.sh 2>&1 | tee /tmp/vpn-setup.log",
      "sudo systemctl restart wg-quick@wg0"
    ]
  }
}