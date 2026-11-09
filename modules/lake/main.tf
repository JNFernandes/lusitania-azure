# MODULE lake: an ADLS Gen2 account (no keys), its containers, and who may read/write the files.

variable "name" {
  description = "Storage account name: globally unique, 3-24 lowercase letters/digits"
  type        = string
}
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "replication_type" {
  description = "LRS = 3 copies in one datacenter; GRS = also in a second region"
  type        = string
  default     = "LRS"
}
variable "containers" {
  type    = set(string)
  default = ["bronze", "silver", "gold", "stream"]
}
variable "data_contributors" {
  description = "Who may read/write files: { label = { principal_id, type (User / ServicePrincipal) } }"
  type = map(object({
    principal_id = string
    type         = string
  }))
}
variable "tags" { type = map(string) }

resource "azurerm_storage_account" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = var.replication_type
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  tags                            = var.tags
}

resource "azurerm_storage_container" "this" {
  for_each           = var.containers
  name               = each.key
  storage_account_id = azurerm_storage_account.this.id
}

resource "azurerm_role_assignment" "data_contributor" {
  for_each             = var.data_contributors
  scope                = azurerm_storage_account.this.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value.principal_id
  principal_type       = each.value.type
}

output "id" { value = azurerm_storage_account.this.id }
output "name" { value = azurerm_storage_account.this.name }
output "dfs_endpoint" { value = azurerm_storage_account.this.primary_dfs_endpoint }
