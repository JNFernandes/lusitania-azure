output "resource_group" { value = azurerm_resource_group.main.name }
output "lake_url" { value = module.lake.dfs_endpoint }
output "key_vault_uri" { value = module.keyvault.uri }
output "eventhubs_bootstrap" { value = module.eventhubs.bootstrap }
output "consumer_sp_client_id" { value = module.identity.service_principal_client_id }
output "registry_name" { value = module.consumer_app.registry_name }
output "consumer_app" { value = module.consumer_app.app_name }
