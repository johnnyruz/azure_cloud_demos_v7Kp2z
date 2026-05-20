#Requires -Version 7
<#
.SYNOPSIS
    Builds container images, updates Container Apps, and deploys the frontend.
    Assumes Terraform has already been applied and all infrastructure exists.

.DESCRIPTION
    Run this script from the session-3-capstone-task-manager-alternate directory.

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -SkipBuild       # skip ACR builds (re-use existing images)
    .\deploy.ps1 -SkipACADeploy   # skip Container App updates (keep existing images)
    .\deploy.ps1 -SkipFrontend    # skip frontend upload
#>
param(
    [switch]$SkipBuild,
    [switch]$SkipACADeploy,
    [switch]$SkipFrontend
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir  = $PSScriptRoot
$TfDir      = Join-Path $ScriptDir "infra\terraform"
$SrcDir     = Join-Path $ScriptDir "src"
$FrontendDir = Join-Path $ScriptDir "frontend"

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
function tf([string]$OutputName) {
    $val = az deployment group show 2>$null  # probe az; ignore result
    $val = terraform -chdir="$TfDir" output -raw $OutputName 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($val)) {
        Write-Error "Could not read Terraform output '$OutputName'. Make sure 'terraform apply' has completed in $TfDir"
    }
    return $val
}

# ---------------------------------------------------------------------------
# Read Terraform outputs
# ---------------------------------------------------------------------------
Write-Host "`n==> Reading Terraform outputs from $TfDir" -ForegroundColor Cyan

$resourceGroupName      = tf "resource_group_name"
$acrName                = tf "acr_name"
$acrServer              = tf "acr_login_server"
$taskmanagerName        = tf "aca_taskmanager_name"
$labelsName             = tf "aca_labels_name"
$apiUrl                 = tf "api_url"
$storageAccountName     = tf "frontend_storage_account_name"

Write-Host "  Resource Group : $resourceGroupName"
Write-Host "  ACR            : $acrServer"
Write-Host "  taskmanager-api: $taskmanagerName"
Write-Host "  labels-api     : $labelsName"
Write-Host "  API URL        : $apiUrl"
Write-Host "  Storage Account: $storageAccountName"

# ---------------------------------------------------------------------------
# Step 2 — Build images in ACR and update Container Apps
# ---------------------------------------------------------------------------
$timestamp = Get-Date -Format "yyyyMMdd-HHmm"

if (-not $SkipBuild) {
    Write-Host "`n==> Building and pushing images to ACR (tag: $timestamp)" -ForegroundColor Cyan

    Write-Host "  Building labels-api..."
    az acr build `
        --registry $acrName `
        --image "labels-api:$timestamp" `
        --image "labels-api:latest" `
        (Join-Path $SrcDir "labels-api")
    if ($LASTEXITCODE -ne 0) { Write-Error "ACR build failed for labels-api" }

    Write-Host "  Building taskmanager-api..."
    az acr build `
        --registry $acrName `
        --image "taskmanager-api:$timestamp" `
        --image "taskmanager-api:latest" `
        (Join-Path $SrcDir "taskmanager-api")
    if ($LASTEXITCODE -ne 0) { Write-Error "ACR build failed for taskmanager-api" }
}


if (-not $SkipACADeploy) {
    Write-Host "`n==> Updating Container Apps with new images (tag: $timestamp)" -ForegroundColor Cyan

    Write-Host "  Updating $labelsName..."
    az containerapp update `
        --name $labelsName `
        --resource-group $resourceGroupName `
        --image "${acrServer}/labels-api:$timestamp"
    if ($LASTEXITCODE -ne 0) { Write-Error "Container App update failed for $labelsName" }

    Write-Host "  Updating $taskmanagerName..."
    az containerapp update `
        --name $taskmanagerName `
        --resource-group $resourceGroupName `
        --image "${acrServer}/taskmanager-api:$timestamp"
    if ($LASTEXITCODE -ne 0) { Write-Error "Container App update failed for $taskmanagerName" }

    Write-Host "`n==> Verifying Container Apps" -ForegroundColor Cyan
    $tmFqdn = az containerapp show `
        --name $taskmanagerName `
        --resource-group $resourceGroupName `
        --query "properties.latestRevisionFqdn" -o tsv
    Write-Host "  taskmanager-api internal FQDN : $tmFqdn"

    $labelsStatus = az containerapp show `
        --name $labelsName `
        --resource-group $resourceGroupName `
        --query "properties.runningStatus" -o tsv
    Write-Host "  labels-api running status     : $labelsStatus"
} else {
    Write-Host "`n==> Skipping ACR build (-SkipBuild specified)" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 4 — Deploy frontend
# ---------------------------------------------------------------------------
if (-not $SkipFrontend) {
    Write-Host "`n==> Deploying frontend to storage account '$storageAccountName'" -ForegroundColor Cyan

    $configPath = Join-Path $FrontendDir "config.js"
    Write-Host "  Writing config.js with apiBaseUrl = $apiUrl"
    @"
window.APP_CONFIG = {
  apiBaseUrl: "$apiUrl"
};
"@ | Set-Content -Path $configPath -Encoding utf8

    Write-Host "  Uploading frontend files..."
    az storage blob upload-batch `
        --account-name $storageAccountName `
        --source $FrontendDir `
        --destination '$web' `
        --auth-mode login `
        --overwrite
    if ($LASTEXITCODE -ne 0) { Write-Error "Frontend upload failed" }

    $frontendUrl = tf "frontend_url"
    Write-Host "`n  Frontend URL: $frontendUrl" -ForegroundColor Green
} else {
    Write-Host "`n==> Skipping frontend deploy (-SkipFrontend specified)" -ForegroundColor Yellow
}

Write-Host "`n==> Deployment complete" -ForegroundColor Green
Write-Host "  API URL     : $apiUrl"
if (-not $SkipFrontend) {
    Write-Host "  Frontend URL: $(tf 'frontend_url')"
}
Write-Host ""
