# ── GitHub Actions OIDC Identity ────────────────────────────────────────────
#
# Creates the Entra ID App Registration + Service Principal that GitHub Actions
# authenticates as via OIDC (no client secrets). Two federated credentials cover
# the two workflow triggers in deploy-aca.yml: push to main and pull_request.
#
# Role assignments are scoped as narrowly as possible:
#   - Contributor on ACR       → needed for `az acr build` (scheduleRun permission)
#   - Contributor on each ACA  → needed for `az containerapp update`

locals {
  github_app_name = "sp-github-actions-${var.workload_name}-deploy"
}

resource "azuread_application" "github_actions" {
  display_name = local.github_app_name
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
}

# Push to main branch
resource "azuread_application_federated_identity_credential" "push_main" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-push-main"
  description    = "GitHub Actions push to main branch"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/main"
  audiences      = ["api://AzureADTokenExchange"]
}

# Pull request events
resource "azuread_application_federated_identity_credential" "pull_request" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-pull-request"
  description    = "GitHub Actions pull_request event"
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:pull_request"
  audiences      = ["api://AzureADTokenExchange"]
}

# ── RBAC ─────────────────────────────────────────────────────────────────────

# az acr build queues an ACR Task run — requires scheduleRun which is in Contributor, not AcrPush
resource "azurerm_role_assignment" "github_actions_acr" {
  scope                = azurerm_container_registry.capstone.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "github_actions_aca_taskmanager" {
  scope                = azurerm_container_app.taskmanager.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

resource "azurerm_role_assignment" "github_actions_aca_labels" {
  scope                = azurerm_container_app.labels.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}
