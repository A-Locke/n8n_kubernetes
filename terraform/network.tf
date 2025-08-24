resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "oke-vcn-n8n"
  cidr_block     = var.vcn_cidr_block
  dns_label      = "n8ncluster"
}
resource "oci_core_internet_gateway" "igw" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "oke-igw-n8n"
}
resource "oci_core_nat_gateway" "nat" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "nat-gateway-n8n"
}
resource "oci_core_route_table" "public_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "public-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.igw.id
  }
}
resource "oci_core_route_table" "nat_rt" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "nat-route-table"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.nat.id
  }
}
resource "oci_core_subnet" "vpn_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.30.0/24"
  display_name               = "vpn-subnet"
  prohibit_public_ip_on_vnic = false
  dns_label                  = "vpnsubnet"
  route_table_id             = oci_core_route_table.public_rt.id
  security_list_ids          = [oci_core_security_list.vpn_sec_list.id]
}
resource "oci_core_subnet" "svc_lb_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.20.0/24"
  display_name               = "oke-svclbsubnet"
  prohibit_public_ip_on_vnic = false
  dns_label                  = "lbsub4a173332b"
  route_table_id             = oci_core_route_table.public_rt.id
  security_list_ids 		 = [oci_core_security_list.oke_svc_lb_sec_list.id]

}
resource "oci_core_subnet" "k8s_api_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.0.0/28"
  display_name               = "oke-k8s-api-subnet"
  prohibit_public_ip_on_vnic = false
  dns_label                  = "sube540c8a2c"
  route_table_id             = oci_core_route_table.public_rt.id
  security_list_ids 		 = [oci_core_security_list.oke_k8s_api_sec_list.id]
}
resource "oci_core_subnet" "oke_nodes_subnet" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = "10.0.10.0/24"
  display_name               = "oke-nodesubnet"
  prohibit_public_ip_on_vnic = false
  dns_label                  = "subd905c1423"
  route_table_id             = oci_core_route_table.nat_rt.id
  security_list_ids 		 = [oci_core_security_list.oke_nodes_sec_list.id]
}