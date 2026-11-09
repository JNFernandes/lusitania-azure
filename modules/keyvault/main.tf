# MODULE keyvault: a vault with RBAC, the "Secrets Officer" role for one person, and a timer that
# waits until that role has spread through Azure (so secrets can be written right after).

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }
variable "secrets_officer_object_id" {
  description = "Who may create and read secrets (you)."
  type        = string
}
variable "tags" { type = map(string) }

resource "azurerm_key_vault" "this" {
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = var.tags
}

resource "azurerm_role_assignment" "secrets_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.secrets_officer_object_id
}

resource "time_sleep" "role_ready" {
  depends_on      = [azurerm_role_assignment.secrets_officer]
  create_duration = "90s"
}

# The id is only handed out AFTER the wait: any module that writes secrets with it waits too.
output "id" {
  value      = azurerm_key_vault.this.id
  depends_on = [time_sleep.role_ready]
}

output "uri" { value = azurerm_key_vault.this.vault_uri }
output "name" { value = azurerm_key_vault.this.name }
