terraform {
  backend "oci" {
    bucket           = "__BUCKET__"
    namespace        = "__NAMESPACE__"
    key              = "terraform.tfstate"
    region           = "__REGION__"
    compartment_ocid = "__COMPARTMENT_OCID__"
  }
}