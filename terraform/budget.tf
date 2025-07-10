resource "oci_budget_budget" "compartment_budget" {
  compartment_id = var.tenancy_ocid
  target_type    = "COMPARTMENT"
  targets        = [var.compartment_ocid]

  amount         = 100.0
  display_name   = "Budget"
  reset_period   = "MONTHLY"
  description    = "Monthly budget for n8n compartment"
}

resource "oci_budget_alert_rule" "budget_alert" {
  budget_id      = oci_budget_budget.compartment_budget.id
  display_name   = "Alert_rule"
  threshold      = 10.0
  threshold_type = "PERCENTAGE"
  type           = "ACTUAL"
  message        = "You have consumed 10% of your compartment's budget."
  recipients     = var.budget_alert_email
}