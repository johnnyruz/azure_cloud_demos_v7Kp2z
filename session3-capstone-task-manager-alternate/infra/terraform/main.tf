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
  vnet_name             = "vnet-${var.workload_name}-${var.environment}"
  cosmosdb_account_name = substr("${var.workload_name}cosmos${local.unique_suffix}", 0, 44)
  key_vault_name        = substr("kv-${var.workload_name}-${local.unique_suffix}", 0, 24)
  storage_account_name  = substr("st${var.workload_name}${local.unique_suffix}", 0, 24)
  log_analytics_name    = "log-${var.workload_name}-${local.unique_suffix}"
  app_insights_name     = "appi-${var.workload_name}-${local.unique_suffix}"
  acr_name              = substr("acr${var.workload_name}${local.unique_suffix}", 0, 50)
  aca_env_name          = "cae-${var.workload_name}-${local.unique_suffix}"
  aca_taskmanager_name  = "ca-taskmanager-${local.unique_suffix}"
  aca_labels_name       = "ca-labels-${local.unique_suffix}"
  appgw_name            = "agw-${var.workload_name}-${local.unique_suffix}"
  appgw_pip_name        = "pip-${var.workload_name}-appgw-${local.unique_suffix}"
  appgw_dns_label       = "${var.workload_name}${local.unique_suffix}"
  cosmos_secret_name    = "cosmosdb-connection-string"

  common_tags = {
    environment = var.environment
    workshop    = "cloud-journey-session-3-alternate"
    managed_by  = "terraform"
  }
}

# ── Networking ──────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "capstone" {
  name                = local.vnet_name
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  address_space       = var.vnet_address_space
  tags                = local.common_tags
}

