output "resource_group_name" {
  value = data.azurerm_resource_group.capstone.name
}

output "vnet_name" {
  value = azurerm_virtual_network.capstone.name
}

output "app_service_name" {
  value = azurerm_linux_web_app.api.name
}

output "app_service_url" {
  value = "https://${azurerm_linux_web_app.api.default_hostname}"
}

output "swagger_url" {
  value = "https://${azurerm_linux_web_app.api.default_hostname}/swagger"
}

output "cosmosdb_account_name" {
  value = azurerm_cosmosdb_account.tasks.name
}

output "cosmosdb_database_name" {
  value = azurerm_cosmosdb_sql_database.tasks.name
}

output "cosmosdb_container_name" {
  value = azurerm_cosmosdb_sql_container.tasks.name
}

output "cosmosdb_private_endpoint_name" {
  value = azurerm_private_endpoint.cosmos.name
}

output "key_vault_name" {
  value = azurerm_key_vault.capstone.name
}

output "key_vault_secret_uri" {
  value     = azurerm_key_vault_secret.cosmos_connection.versionless_id
  sensitive = true
}

output "application_insights_name" {
  value = azurerm_application_insights.capstone.name
}

output "frontend_storage_account_name" {
  value = azurerm_storage_account.frontend.name
}

output "frontend_url" {
  value = azurerm_storage_account.frontend.primary_web_endpoint
}

output "frontend_container_name" {
  value = "$web"
}
