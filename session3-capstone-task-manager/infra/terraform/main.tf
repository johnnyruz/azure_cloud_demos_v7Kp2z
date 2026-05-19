data "azurerm_client_config" "current" {}

data "azurerm_resource_group" "capstone" {
  name = var.resource_group_name
}

resource "random_string" "suffix" {
  length  = 8
  lower   = true
  numeric = true
  special = false
  upper   = false
}

locals {
  unique_suffix         = random_string.suffix.result
  cosmosdb_account_name = substr("${var.workload_name}cosmos${local.unique_suffix}", 0, 44)
  app_service_plan_name = "asp-${var.workload_name}-${local.unique_suffix}"
  app_service_name      = substr("${var.workload_name}-api-${local.unique_suffix}", 0, 60)
  log_analytics_name    = "log-${var.workload_name}-${local.unique_suffix}"
  app_insights_name     = "appi-${var.workload_name}-${local.unique_suffix}"
  key_vault_name        = substr("kv-${var.workload_name}-${local.unique_suffix}", 0, 24)
  storage_account_name  = substr("st${var.workload_name}${local.unique_suffix}", 0, 24)
  vnet_name             = "vnet-${var.workload_name}-${var.environment}"
  app_subnet_name       = "snet-app"
  data_subnet_name      = "snet-data"
  cosmos_secret_name    = "cosmosdb-connection-string"

  common_tags = {
    environment = var.environment
    workshop    = "cloud-journey-session-3"
    managed_by  = "terraform"
  }
}