# App Gateway subnet — Standard_v2 requires dedicated /24 minimum
resource "azurerm_network_security_group" "appgw" {
  name                = "nsg-${var.workload_name}-appgw-${local.unique_suffix}"
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-HTTPS-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  # Required for App Gateway v2 infrastructure communication
  security_rule {
    name                       = "Allow-GatewayManager-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-AzureLoadBalancer-Inbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet" "appgw" {
  name                 = "snet-appgw"
  resource_group_name  = data.azurerm_resource_group.capstone.name
  virtual_network_name = azurerm_virtual_network.capstone.name
  address_prefixes     = [var.appgw_subnet_prefix]
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  subnet_id                 = azurerm_subnet.appgw.id
  network_security_group_id = azurerm_network_security_group.appgw.id
}

# ACA environment subnet — consumption plan, delegated to Microsoft.App/environments
resource "azurerm_network_security_group" "aca" {
  name                = "nsg-${var.workload_name}-aca-${local.unique_suffix}"
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-AppGW-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.appgw_subnet_prefix
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet" "aca" {
  name                 = "snet-aca"
  resource_group_name  = data.azurerm_resource_group.capstone.name
  virtual_network_name = azurerm_virtual_network.capstone.name
  address_prefixes     = [var.aca_subnet_prefix]

  delegation {
    name = "aca-env-delegation"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_subnet_network_security_group_association" "aca" {
  subnet_id                 = azurerm_subnet.aca.id
  network_security_group_id = azurerm_network_security_group.aca.id
}

# Data subnet — hosts the Cosmos DB private endpoint
resource "azurerm_network_security_group" "data" {
  name                = "nsg-${var.workload_name}-data-${local.unique_suffix}"
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags

  security_rule {
    name                       = "Allow-ACA-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = var.aca_subnet_prefix
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

resource "azurerm_subnet" "data" {
  name                              = "snet-data"
  resource_group_name               = data.azurerm_resource_group.capstone.name
  virtual_network_name              = azurerm_virtual_network.capstone.name
  address_prefixes                  = [var.data_subnet_prefix]
  private_endpoint_network_policies = "Disabled"
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.data.id
  network_security_group_id = azurerm_network_security_group.data.id
}

# ── Cosmos DB ───────────────────────────────────────────────────────────────

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

# ── Key Vault ───────────────────────────────────────────────────────────────

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

resource "azurerm_role_assignment" "terraform_key_vault_certificates_officer" {
  scope                = azurerm_key_vault.capstone.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Wait for both KV role assignments to propagate before writing secrets or certs
resource "time_sleep" "wait_for_key_vault_rbac" {
  create_duration = "60s"

  depends_on = [
    azurerm_role_assignment.terraform_key_vault_secrets_officer,
    azurerm_role_assignment.terraform_key_vault_certificates_officer,
  ]
}

resource "azurerm_key_vault_secret" "cosmos_connection" {
  name         = local.cosmos_secret_name
  value        = azurerm_cosmosdb_account.tasks.primary_sql_connection_string
  key_vault_id = azurerm_key_vault.capstone.id

  depends_on = [time_sleep.wait_for_key_vault_rbac]
}

# Self-signed TLS certificate for the App Gateway HTTPS listener.
# App Gateway reads it from Key Vault via its User-Assigned Managed Identity.
resource "azurerm_key_vault_certificate" "appgw_tls" {
  name         = "appgw-tls"
  key_vault_id = azurerm_key_vault.capstone.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }
    key_properties {
      exportable = true
      key_size   = 2048
      key_type   = "RSA"
      reuse_key  = true
    }
    secret_properties {
      content_type = "application/x-pkcs12"
    }
    x509_certificate_properties {
      subject            = "CN=${local.appgw_dns_label}.${var.location}.cloudapp.azure.com"
      validity_in_months = 12
      key_usage          = ["digitalSignature", "keyEncipherment"]
    }
  }

  depends_on = [time_sleep.wait_for_key_vault_rbac]
}

# ── Observability ───────────────────────────────────────────────────────────

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

# ── Storage (frontend static website) ──────────────────────────────────────

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

# ── Container Registry ──────────────────────────────────────────────────────

resource "azurerm_container_registry" "capstone" {
  name                = local.acr_name
  resource_group_name = data.azurerm_resource_group.capstone.name
  location            = data.azurerm_resource_group.capstone.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.common_tags
}

# ── Managed Identities ──────────────────────────────────────────────────────

# Shared UAMI for both Container Apps — owns AcrPull and KV Secrets User
resource "azurerm_user_assigned_identity" "aca_workload" {
  name                = "mid-${var.workload_name}-aca-${local.unique_suffix}"
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags
}

# UAMI for App Gateway — reads the TLS certificate from Key Vault
resource "azurerm_user_assigned_identity" "appgw" {
  name                = "mid-${var.workload_name}-appgw-${local.unique_suffix}"
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags
}

resource "azurerm_role_assignment" "aca_acr_pull" {
  scope                = azurerm_container_registry.capstone.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.aca_workload.principal_id
}

resource "azurerm_role_assignment" "aca_kv_secrets_user" {
  scope                = azurerm_key_vault.capstone.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.aca_workload.principal_id
}

resource "azurerm_role_assignment" "appgw_kv_secrets_user" {
  scope                = azurerm_key_vault.capstone.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw.principal_id
}

# Extra propagation time for the App Gateway identity before App Gateway reads the cert
resource "time_sleep" "wait_for_appgw_kv_rbac" {
  create_duration = "30s"
  depends_on      = [azurerm_role_assignment.appgw_kv_secrets_user]
}

# ── Azure Container Apps Environment ────────────────────────────────────────

resource "azurerm_container_app_environment" "capstone" {
  name                           = local.aca_env_name
  location                       = data.azurerm_resource_group.capstone.location
  resource_group_name            = data.azurerm_resource_group.capstone.name
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.capstone.id
  infrastructure_subnet_id       = azurerm_subnet.aca.id
  internal_load_balancer_enabled = true
  tags                           = local.common_tags

  workload_profile {
    maximum_count         = 0
    minimum_count         = 0
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  identity {
    type = "SystemAssigned"
  }
}

# Private DNS zone so VNet resources (App Gateway) can resolve ACA internal FQDNs.
# Internal ACA environments get a static IP but Azure does not auto-register the
# environment domain in VNet DNS — without this, App Gateway can't reach the backend.
resource "azurerm_private_dns_zone" "aca" {
  name                = azurerm_container_app_environment.capstone.default_domain
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "aca" {
  name                  = "pdnslink-aca-${local.unique_suffix}"
  resource_group_name   = data.azurerm_resource_group.capstone.name
  private_dns_zone_name = azurerm_private_dns_zone.aca.name
  virtual_network_id    = azurerm_virtual_network.capstone.id
  registration_enabled  = false
  tags                  = local.common_tags
}

resource "azurerm_private_dns_a_record" "aca_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.aca.name
  resource_group_name = data.azurerm_resource_group.capstone.name
  ttl                 = 300
  records             = [azurerm_container_app_environment.capstone.static_ip_address]
}

# ── Container App: labels-api (internal only) ───────────────────────────────
# Not reachable from the VNet or internet. Only callable by other apps within
# the same ACA environment via http://<app-name>.

resource "azurerm_container_app" "labels" {
  name                         = local.aca_labels_name
  container_app_environment_id = azurerm_container_app_environment.capstone.id
  resource_group_name          = data.azurerm_resource_group.capstone.name
  revision_mode                = "Single"
  tags                         = local.common_tags
  workload_profile_name        = "Consumption"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca_workload.id]
  }

  registry {
    server   = azurerm_container_registry.capstone.login_server
    identity = azurerm_user_assigned_identity.aca_workload.id
  }

  ingress {
    external_enabled = false
    target_port      = 8000
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  template {
    min_replicas = 0
    max_replicas = 3

    container {
      name   = "labels-api"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.25
      memory = "0.5Gi"

      liveness_probe {
        failure_count_threshold = 3
        initial_delay           = 0
        interval_seconds        = 10
        port                    = 8000
        timeout                 = 5
        transport               = "TCP"
      }

      readiness_probe {
        failure_count_threshold = 48
        initial_delay           = 0
        interval_seconds        = 5
        port                    = 8000
        success_count_threshold = 1
        timeout                 = 5
        transport               = "TCP"
      }

      startup_probe {
        failure_count_threshold = 240
        initial_delay           = 1
        interval_seconds        = 1
        port                    = 8000
        timeout                 = 3
        transport               = "TCP"
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [azurerm_role_assignment.aca_acr_pull]
}

# ── Container App: taskmanager-api (VNet-accessible via App Gateway) ─────────
# external_enabled = true on an internal-LB environment means the app is
# reachable from within the VNet (App Gateway), but not from the public internet.

resource "azurerm_container_app" "taskmanager" {
  name                         = local.aca_taskmanager_name
  container_app_environment_id = azurerm_container_app_environment.capstone.id
  resource_group_name          = data.azurerm_resource_group.capstone.name
  revision_mode                = "Single"
  tags                         = local.common_tags
  workload_profile_name        = "Consumption"

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aca_workload.id]
  }

  registry {
    server   = azurerm_container_registry.capstone.login_server
    identity = azurerm_user_assigned_identity.aca_workload.id
  }

  ingress {
    external_enabled = true
    target_port      = 8000
    transport        = "http"

    traffic_weight {
      percentage      = 100
      latest_revision = true
    }
  }

  secret {
    name                = "cosmos-connection-string"
    identity            = azurerm_user_assigned_identity.aca_workload.id
    key_vault_secret_id = azurerm_key_vault_secret.cosmos_connection.versionless_id
  }

  template {
    min_replicas = 1
    max_replicas = 5

    container {
      name   = "taskmanager-api"
      image  = "mcr.microsoft.com/azuredocs/containerapps-helloworld:latest"
      cpu    = 0.5
      memory = "1Gi"

      liveness_probe {
        failure_count_threshold = 3
        initial_delay           = 0
        interval_seconds        = 10
        port                    = 8000
        timeout                 = 5
        transport               = "TCP"
      }

      readiness_probe {
        failure_count_threshold = 48
        initial_delay           = 0
        interval_seconds        = 5
        port                    = 8000
        success_count_threshold = 1
        timeout                 = 5
        transport               = "TCP"
      }

      startup_probe {
        failure_count_threshold = 240
        initial_delay           = 1
        interval_seconds        = 1
        port                    = 8000
        timeout                 = 3
        transport               = "TCP"
      }

      env {
        name        = "COSMOS_DB_CONNECTION_STRING"
        secret_name = "cosmos-connection-string"
      }
      env {
        name  = "COSMOSDB__DATABASE_NAME"
        value = azurerm_cosmosdb_sql_database.tasks.name
      }
      env {
        name  = "COSMOSDB__CONTAINER_NAME"
        value = azurerm_cosmosdb_sql_container.tasks.name
      }
      env {
        name  = "LABELS_SERVICE_URL"
        value = "http://${local.aca_labels_name}"
      }
      env {
        name  = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        value = azurerm_application_insights.capstone.connection_string
      }
      env {
        name  = "CORS__ALLOWED_ORIGINS"
        value = trimsuffix(azurerm_storage_account.frontend.primary_web_endpoint, "/")
      }
    }
  }

  lifecycle {
    ignore_changes = [template[0].container[0].image]
  }

  depends_on = [
    azurerm_role_assignment.aca_acr_pull,
    azurerm_role_assignment.aca_kv_secrets_user,
    azurerm_container_app.labels,
  ]
}

# ── Application Gateway ──────────────────────────────────────────────────────

resource "azurerm_public_ip" "appgw" {
  name                = local.appgw_pip_name
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = local.appgw_dns_label
  tags                = local.common_tags
}

resource "azurerm_application_gateway" "capstone" {
  name                = local.appgw_name
  location            = data.azurerm_resource_group.capstone.location
  resource_group_name = data.azurerm_resource_group.capstone.name
  tags                = local.common_tags

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.appgw.id]
  }

  sku {
    name = "Standard_v2"
    tier = "Standard_v2"
  }

  autoscale_configuration {
    min_capacity = 1
    max_capacity = 2
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = "https-443"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "appgw-public-frontend"
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Self-signed certificate stored in Key Vault, read via App Gateway UAMI
  ssl_certificate {
    name                = "appgw-tls"
    key_vault_secret_id = azurerm_key_vault_certificate.appgw_tls.versionless_secret_id
  }

  backend_address_pool {
    name  = "aca-taskmanager-pool"
    fqdns = [azurerm_container_app.taskmanager.ingress[0].fqdn]
  }

  # ACA internal ingress exposes HTTPS/443 even within the VNet
  backend_http_settings {
    name                                = "aca-https-settings"
    cookie_based_affinity               = "Disabled"
    port                                = 443
    protocol                            = "Https"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = "aca-health-probe"
  }

  probe {
    name                                      = "aca-health-probe"
    protocol                                  = "Https"
    path                                      = "/health"
    interval                                  = 30
    timeout                                   = 10
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  http_listener {
    name                           = "https-listener"
    frontend_ip_configuration_name = "appgw-public-frontend"
    frontend_port_name             = "https-443"
    protocol                       = "Https"
    ssl_certificate_name           = "appgw-tls"
  }

  request_routing_rule {
    name                       = "aca-routing-rule"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "https-listener"
    backend_address_pool_name  = "aca-taskmanager-pool"
    backend_http_settings_name = "aca-https-settings"
  }

  depends_on = [
    time_sleep.wait_for_appgw_kv_rbac,
    azurerm_key_vault_certificate.appgw_tls,
    azurerm_container_app.taskmanager,
  ]
}
