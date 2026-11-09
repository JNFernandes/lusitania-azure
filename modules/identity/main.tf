# MODULE identity: the two identities of the streaming consumer, and nothing else.
#   managed identity   for when it runs IN Azure      (no secret at all)
#   service principal  for when it runs OUTSIDE Azure (its secret goes into the vault)
# Their roles on the LAKE are given by the lake module (it receives the principal ids).

variable "name" {
  description = "Base name, e.g. lusitania-consumer-dev"
  type        = string
}
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }
variable "owner_object_id" { type = string }
variable "key_vault_id" { type = string }
variable "tags" { type = map(string) }

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "identity_reads_secrets" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
}

resource "azuread_application" "this" {
  display_name = "sp-${var.name}"
  owners       = [var.owner_object_id]
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application.this.client_id
  owners    = [var.owner_object_id]
}

resource "azuread_application_password" "this" {
  application_id = azuread_application.this.id
  display_name   = var.name
}

resource "azurerm_key_vault_secret" "login" {
  for_each = {
    consumer-tenant-id     = var.tenant_id
    consumer-client-id     = azuread_application.this.client_id
    consumer-client-secret = azuread_application_password.this.value
  }
  name         = each.key
  value        = each.value
  key_vault_id = var.key_vault_id
}

output "managed_identity_id" { value = azurerm_user_assigned_identity.this.id }
output "managed_identity_principal_id" { value = azurerm_user_assigned_identity.this.principal_id }
output "managed_identity_client_id" { value = azurerm_user_assigned_identity.this.client_id }
output "service_principal_object_id" { value = azuread_service_principal.this.object_id }
output "service_principal_client_id" { value = azuread_application.this.client_id }
output "secret_ids" {
  description = "Versionless ids: always the latest version of each secret"
  value       = { for name, s in azurerm_key_vault_secret.login : name => s.versionless_id }
}
