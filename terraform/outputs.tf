output "kubeconfig" {
  description = "OKE kubeconfig for GitHub Actions"
  value       = data.oci_containerengine_cluster_kube_config.generated.content
  sensitive   = false
}
output "svc_lb_subnet_ocid" {
  description = "Subnet OCID for the Kubernetes LoadBalancer"
  value       = oci_core_subnet.svc_lb_subnet.id
}
output "vpn_instance_public_ip" {
  value = oci_core_instance.vpn_instance.public_ip
}