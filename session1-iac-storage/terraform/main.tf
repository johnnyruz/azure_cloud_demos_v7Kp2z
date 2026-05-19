resource "random_string" "storage_suffix" {
  length  = 10
  lower   = true
  numeric = true
  special = false
  upper   = false
}

locals {
  storage_account_name = "${var.storage_account_prefix}${random_string.storage_suffix.result}"
  common_tags = {
    environment = var.environment
    workshop    = "cloud-journey-session-1"
    managed_by  = "terraform"
  }
}

resource "azurerm_resource_group" "demo" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_storage_account" "demo" {
  name                            = local.storage_account_name
  resource_group_name             = azurerm_resource_group.demo.name
  location                        = azurerm_resource_group.demo.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  access_tier                     = "Hot"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  tags                            = local.common_tags
}

resource "azurerm_storage_container" "training" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.demo.id
  container_access_type = "private"
}
