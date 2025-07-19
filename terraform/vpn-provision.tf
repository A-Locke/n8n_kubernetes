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
    inline = [
      "export DEBIAN_FRONTEND=noninteractive",
      "set -e",
      
      # Test basic connectivity and setup logging
      "echo 'Testing connectivity at $(date)...'",
      "whoami",
      "pwd", 
      "uname -a",
      "df -h",
      "free -h",
      
      # Create log file with proper permissions
      "sudo touch /tmp/vpn-provision.log",
      "sudo chmod 666 /tmp/vpn-provision.log",
      
      # Function to log and exit on error
      "log_and_exit() { echo \"ERROR: $1\" | sudo tee -a /tmp/vpn-provision.log; exit 1; }",
      
      # Start logging
      "exec > >(sudo tee -a /tmp/vpn-provision.log) 2>&1",
      
      "echo 'Starting VPN provisioning at $(date)'",
      
      "echo 'Step 1: Updating packages'",
      "sudo apt-get update -y || log_and_exit 'Package update failed'",
      "echo 'Step 1 completed'",
      
      "echo 'Step 2: Installing packages'", 
      "sudo timeout 300 apt-get install -y --no-install-recommends wireguard dnsmasq resolvconf || log_and_exit 'Package installation failed'",
      "echo 'Step 2 completed'",
      
      "echo 'Step 3: Enabling IP forwarding'",
      "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf || log_and_exit 'Failed to configure IP forwarding'",
      "sudo sysctl -p || log_and_exit 'Failed to apply sysctl settings'",
      "echo 'Step 3 completed'",
      
      "echo 'Step 4: Creating WireGuard config'",
      "sudo mkdir -p /etc/wireguard || log_and_exit 'Failed to create wireguard directory'",
      # Validate WireGuard key before using it
      "echo 'Validating WireGuard private key...'",
      "if [ ${#var.vpn_wireguard_private_key} -ne 44 ]; then log_and_exit 'Invalid WireGuard private key length'; fi",
      # Create config file in one go to avoid potential issues  
      "sudo tee /etc/wireguard/wg0.conf > /dev/null <<'WGEOF' || log_and_exit 'Failed to create WireGuard config'",
      "[Interface]",
      "Address = 10.200.200.1/24",
      "PrivateKey = ${var.vpn_wireguard_private_key}",
      "ListenPort = 51820",
      "PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE",
      "PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE",
      "WGEOF",
      "sudo chmod 600 /etc/wireguard/wg0.conf || log_and_exit 'Failed to set WireGuard config permissions'",
      "echo 'Step 4 completed'",
      
      "echo 'Step 5: Starting WireGuard'",
      "sudo systemctl enable wg-quick@wg0 || log_and_exit 'Failed to enable WireGuard service'",
      "sudo systemctl start wg-quick@wg0 || { echo 'WireGuard start failed, checking logs:'; sudo journalctl -u wg-quick@wg0 --no-pager -l; log_and_exit 'WireGuard service failed to start'; }",
      "sleep 5",
      "sudo systemctl status wg-quick@wg0 --no-pager || echo 'WireGuard status check failed'",
      "echo 'Step 5 completed'",
      
      "echo 'Step 6: Configuring dnsmasq'",
      "sudo mkdir -p /etc/dnsmasq.d || log_and_exit 'Failed to create dnsmasq directory'",
      "sudo tee /etc/dnsmasq.d/locke-dns.conf > /dev/null <<'DNSEOF' || log_and_exit 'Failed to create dnsmasq config'",
      "address=/n8n-admin.${var.domain}/${var.lb_ip}",
      "address=/pgadmin.${var.domain}/${var.lb_ip}",
      "listen-address=127.0.0.1",
      "listen-address=10.200.200.1",
      "DNSEOF",
      "echo 'Step 6 completed'",
      
      "echo 'Step 7: Starting dnsmasq'",
      "sudo systemctl restart dnsmasq || { echo 'dnsmasq restart failed, checking logs:'; sudo journalctl -u dnsmasq --no-pager -l; log_and_exit 'dnsmasq service failed to start'; }",
      "sleep 3",
      "sudo systemctl status dnsmasq --no-pager || echo 'dnsmasq status check failed'",
      "echo 'Step 7 completed'",
      
      "echo 'Step 8: Configuring systemd-resolved'",
      "sudo mkdir -p /etc/systemd/resolved.conf.d || log_and_exit 'Failed to create resolved config directory'",
      "sudo tee /etc/systemd/resolved.conf.d/dns.conf > /dev/null <<'RESEOF' || log_and_exit 'Failed to create resolved config'",
      "[Resolve]",
      "DNS=127.0.0.1 10.200.200.1",
      "FallbackDNS=1.1.1.1 8.8.8.8",
      "DNSStubListener=yes",
      "RESEOF",
      "echo 'Step 8 completed'",
      
      "echo 'Step 9: Restarting systemd-resolved'",
      "sudo systemctl restart systemd-resolved || echo 'systemd-resolved restart failed, continuing...'",
      "sleep 3",
      "sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf || true",
      "echo 'Step 9 completed'",
      
      "echo 'Step 10: Creating client config'",
      # Validate client key
      "echo 'Validating WireGuard client private key...'", 
      "if [ ${#var.vpn_client_private_key} -ne 44 ]; then log_and_exit 'Invalid WireGuard client private key length'; fi",
      "tee /tmp/wg0-client.conf > /dev/null <<'CLIENTEOF' || log_and_exit 'Failed to create client config'",
      "[Interface]",
      "PrivateKey = ${var.vpn_client_private_key}",
      "Address = 10.200.200.2/24",
      "DNS = 10.200.200.1",
      "",
      "[Peer]",
      "PublicKey = ${var.vpn_wireguard_public_key}",
      "Endpoint = ${oci_core_instance.vpn_instance.public_ip}:51820",
      "AllowedIPs = 0.0.0.0/0",
      "PersistentKeepalive = 25",
      "CLIENTEOF",
      "sudo cp /tmp/wg0-client.conf /home/ubuntu/wg0-client.conf || log_and_exit 'Failed to copy client config'",
      "sudo chown ubuntu:ubuntu /home/ubuntu/wg0-client.conf || log_and_exit 'Failed to set client config ownership'",
      "echo 'Step 10 completed'",
      
      "echo 'VPN provisioning completed successfully at $(date)'",
      "echo 'Log saved to /tmp/vpn-provision.log'"
    ]
    
    connection {
      type        = "ssh"
      host        = oci_core_instance.vpn_instance.public_ip
      user        = "ubuntu"
      private_key = var.vpn_private_key
      timeout     = "15m"
      # Add retry logic
      agent       = false
    }
  }
  
  # Use local-exec to handle failures instead of destroy provisioner
  provisioner "local-exec" {
    when    = destroy
    command = "echo 'VPN provisioner destroyed at $(date)'"
  }
}