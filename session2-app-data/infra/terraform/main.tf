resource "random_string" "suffix" {
  length  = 8
  lower   = true
  numeric = true
  special = false
  upper   = false
}

locals {
  unique_suffix          = random_string.suffix.result
  cosmosdb_account_name  = substr("${var.workload_name}cosmos${local.unique_suffix}", 0, 44)
  app_service_plan_name  = "asp-${var.workload_name}-${local.unique_suffix}"
  app_service_name       = substr("${var.workload_name}-api-${local.unique_suffix}", 0, 60)
  log_analytics_name     = "log-${var.workload_name}-${local.unique_suffix}"
  app_insights_name      = "appi-${var.workload_name}-${local.unique_suffix}"

  common_tags = {
    environment = var.environment
    workshop    = "cloud-journey-session-2"
    managed_by  = "terraform"
  }
}

data "azurerm_resource_group" "demo" {
  name     = var.resource_group_name
}

resource "azurerm_cosmosdb_account" "demo" {
  name                = local.cosmosdb_account_name
  location            = data.azurerm_resource_group.demo.location
  resource_group_name = data.azurerm_resource_group.demo.name
  offer_type          = "Standard"
  kind                = "GlobalDocumentDB"

  capabilities {
    name = "EnableServerless"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = data.azurerm_resource_group.demo.location
    failover_priority = 0
    zone_redundant    = false
  }

  tags = local.common_tags
}

resource "azurerm_cosmosdb_sql_database" "training" {
  name                = var.database_name
  resource_group_name = data.azurerm_resource_group.demo.name
  account_name        = azurerm_cosmosdb_account.demo.name
}

resource "azurerm_cosmosdb_sql_container" "items" {
  name                = var.container_name
  resource_group_name = data.azurerm_resource_group.demo.name
  account_name        = azurerm_cosmosdb_account.demo.name
  database_name       = azurerm_cosmosdb_sql_database.training.name
  partition_key_paths = [var.partition_key_path]
}

resource "azurerm_log_analytics_workspace" "demo" {
  name                = local.log_analytics_name
  location            = data.azurerm_resource_group.demo.location
  resource_group_name = data.azurerm_resource_group.demo.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.common_tags
}

resource "azurerm_application_insights" "demo" {
  name                = local.app_insights_name
  location            = data.azurerm_resource_group.demo.location
  resource_group_name = data.azurerm_resource_group.demo.name
  workspace_id        = azurerm_log_analytics_workspace.demo.id
  application_type    = "web"
  tags                = local.common_tags
}

resource "azurerm_service_plan" "api" {
  name                = local.app_service_plan_name
  location            = data.azurerm_resource_group.demo.location
  resource_group_name = data.azurerm_resource_group.demo.name
  os_type             = "Linux"
  sku_name            = var.app_service_sku
  tags                = local.common_tags
}

resource "azurerm_linux_web_app" "api" {
  name                = local.app_service_name
  location            = data.azurerm_resource_group.demo.location
  resource_group_name = data.azurerm_resource_group.demo.name
  service_plan_id     = azurerm_service_plan.api.id
  https_only          = true
  tags                = local.common_tags

  site_config {
    always_on = false

    application_stack {
      dotnet_version = "10.0"
    }
  }

  app_settings = {
    CosmosDb__ConnectionString              = azurerm_cosmosdb_account.demo.primary_sql_connection_string
    CosmosDb__DatabaseName                  = azurerm_cosmosdb_sql_database.training.name
    CosmosDb__ContainerName                 = azurerm_cosmosdb_sql_container.items.name
    APPLICATIONINSIGHTS_CONNECTION_STRING   = azurerm_application_insights.demo.connection_string
    ApplicationInsightsAgent_EXTENSION_VERSION = "~3"
    EnableSwagger                           = "true"
  }
}