resource "azurerm_virtual_network" "capstone" {
  name                = local.vnet_name
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "app" {
  name                = "nsg-${var.workload_name}-app-${local.unique_suffix}"
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags
}

resource "azurerm_network_security_group" "data" {
  name                = "nsg-${var.workload_name}-data-${local.unique_suffix}"
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-AppSubnet-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.app_subnet_prefix
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Deny-Internet-Inbound"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet" "app" {
  name                 = local.app_subnet_name
  resource_group_name  = data.azurerm_resource_group.capstone.name
  virtual_network_name = azurerm_virtual_network.capstone.name
  address_prefixes     = [var.app_subnet_prefix]

  delegation {
    name = "app-service-delegation"

    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_subnet" "data" {
  name                              = local.data_subnet_name
  resource_group_name               = data.azurerm_resource_group.capstone.name
  virtual_network_name              = azurerm_virtual_network.capstone.name
  address_prefixes                  = [var.data_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}

resource "azurerm_cosmosdb_account" "tasks" {
  name                          = local.cosmosdb_account_name
  location                      = data.azurerm_resource_group.capstone.location
  resource_group_name           = data.azurerm_resource_group.capstone.name
  offer_type                    = "Standard"
  kind                          = "GlobalDocumentDB"
  public_network_access_enabled = false

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = data.azurerm_resource_group.capstone.location
    failover_priority = 0
    zone_redundant    = false
  }

  tags = local.common_tags
}

resource "azurerm_cosmosdb_sql_database" "tasks" {
  name                = var.database_name
  resource_group_name = data.azurerm_resource_group.capstone.name
  account_name        = azurerm_cosmosdb_account.tasks.name
}

resource "azurerm_cosmosdb_sql_container" "tasks" {
  name                = var.container_name
  resource_group_name = data.azurerm_resource_group.capstone.name
  account_name        = azurerm_cosmosdb_account.tasks.name
  database_name       = azurerm_cosmosdb_sql_database.tasks.name
  partition_key_paths = [var.partition_key_path]
}

resource "azurerm_private_dns_zone" "cosmos" {
  name                = "privatelink.documents.azure.com"
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "cosmos" {
  name                  = "pdnslink-${var.workload_name}-${local.unique_suffix}"
  resource_group_name   = data.azurerm_resource_group.capstone.name
  private_dns_zone_name = azurerm_private_dns_zone.cosmos.name
  virtual_network_id    = azurerm_virtual_network.capstone.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_endpoint" "cosmos" {
  name                = "pe-${var.workload_name}-cosmos-${local.unique_suffix}"
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  subnet_id           = azurerm_subnet.data.id
  tags                = local.common_tags

  private_service_connection {
    name                           = "psc-${var.workload_name}-cosmos"
    private_connection_resource_id = azurerm_cosmosdb_account.tasks.id
    is_manual_connection           = false
    subresource_names              = ["Sql"]
  }

  private_dns_zone_group {
    name                 = "cosmos-private-dns-zone-group"
    private_dns_zone_ids = [azurerm_private_dns_zone.cosmos.id]
  }
}

resource "azurerm_key_vault" "capstone" {
  name                       = local.key_vault_name
  location                   = data.azurerm_resource_group.capstone.location
  resource_group_name        = data.azurerm_resource_group.capstone.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
  tags                       = local.common_tags
}

resource "azurerm_role_assignment" "terraform_key_vault_secrets_officer" {
  scope                = azurerm_key_vault.capstone.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "time_sleep" "wait_for_key_vault_rbac" {
  create_duration = "45s"

  depends_on = [azurerm_role_assignment.terraform_key_vault_secrets_officer]
}

resource "azurerm_key_vault_secret" "cosmos_connection" {
  name         = local.cosmos_secret_name
  value        = azurerm_cosmosdb_account.tasks.primary_sql_connection_string
  key_vault_id = azurerm_key_vault.capstone.id

  depends_on = [time_sleep.wait_for_key_vault_rbac]
}

resource "azurerm_log_analytics_workspace" "capstone" {
  name                = local.log_analytics_name
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_application_insights" "capstone" {
  name                = local.app_insights_name
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  workspace_id        = azurerm_log_analytics_workspace.capstone.id
  application_type    = "web"
  tags                = local.common_tags
}

resource "azurerm_service_plan" "api" {
  name                = local.app_service_plan_name
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.common_tags
}

resource "azurerm_storage_account" "frontend" {
  name                            = local.storage_account_name
  resource_group_name             = data.azurerm_resource_group.capstone.name
  location                        = data.azurerm_resource_group.capstone.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = true
  tags                            = local.common_tags
}

resource "azurerm_storage_account_static_website" "frontend" {
  storage_account_id = azurerm_storage_account.frontend.id
  index_document     = "index.html"
}

resource "azurerm_role_assignment" "terraform_storage_blob_contributor" {
  scope                = azurerm_storage_account.frontend.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_linux_web_app" "api" {
  name                = local.app_service_name
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  service_plan_id     = azurerm_service_plan.api.id
  https_only          = true
  tags                = local.common_tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on = false
    vnet_route_all_enabled = true

    application_stack {
      dotnet_version = "10.0"
    }

    cors {
      allowed_origins     = [trimsuffix(azurerm_storage_account.frontend.primary_web_endpoint, "/")]
      support_credentials = false
    }
  }

  app_settings = {
    CosmosDb__ConnectionString                 = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.cosmos_connection.versionless_id})"
    CosmosDb__DatabaseName                     = azurerm_cosmosdb_sql_database.tasks.name
    CosmosDb__ContainerName                    = azurerm_cosmosdb_sql_container.tasks.name
    APPLICATIONINSIGHTS_CONNECTION_STRING      = azurerm_application_insights.capstone.connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    EnableSwagger                              = "true"
    Cors__AllowedOrigins__0                    = trimsuffix(azurerm_storage_account.frontend.primary_web_endpoint, "/")
    WEBSITE_DNS_SERVER                         = "168.63.129.16"
  }

  depends_on = [
    azurerm_service_plan.api,
    azurerm_storage_account.frontend,
    azurerm_cosmosdb_sql_database.tasks,
    azurerm_cosmosdb_sql_container.tasks,
    azurerm_key_vault_secret.cosmos_connection
  ]
}

resource "azurerm_role_assignment" "api_key_vault_secrets_user" {
  scope                = azurerm_key_vault.capstone.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_linux_web_app.api.identity[0].principal_id
}

resource "azurerm_app_service_virtual_network_swift_connection" "api" {
  app_service_id = azurerm_linux_web_app.api.id
  subnet_id      = azurerm_subnet.app.id
}
