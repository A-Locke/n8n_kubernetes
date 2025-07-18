terraform {
  backend "oci" {
    namespace      = "{{namespace}}"
    bucket         = "{{bucket}}"
    region         = "{{region}}"
    key            = "{{key}}"
  }
}