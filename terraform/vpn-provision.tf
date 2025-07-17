resource "null_resource" "vpn_provision" {
  count = var.lb_ip == "127.0.0.1" ? 0 : 1

  depends_on = [oci_core_instance.vpn_instance]

  provisioner "remote-exec" {
    inline = [
      # Install dependencies
      "sudo apt-get update",
      "sudo apt-get install -y wireguard dnsmasq resolvconf",

      # Enable IP forwarding
      "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl -p",

      # Create WireGuard server config
      "sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF\n[Interface]\nAddress = 10.200.200.1/24\nPrivateKey = ${var.vpn_wireguard_private_key}\nListenPort = 51820\nPostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE\nPostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE\nEOF",

      # Secure and start WireGuard
      "sudo chmod 600 /etc/wireguard/wg0.conf",
      "sudo systemctl enable wg-quick@wg0",
      "sudo systemctl start wg-quick@wg0",

      # Configure dnsmasq to serve ingress domains
      "sudo tee /etc/dnsmasq.d/locke-dns.conf > /dev/null <<EOF\naddress=/n8n-admin.${var.domain}/${var.lb_ip}\naddress=/pgadmin.${var.domain}/${var.lb_ip}\nlisten-address=127.0.0.1\nlisten-address=10.200.200.1\nEOF",

      "sudo systemctl restart dnsmasq",

      # Set system DNS resolver to use local dnsmasq (Ubuntu 22.04 systemd-resolved)
      "sudo mkdir -p /etc/systemd/resolved.conf.d",
      "sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null <<EOF\n[Resolve]\nDNS=127.0.0.1 10.200.200.1\nFallbackDNS=1.1.1.1 8.8.8.8\nDNSStubListener=yes\nEOF",
      "sudo systemctl restart systemd-resolved",
      "sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf",

      # Generate WireGuard client config
      "sudo tee /home/ubuntu/wg0-client.conf > /dev/null <<EOF\n[Interface]\nPrivateKey = ${var.vpn_client_private_key}\nAddress = 10.200.200.2/24\nDNS = 10.200.200.1\n\n[Peer]\nPublicKey = ${var.vpn_wireguard_public_key}\nEndpoint = ${oci_core_instance.vpn_instance.public_ip}:51820\nAllowedIPs = 0.0.0.0/0\nPersistentKeepalive = 25\nEOF",

      "sudo chown ubuntu:ubuntu /home/ubuntu/wg0-client.conf"
    ]

    connection {
      type        = "ssh"
      host        = oci_core_instance.vpn_instance.public_ip
      user        = "ubuntu"
      private_key = var.vpn_private_key
    }
  }
}