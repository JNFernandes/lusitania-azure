terraform {
  required_version = ">= 1.6"

  # Same bootstrap storage, ONE STATE FILE PER ENVIRONMENT (the "key")
  backend "azurerm" {
    resource_group_name  = "rg-lusitania-tfstate"
    storage_account_name = "sttfstatelusitjf01"
    container_name       = "tfstate"
    key                  = "lusitania-dev.tfstate"
    use_azuread_auth     = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }
  }
  subscription_id     = var.subscription_id
  storage_use_azuread = true

  # Azure services are switched on per subscription ("resource providers"). azurerm registers a
  # standard set by itself; Container Apps (Microsoft.App) is not in it, so it is added here.
  resource_providers_to_register = ["Microsoft.App"]
}
