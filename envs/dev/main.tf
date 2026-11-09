# ONE ENVIRONMENT = this file + its values (env.auto.tfvars).
# envs/dev/main.tf and envs/prod/main.tf are IDENTICAL: the same modules, called with different
# values. A fix in a module reaches every environment; nothing is copied by hand.

data "azurerm_client_config" "current" {}

locals {
  name = "lusitania-${var.environment}"
  tags = {
    project     = "lusitania"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${local.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_consumption_budget_resource_group" "main" {
  name              = "budget-${local.name}"
  resource_group_id = azurerm_resource_group.main.id
  amount            = var.budget_amount
  time_grain        = "Monthly"

  time_period {
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }
  lifecycle {
    ignore_changes = [time_period]
  }

  dynamic "notification" { # one alert block per type: Actual, then Forecasted
    for_each = ["Actual", "Forecasted"]
    content {
      enabled        = true
      threshold      = 100
      threshold_type = notification.value
      operator       = "GreaterThan"
      contact_emails = [var.alert_email]
    }
  }
}

module "keyvault" {
  source                    = "../../modules/keyvault"
  name                      = "kv-${local.name}-${var.suffix}"
  resource_group_name       = azurerm_resource_group.main.name
  location                  = azurerm_resource_group.main.location
  tenant_id                 = data.azurerm_client_config.current.tenant_id
  secrets_officer_object_id = data.azurerm_client_config.current.object_id
  tags                      = local.tags
}

module "identity" {
  source              = "../../modules/identity"
  name                = "lusitania-consumer-${var.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  owner_object_id     = data.azurerm_client_config.current.object_id
  key_vault_id        = module.keyvault.id # a MODULE OUTPUT feeding another module
  tags                = local.tags
}

module "lake" {
  source              = "../../modules/lake"
  name                = "stlusitania${var.environment}${var.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  replication_type    = var.lake_replication
  data_contributors = {
    me                = { principal_id = data.azurerm_client_config.current.object_id, type = "User" }
    consumer_identity = { principal_id = module.identity.managed_identity_principal_id, type = "ServicePrincipal" }
    consumer_sp       = { principal_id = module.identity.service_principal_object_id, type = "ServicePrincipal" }
  }
  tags = local.tags
}

module "eventhubs" {
  source              = "../../modules/eventhubs"
  name                = "evhns-${local.name}-${var.suffix}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  capacity            = var.eventhubs_capacity
  retention_days      = var.eventhubs_retention_days
  hubs                = { web_orders = 3, order_status = 3, web_orders_dlq = 1 }
  key_vault_id        = module.keyvault.id
  tags                = local.tags
}

module "consumer_app" {
  source                = "../../modules/consumer_app"
  name                  = "lusitania-consumer-${var.environment}"
  registry_name         = "acrlusitania${var.environment}${var.suffix}"
  resource_group_name   = azurerm_resource_group.main.name
  location              = azurerm_resource_group.main.location
  identity_id           = module.identity.managed_identity_id
  identity_principal_id = module.identity.managed_identity_principal_id
  deploy                = var.deploy_consumer
  image_tag             = var.consumer_image_tag
  environment_variables = { LAKE_ACCOUNT = module.lake.name }
  secret_ids = {
    EVENTHUBS_CONNECTION_STRING = module.eventhubs.connection_string_secret_id
    LAKE_TENANT_ID              = module.identity.secret_ids["consumer-tenant-id"]
    LAKE_CLIENT_ID              = module.identity.secret_ids["consumer-client-id"]
    LAKE_CLIENT_SECRET          = module.identity.secret_ids["consumer-client-secret"]
  }
  tags = local.tags
}
