resource "oci_core_security_list" "oke_nodes_sec_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "oke-nodes-security-list"

  ingress_security_rules {
    protocol = "all"
    source   = "10.0.10.0/24"
  }

  ingress_security_rules {
    protocol = "1"
    source   = "10.0.0.0/28"
    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "10.0.0.0/28"
    tcp_options {
      min = 12250
      max = 12250
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "10.0.0.0/28"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 22
      max = 22
    }
  }

  egress_security_rules {
    protocol = "all"
    destination = "10.0.10.0/24"
  }

  egress_security_rules {
    protocol = "6"
    destination = "10.0.0.0/28"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  egress_security_rules {
    protocol = "6"
    destination = "10.0.0.0/28"
    tcp_options {
      min = 12250
      max = 12250
    }
  }

  egress_security_rules {
    protocol = "1"
    destination = "10.0.0.0/28"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol = "6"
    destination = "10.0.0.0/16"
    tcp_options {
      min = 443
      max = 443
    }
  }

  egress_security_rules {
    protocol = "1"
    destination = "0.0.0.0/0"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "oke_k8s_api_sec_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "oke-k8s-api-security-list"

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "10.0.10.0/24"
    tcp_options {
      min = 6443
      max = 6443
    }
  }

  ingress_security_rules {
    protocol = "6"
    source   = "10.0.10.0/24"
    tcp_options {
      min = 12250
      max = 12250
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "10.0.10.0/24"
    icmp_options {
      type = 3
      code = 4
    }
  }

  egress_security_rules {
    protocol = "all"
    destination = "0.0.0.0/0"
    }

  egress_security_rules {
    protocol = "6"
    destination = "10.0.10.0/24"
  }

  egress_security_rules {
    protocol = "1"
    destination = "10.0.10.0/24"
    icmp_options {
      type = 3
      code = 4
    }
  }
}

resource "oci_core_security_list" "oke_svc_lb_sec_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "oke-svclb-security-list"

  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}

resource "oci_core_security_list" "vpn_sec_list" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "vpn-security-list"

  # SSH from anywhere
  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  # All internal VCN traffic
  ingress_security_rules {
    protocol = "all"
    source   = "10.0.0.0/16"
  }
  
  # UDP for VPN
	ingress_security_rules {
    protocol = "17"  
    source = "0.0.0.0/0"

    udp_options {
        min = 51820
        max = 51820
    
   }
 }
  egress_security_rules {
    protocol    = "all"
    destination = "0.0.0.0/0"
  }
}