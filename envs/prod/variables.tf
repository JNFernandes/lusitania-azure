# Personal values (terraform.tfvars, NOT committed)
variable "subscription_id" { type = string }
variable "alert_email" { type = string }

# Environment values (env.auto.tfvars, committed: they are the difference between dev and prod)
variable "environment" { type = string }
variable "suffix" {
  description = "Makes globally unique names unique (storage, vault, Event Hubs)"
  type        = string
}
variable "location" {
  type    = string
  default = "westeurope"
}
variable "budget_amount" { type = number }
variable "lake_replication" { type = string }
variable "eventhubs_capacity" { type = number }
variable "eventhubs_retention_days" { type = number }

# Step 8b: the consumer in Azure Container Apps (two-stage: registry first, then the app)
variable "deploy_consumer" {
  type    = bool
  default = false
}
variable "consumer_image_tag" {
  type    = string
  default = "v1"
}
