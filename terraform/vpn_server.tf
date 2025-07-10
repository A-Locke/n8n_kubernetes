resource "oci_core_instance" "vpn_instance" {
  availability_domain = var.availability_domain
  compartment_id      = var.compartment_ocid
  shape               = var.vpn_instance_shape

  source_details {
    source_type             = "image"
    source_id               = var.vpn_image_ocid
    boot_volume_size_in_gbs = 50
  }

  shape_config {
    ocpus         = 1
    memory_in_gbs = 1
  }

  create_vnic_details {
    subnet_id        = oci_core_subnet.vpn_subnet.id
    assign_public_ip = true
    display_name     = "vpn-vnic"
  }

  display_name = "vpn-instance"

  metadata = {
    ssh_authorized_keys = var.vpn_ssh_key
  }
}