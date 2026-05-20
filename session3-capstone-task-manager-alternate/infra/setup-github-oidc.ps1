<#
.SYNOPSIS
    Bootstraps Azure AD OIDC trust for GitHub Actions → Azure Container Apps deployments.

.DESCRIPTION
    Creates an Azure AD App Registration with two Federated Identity Credentials
    (branch push + pull_request), assigns the minimum required RBAC roles, and
    outputs the seven GitHub secrets the deploy-aca.yml workflow expects.

    Run this once after `terraform apply`. Re-running is idempotent: existing
    federated credentials and role assignments are left unchanged.

    Prerequisites
    -------------
    - Azure CLI installed and logged in (`az login`)
    - Sufficient permissions: Application Administrator (Entra ID) + Owner/User Access
      Administrator on the target subscription or resource group
    - (Optional) GitHub CLI (`gh`) logged in to set secrets automatically

.PARAMETER GitHubRepo
    Repository in "owner/repo" format, e.g. "myorg/myrepo". Reads from
    terraform.tfvars automatically if not supplied.

.PARAMETER SubscriptionId
    Azure subscription ID. Defaults to the current az CLI subscription.

.PARAMETER ResourceGroupName
    Resource group containing the ACA and ACR resources. Reads from
    terraform.tfvars automatically if not supplied.

.PARAMETER AppName
    Display name for the new App Registration.
    Default: "sp-github-actions-<workload>-deploy"

.PARAMETER MainBranch
    Branch that triggers push-based deploys. Default: "main".

.PARAMETER SetGitHubSecrets
    When specified, sets the secrets automatically via the GitHub CLI.

.EXAMPLE
    # Fully automatic (reads tfvars, sets GH secrets via gh CLI)
    .\setup-github-oidc.ps1 -SetGitHubSecrets

.EXAMPLE
    # Manual override
    .\setup-github-oidc.ps1 -GitHubRepo "myorg/myrepo" -ResourceGroupName "rg-JRuzick" -SetGitHubSecrets
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$GitHubRepo,
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$AppName,
    [string]$MainBranch = "main",
    [switch]$SetGitHubSecrets
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step([string]$msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Skip([string]$msg) { Write-Host "    [--] $msg" -ForegroundColor DarkGray }

function Assert-AzCli {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw "Azure CLI not found. Install from https://aka.ms/installazurecliwindows"
    }
}

function Read-TfVarsValue([string]$TfVarsPath, [string]$Key) {
    if (-not (Test-Path $TfVarsPath)) { return $null }
    $line = Select-String -Path $TfVarsPath -Pattern "^\s*${Key}\s*=" | Select-Object -First 1
    if (-not $line) { return $null }
    # Extract value between quotes or bare value
    if ($line.Line -match '=\s*"([^"]+)"') { return $Matches[1] }
    if ($line.Line -match '=\s*(\S+)')      { return $Matches[1] }
    return $null
}

# ── Resolve script directory and tfvars path ─────────────────────────────────

$scriptDir  = $PSScriptRoot
$tfvarsPath = Join-Path $scriptDir "terraform\terraform.tfvars"

Write-Step "Reading Terraform variables from $tfvarsPath"

if (-not $GitHubRepo) {
    $GitHubRepo = Read-TfVarsValue $tfvarsPath "github_repo"
    if (-not $GitHubRepo -or $GitHubRepo -eq "your-org/your-repo") {
        throw "GitHubRepo is required. Set github_repo in terraform.tfvars or pass -GitHubRepo 'owner/repo'."
    }
}

if (-not $ResourceGroupName) {
    $ResourceGroupName = Read-TfVarsValue $tfvarsPath "resource_group_name"
    if (-not $ResourceGroupName) {
        throw "ResourceGroupName is required. Set resource_group_name in terraform.tfvars or pass -ResourceGroupName."
    }
}

$workloadName = Read-TfVarsValue $tfvarsPath "workload_name"
if (-not $AppName) {
    $suffix   = if ($workloadName) { $workloadName } else { "aca" }
    $AppName  = "sp-github-actions-${suffix}-deploy"
}

Write-Ok "GitHub repo   : $GitHubRepo"
Write-Ok "Resource group: $ResourceGroupName"
Write-Ok "App name      : $AppName"

# ── Verify Azure CLI ──────────────────────────────────────────────────────────

Assert-AzCli

Write-Step "Resolving Azure subscription"

