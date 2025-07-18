terraform {
  backend "oci" {
    namespace      = "{{namespace}}"
    bucket         = "{{bucket}}"
    region         = "{{region}}"
    key            = "{{key}}"
    compartment_id = "{{compartment_id}}"
  }
}