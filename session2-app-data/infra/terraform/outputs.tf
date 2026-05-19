output "resource_group_name" {
  value = data.azurerm_resource_group.demo.name
}

output "cosmosdb_account_name" {
  value = azurerm_cosmosdb_account.demo.name
}

output "cosmosdb_database_name" {
  value = azurerm_cosmosdb_sql_database.training.name
}

output "cosmosdb_container_name" {
  value = azurerm_cosmosdb_sql_container.items.name
}

output "cosmosdb_connection_string" {
  value     = azurerm_cosmosdb_account.demo.primary_sql_connection_string
  sensitive = true
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

output "application_insights_name" {
  value = azurerm_application_insights.demo.name
}
