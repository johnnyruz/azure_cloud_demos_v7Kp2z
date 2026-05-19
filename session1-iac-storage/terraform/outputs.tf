output "resource_group_name" {
  value = azurerm_resource_group.demo.name
}

output "storage_account_name" {
  value = azurerm_storage_account.demo.name
}

output "storage_account_id" {
  value = azurerm_storage_account.demo.id
}

output "blob_endpoint" {
  value = azurerm_storage_account.demo.primary_blob_endpoint
}

output "container_name" {
  value = azurerm_storage_container.training.name
}