if (-not $SubscriptionId) {
    $SubscriptionId = (az account show --query id -o tsv 2>$null)
    if (-not $SubscriptionId) {
        throw "Not logged in to Azure CLI. Run: az login"
    }
}

$tenantId = (az account show --subscription $SubscriptionId --query tenantId -o tsv)
Write-Ok "Subscription: $SubscriptionId"
Write-Ok "Tenant      : $tenantId"

# ── Discover Terraform outputs ────────────────────────────────────────────────

Write-Step "Reading Terraform outputs (az acr / container app names)"

$tfDir = Join-Path $scriptDir "terraform"

Push-Location $tfDir
try {
    $tfOutputJson = terraform output -json 2>$null | ConvertFrom-Json
} catch {
    $tfOutputJson = $null
} finally {
    Pop-Location
}

function Get-TfOutput([string]$key) {
    if ($tfOutputJson -and $tfOutputJson.PSObject.Properties[$key]) {
        return $tfOutputJson.$key.value
    }
    return $null
}

$acrLoginServer      = Get-TfOutput "acr_login_server"
$acrName             = Get-TfOutput "acr_name"
$acaTaskManagerName  = Get-TfOutput "aca_taskmanager_name"
$acaLabelsName       = Get-TfOutput "aca_labels_name"

if (-not $acrLoginServer -or -not $acrName -or -not $acaTaskManagerName -or -not $acaLabelsName) {
    Write-Warning "Could not read all Terraform outputs. Have you run 'terraform apply'?"
    Write-Warning "Attempting to discover resources by listing from Azure..."

    # Fallback: list ACR and Container Apps in the resource group
    $acrList = az acr list --resource-group $ResourceGroupName --query "[].{name:name,loginServer:loginServer}" -o json | ConvertFrom-Json
    if ($acrList.Count -eq 0) { throw "No ACR found in resource group $ResourceGroupName" }
    if ($acrList.Count -gt 1) { Write-Warning "Multiple ACRs found; using the first one." }
    $acrName        = $acrList[0].name
    $acrLoginServer = $acrList[0].loginServer

    $caList = az containerapp list --resource-group $ResourceGroupName --query "[].name" -o json | ConvertFrom-Json
    $acaTaskManagerName = $caList | Where-Object { $_ -like "*taskmanager*" } | Select-Object -First 1
    $acaLabelsName      = $caList | Where-Object { $_ -like "*labels*" }      | Select-Object -First 1

    if (-not $acaTaskManagerName -or -not $acaLabelsName) {
        throw "Could not resolve Container App names. Pass them as parameters or ensure 'terraform apply' has completed."
    }
}

Write-Ok "ACR login server    : $acrLoginServer"
Write-Ok "ACR name            : $acrName"
Write-Ok "ACA taskmanager-api : $acaTaskManagerName"
Write-Ok "ACA labels-api      : $acaLabelsName"

# ── Create App Registration ───────────────────────────────────────────────────

Write-Step "Creating App Registration: $AppName"

$existingApp = az ad app list --display-name $AppName --query "[0].appId" -o tsv 2>$null

if ($existingApp) {
    $clientId = $existingApp
    Write-Skip "App Registration already exists (appId: $clientId)"
} else {
    $clientId = az ad app create --display-name $AppName --query appId -o tsv
    Write-Ok "Created app registration (appId: $clientId)"
}

# ── Create Service Principal ──────────────────────────────────────────────────

Write-Step "Ensuring Service Principal exists"

$spId = az ad sp show --id $clientId --query id -o tsv 2>$null

if ($spId) {
    Write-Skip "Service Principal already exists (objectId: $spId)"
} else {
    $spId = az ad sp create --id $clientId --query id -o tsv
    Write-Ok "Created Service Principal (objectId: $spId)"
    # Brief wait for SP to propagate before role assignments
    Write-Host "    Waiting 15 s for SP to propagate..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 15
}

# ── Federated Identity Credentials ───────────────────────────────────────────

Write-Step "Configuring Federated Identity Credentials"

