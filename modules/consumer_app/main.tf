# MODULE consumer_app (step 8b): the streaming consumer runs IN AZURE, not on the laptop.
#
#   Azure Container Registry   holds the image (built in Azure: cloud/build_consumer_image.ps1)
#   Container Apps environment the place apps run in (serverless: no VMs to manage)
#   Container App              the consumer: 1 replica, always on, restarted by Azure if it crashes
#
# It logs in with the MANAGED IDENTITY (step 6) for everything it needs from Azure itself:
#   pull the image from the registry     → role AcrPull, no registry password
#   read its secrets from Key Vault      → "Key Vault references": Azure fetches them for it
#
# TWO-STAGE DEPLOY: the image must exist before the app can start, and the registry must exist
# before the image can be built. So: apply (registry) → build the image → apply with deploy = true.

variable "name" { type = string }
variable "registry_name" {
  description = "Globally unique, 5-50 letters/digits"
  type        = string
}
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "identity_id" {
  description = "Resource id of the user-assigned managed identity"
  type        = string
}
variable "identity_principal_id" { type = string }
variable "secret_ids" {
  description = "Key Vault secret ids (versionless) the app receives as environment variables: { ENV_VAR = id }"
  type        = map(string)
}
variable "environment_variables" {
  description = "Plain (non-secret) environment variables"
  type        = map(string)
  default     = {}
}
variable "deploy" {
  description = "false = registry only (stage 1); true = also the environment and the app (stage 2)"
  type        = bool
  default     = false
}
variable "image_tag" {
  type    = string
  default = "v1"
}
variable "tags" { type = map(string) }

resource "azurerm_container_registry" "this" {
  name                = var.registry_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false # no registry password: pulls happen with the managed identity
  tags                = var.tags
}

resource "azurerm_role_assignment" "pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = var.identity_principal_id
  principal_type       = "ServicePrincipal"
}

resource "time_sleep" "pull_ready" {
  depends_on      = [azurerm_role_assignment.pull]
  create_duration = "60s"
}

resource "azurerm_container_app_environment" "this" {
  count               = var.deploy ? 1 : 0
  name                = "cae-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

locals {
  # Container Apps secret names: lowercase letters, digits and '-' (LAKE_CLIENT_SECRET → lake-client-secret)
  secret_names = { for env_var, _ in var.secret_ids : env_var => replace(lower(env_var), "_", "-") }
}

resource "azurerm_container_app" "this" {
  count                        = var.deploy ? 1 : 0
  name                         = "ca-${var.name}"
  container_app_environment_id = azurerm_container_app_environment.this[0].id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  registry {
    server   = azurerm_container_registry.this.login_server
    identity = var.identity_id
  }

  # KEY VAULT REFERENCES: the app stores only WHERE each secret is; Azure reads it with the identity
  dynamic "secret" {
    for_each = var.secret_ids
    content {
      name                = local.secret_names[secret.key]
      identity            = var.identity_id
      key_vault_secret_id = secret.value
    }
  }

  template {
    min_replicas = 1 # a stream never sleeps: always one copy running...
    max_replicas = 1 # ...and never two: they would fight over the same checkpoint

    container {
      name   = "consumer"
      image  = "${azurerm_container_registry.this.login_server}/lusitania-consumer:${var.image_tag}"
      cpu    = 2.0
      memory = "4Gi"

      dynamic "env" {
        for_each = var.environment_variables
        content {
          name  = env.key
          value = env.value
        }
      }
      dynamic "env" {
        for_each = var.secret_ids
        content {
          name        = env.key
          secret_name = local.secret_names[env.key]
        }
      }
    }
  }

  depends_on = [time_sleep.pull_ready]
}

output "registry_name" { value = azurerm_container_registry.this.name }
output "registry_login_server" { value = azurerm_container_registry.this.login_server }
output "app_name" { value = var.deploy ? azurerm_container_app.this[0].name : null }
