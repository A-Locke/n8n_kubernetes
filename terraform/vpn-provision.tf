# VPN provisioning is handled by Ansible (ansible/playbooks/vpn-provision.yml).
# The null_resource.vpn_provision that previously lived here has been removed —
# mixing infrastructure (Terraform) with configuration management is an anti-pattern.
# Terraform provisions the VM; Ansible configures it.
