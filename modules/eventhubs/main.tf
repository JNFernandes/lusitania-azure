# MODULE eventhubs: Kafka in the cloud — a namespace, its event hubs (topics), an application
# login (send + listen) and that login's connection string in the vault.

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "capacity" {
  description = "Throughput units: 1 TU = 1 MB/s or 1,000 events/s in"
  type        = number
  default     = 1
}
variable "retention_days" {
  type    = number
  default = 1
}
variable "hubs" {
  description = "Event hub (topic) name = number of partitions"
  type        = map(number)
}
variable "key_vault_id" { type = string }
variable "tags" { type = map(string) }

resource "azurerm_eventhub_namespace" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "Standard" # the Kafka endpoint needs Standard or higher
  capacity            = var.capacity
  minimum_tls_version = "1.2"
  tags                = var.tags
}

resource "azurerm_eventhub" "this" {
  for_each          = var.hubs
  name              = each.key
  namespace_id      = azurerm_eventhub_namespace.this.id
  partition_count   = each.value
  message_retention = var.retention_days
}

resource "azurerm_eventhub_namespace_authorization_rule" "app" {
  name                = "lusitania-app"
  namespace_name      = azurerm_eventhub_namespace.this.name
  resource_group_name = var.resource_group_name
  listen              = true
  send                = true
  manage              = false
}

resource "azurerm_key_vault_secret" "connection_string" {
  name         = "eventhubs-connection-string"
  value        = azurerm_eventhub_namespace_authorization_rule.app.primary_connection_string
  key_vault_id = var.key_vault_id
  content_type = "Event Hubs connection string (SASL PLAIN password for the Kafka endpoint)"
}

output "bootstrap" { value = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net:9093" }
output "connection_string_secret_id" { value = azurerm_key_vault_secret.connection_string.versionless_id }
