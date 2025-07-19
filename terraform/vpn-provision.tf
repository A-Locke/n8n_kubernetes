resource "null_resource" "vpn_provision" {
  count = var.lb_ip == "127.0.0.1" ? 0 : 1
  depends_on = [oci_core_instance.vpn_instance]
  
  provisioner "remote-exec" {
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "set -e",
      "exec > >(tee -a /tmp/vpn-provision.log) 2>&1",  # Log everything
      "echo 'Starting VPN provisioning at $(date)'",
      
      "echo 'Step 1: Updating packages'",
      "sudo apt-get update -y",
      "echo 'Step 1 completed'",
      
      "echo 'Step 2: Installing packages'", 
      "sudo timeout 300 apt-get install -y --no-install-recommends wireguard dnsmasq resolvconf",
      "echo 'Step 2 completed'",
      
      "echo 'Step 3: Enabling IP forwarding'",
      "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf",
      "sudo sysctl -p",
      "echo 'Step 3 completed'",
      
      "echo 'Step 4: Creating WireGuard config'",
      "sudo mkdir -p /etc/wireguard",
      # Split the config creation into smaller parts
      "echo '[Interface]' | sudo tee /etc/wireguard/wg0.conf",
      "echo 'Address = 10.200.200.1/24' | sudo tee -a /etc/wireguard/wg0.conf",
      "echo 'PrivateKey = ${var.vpn_wireguard_private_key}' | sudo tee -a /etc/wireguard/wg0.conf",
      "echo 'ListenPort = 51820' | sudo tee -a /etc/wireguard/wg0.conf",
      "echo 'PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE' | sudo tee -a /etc/wireguard/wg0.conf",
      "echo 'PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE' | sudo tee -a /etc/wireguard/wg0.conf",
      "sudo chmod 600 /etc/wireguard/wg0.conf",
      "echo 'Step 4 completed'",
      
      "echo 'Step 5: Starting WireGuard'",
      "sudo systemctl enable wg-quick@wg0",
      "sudo systemctl start wg-quick@wg0",
      "sleep 5",
      "sudo systemctl status wg-quick@wg0 --no-pager",
      "echo 'Step 5 completed'",
      
      "echo 'Step 6: Configuring dnsmasq'",
      "sudo mkdir -p /etc/dnsmasq.d",
      "echo 'address=/n8n-admin.${var.domain}/${var.lb_ip}' | sudo tee /etc/dnsmasq.d/locke-dns.conf",
      "echo 'address=/pgadmin.${var.domain}/${var.lb_ip}' | sudo tee -a /etc/dnsmasq.d/locke-dns.conf",
      "echo 'listen-address=127.0.0.1' | sudo tee -a /etc/dnsmasq.d/locke-dns.conf",
      "echo 'listen-address=10.200.200.1' | sudo tee -a /etc/dnsmasq.d/locke-dns.conf",
      "echo 'Step 6 completed'",
      
      "echo 'Step 7: Starting dnsmasq'",
      "sudo systemctl restart dnsmasq",
      "sleep 3",
      "sudo systemctl status dnsmasq --no-pager",
      "echo 'Step 7 completed'",
      
      "echo 'Step 8: Configuring systemd-resolved'",
      "sudo mkdir -p /etc/systemd/resolved.conf.d",
      "echo '[Resolve]' | sudo tee /etc/systemd/resolved.conf.d/dns.conf",
      "echo 'DNS=127.0.0.1 10.200.200.1' | sudo tee -a /etc/systemd/resolved.conf.d/dns.conf",
      "echo 'FallbackDNS=1.1.1.1 8.8.8.8' | sudo tee -a /etc/systemd/resolved.conf.d/dns.conf",
      "echo 'DNSStubListener=yes' | sudo tee -a /etc/systemd/resolved.conf.d/dns.conf",
      "echo 'Step 8 completed'",
      
      "echo 'Step 9: Restarting systemd-resolved'",
      "sudo systemctl restart systemd-resolved || echo 'systemd-resolved restart failed, continuing...'",
      "sleep 3",
      "sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf || true",
      "echo 'Step 9 completed'",
      
      "echo 'Step 10: Creating client config'",
      "echo '[Interface]' > /tmp/wg0-client.conf",
      "echo 'PrivateKey = ${var.vpn_client_private_key}' >> /tmp/wg0-client.conf", 
      "echo 'Address = 10.200.200.2/24' >> /tmp/wg0-client.conf",
      "echo 'DNS = 10.200.200.1' >> /tmp/wg0-client.conf",
      "echo '' >> /tmp/wg0-client.conf",
      "echo '[Peer]' >> /tmp/wg0-client.conf",
      "echo 'PublicKey = ${var.vpn_wireguard_public_key}' >> /tmp/wg0-client.conf",
      "echo 'Endpoint = ${oci_core_instance.vpn_instance.public_ip}:51820' >> /tmp/wg0-client.conf",
      "echo 'AllowedIPs = 0.0.0.0/0' >> /tmp/wg0-client.conf",
      "echo 'PersistentKeepalive = 25' >> /tmp/wg0-client.conf",
      "sudo cp /tmp/wg0-client.conf /home/ubuntu/wg0-client.conf",
      "sudo chown ubuntu:ubuntu /home/ubuntu/wg0-client.conf",
      "echo 'Step 10 completed'",
      
      "echo 'VPN provisioning completed successfully at $(date)'",
      "echo 'Log saved to /tmp/vpn-provision.log'"
    ]
    
    connection {
      type        = "ssh"
      host        = oci_core_instance.vpn_instance.public_ip
      user        = "ubuntu"
      private_key = var.vpn_private_key
      timeout     = "10m"
    }
  }
}