variable "tenancy_ocid" {}
variable "user_ocid" {}
variable "fingerprint" {}
variable "private_key" {}
variable "region" {}
variable "availability_domain" {}
variable "compartment_ocid" {}
variable "vcn_cidr_block" { default = "10.0.0.0/16" }
variable "oke_k8s_version" { default = "v1.33.1" }
variable "vpn_ssh_key" {}
variable "vpn_private_key" {}
variable "oke_ssh_key" {}
variable "vpn_image_ocid" {}
variable "oke_image_ocid" {}
variable "budget_alert_email" {}
variable "vpn_instance_shape" {}
variable "oke_node_shape" {}
variable "lb_ip" {
  description = "Load Balancer IP for DNS"
  type        = string
  default     = "127.0.0.1"
}
variable "domain" {
  description = "Base domain for ingress DNS"
  type        = string
  default     = "example.com"
}
variable "vpn_wireguard_private_key" {
  description = "WireGuard private key for the VPN server"
  type        = string
  sensitive   = true
  default     = "PRIVATE_KEY_PLACEHOLDER"
}
variable "vpn_wireguard_public_key" {
  description = "WireGuard server public key"
  type        = string
  sensitive   = true
  default     = "PUBLIC_KEY_PLACEHOLDER"
}

variable "vpn_client_private_key" {
  description = "WireGuard client private key"
  type        = string
  sensitive   = true
  default     = "CLIENT_PRIVATE_KEY_PLACEHOLDER"
}
variable "vpn_wireguard_client_public_key" {
  description = "WireGuard client public key"
  type        = string
  sensitive   = true
  default     = "CLIENT_PUBLIC_KEY_PLACEHOLDER"
}