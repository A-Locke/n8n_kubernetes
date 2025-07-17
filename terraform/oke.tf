resource "oci_containerengine_cluster" "oke_cluster" {
  compartment_id     = var.compartment_ocid
  name               = "cluster_basic_n8n"
  vcn_id             = oci_core_vcn.main.id
  kubernetes_version = "v1.33.1"
  type               = "BASIC_CLUSTER"

  options {
    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
    admission_controller_options {
      is_pod_security_policy_enabled = false
    }
    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
    service_lb_config {}
  }

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = oci_core_subnet.k8s_api_subnet.id
  }
}
resource "oci_containerengine_node_pool" "node_pool" {
  cluster_id         = oci_containerengine_cluster.oke_cluster.id
  compartment_id     = var.compartment_ocid
  name               = "n8n-node-pool"
  kubernetes_version = "v1.33.1"
  node_shape         = var.oke_node_shape

  node_shape_config {
    ocpus         = 2
    memory_in_gbs = 12
  }

  node_config_details {
    size = 2

    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = oci_core_subnet.oke_nodes_subnet.id
    }
  }

  node_metadata = {
      ssh_authorized_keys = var.oke_ssh_key
  }
  node_source_details {
  source_type = "IMAGE"
  image_id    = var.oke_image_ocid  # This should reference your chosen Ubuntu or Oracle Linux image OCID
  boot_volume_size_in_gbs = 50
}
}
data "oci_containerengine_cluster_kube_config" "generated" {
  cluster_id = oci_containerengine_cluster.oke_cluster.id
}