function Set-FederatedCredential([string]$credName, [string]$subject, [string]$description) {
    $existing = az ad app federated-credential list --id $clientId --query "[?name=='$credName'].id" -o tsv 2>$null
    if ($existing) {
        Write-Skip "Federated credential '$credName' already exists"
        return
    }

    $credBody = @{
        name        = $credName
        issuer      = "https://token.actions.githubusercontent.com"
        subject     = $subject
        description = $description
        audiences   = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Compress

    az ad app federated-credential create --id $clientId --parameters $credBody | Out-Null
    Write-Ok "Created federated credential: $credName"
    Write-Ok "  Subject: $subject"
}

# Push to main branch
Set-FederatedCredential `
    -credName    "github-push-$($MainBranch -replace '[^a-zA-Z0-9]','-')" `
    -subject     "repo:${GitHubRepo}:ref:refs/heads/${MainBranch}" `
    -description "GitHub Actions push to $MainBranch branch"

# Pull requests (any PR against the repo)
Set-FederatedCredential `
    -credName    "github-pull-request" `
    -subject     "repo:${GitHubRepo}:pull_request" `
    -description "GitHub Actions pull_request event"

# ── RBAC Role Assignments ─────────────────────────────────────────────────────

Write-Step "Assigning RBAC roles"

$subscriptionScope   = "/subscriptions/${SubscriptionId}"
$rgScope             = "${subscriptionScope}/resourceGroups/${ResourceGroupName}"

$acrResourceId       = (az acr show --name $acrName --resource-group $ResourceGroupName --query id -o tsv)
$caTaskmanagerResId  = (az containerapp show --name $acaTaskManagerName --resource-group $ResourceGroupName --query id -o tsv)
$caLabelsResId       = (az containerapp show --name $acaLabelsName --resource-group $ResourceGroupName --query id -o tsv)

function Set-RoleAssignment([string]$scope, [string]$role) {
    $existing = az role assignment list --assignee $spId --scope $scope --role $role --query "[0].id" -o tsv 2>$null
    if ($existing) {
        Write-Skip "Role '$role' on scope already assigned"
        return
    }
    az role assignment create --assignee $spId --scope $scope --role $role | Out-Null
    Write-Ok "Assigned '$role' on $scope"
}

# az acr build needs Contributor on the ACR (AcrPush alone lacks scheduleRun permission)
Set-RoleAssignment -scope $acrResourceId -role "Contributor"

# az containerapp update needs Contributor on each Container App
Set-RoleAssignment -scope $caTaskmanagerResId -role "Contributor"
Set-RoleAssignment -scope $caLabelsResId      -role "Contributor"

# ── Collect Secret Values ─────────────────────────────────────────────────────

$secrets = [ordered]@{
    AZURE_CLIENT_ID       = $clientId
    AZURE_TENANT_ID       = $tenantId
    AZURE_SUBSCRIPTION_ID = $SubscriptionId
    ACR_LOGIN_SERVER      = $acrLoginServer
    ACA_RESOURCE_GROUP    = $ResourceGroupName
    ACA_TASKMANAGER_NAME  = $acaTaskManagerName
    ACA_LABELS_NAME       = $acaLabelsName
}

# ── Optionally Set GitHub Secrets ─────────────────────────────────────────────

if ($SetGitHubSecrets) {
    Write-Step "Setting GitHub repository secrets via gh CLI"

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Warning "GitHub CLI (gh) not found. Skipping automatic secret setup."
        Write-Warning "Install from https://cli.github.com and run 'gh auth login'."
    } else {
        foreach ($kv in $secrets.GetEnumerator()) {
            gh secret set $kv.Key --repo $GitHubRepo --body $kv.Value
            Write-Ok "Set secret: $($kv.Key)"
        }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host " GitHub Secrets to configure in: https://github.com/$GitHubRepo/settings/secrets/actions" -ForegroundColor Yellow
Write-Host "════════════════════════════════════════════════════════════════" -ForegroundColor Yellow

foreach ($kv in $secrets.GetEnumerator()) {
    Write-Host ("  {0,-25} = {1}" -f $kv.Key, $kv.Value) -ForegroundColor White
}

Write-Host ""
Write-Host " Federated credential subjects configured:" -ForegroundColor Yellow
Write-Host "  repo:${GitHubRepo}:ref:refs/heads/${MainBranch}  (push events)" -ForegroundColor White
Write-Host "  repo:${GitHubRepo}:pull_request                   (PR events)"   -ForegroundColor White
Write-Host ""
Write-Host " RBAC assignments:" -ForegroundColor Yellow
Write-Host "  Contributor -> ACR ($acrName)"                   -ForegroundColor White
Write-Host "  Contributor -> Container App ($acaTaskManagerName)" -ForegroundColor White
Write-Host "  Contributor -> Container App ($acaLabelsName)"      -ForegroundColor White
Write-Host ""
Write-Host " Next: push a commit to '$MainBranch' or open a PR to trigger the workflow." -ForegroundColor Green
Write-Host ""
