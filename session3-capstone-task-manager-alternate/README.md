# Session 3 Alternate Capstone — Container Task Manager

This capstone is an alternate version of the Session 3 Final Project. It replaces the C# App Service API with a **Python FastAPI microservice** running on **Azure Container Apps**, and adds a second internal microservice (`labels-api`) to demonstrate ACA service discovery. Public traffic flows through an **Application Gateway** with VNET integration; the API never has a public ACA endpoint.

## What this project builds

- **Frontend:** Static HTML/CSS/JavaScript task manager hosted on Azure Storage static website
- **API:** Python FastAPI microservice (`taskmanager-api`) on Azure Container Apps — internal ingress only, fronted by Application Gateway
- **Service discovery demo:** Python FastAPI microservice (`labels-api`) on Azure Container Apps — internal ingress only, callable only by `taskmanager-api` within the ACA environment
- **Database:** Azure Cosmos DB for NoSQL using serverless capacity with a private endpoint
- **Secrets:** Cosmos DB connection string in Azure Key Vault; Container App reads it via UAMI Key Vault secret reference
- **Identity:** User-Assigned Managed Identity shared by both Container Apps (AcrPull on ACR, Key Vault Secrets User on KV)
- **Networking:** VNet with three subnets (App Gateway, ACA environment, data); ACA environment with internal load balancer; App Gateway in dedicated subnet routing HTTPS to ACA internal FQDN; Cosmos DB private endpoint on data subnet
- **TLS:** Self-signed certificate generated in Key Vault, referenced by App Gateway via UAMI
- **CI/CD:** GitHub Actions builds Docker images via `az acr build`, pushes to ACR, and updates Container App revisions on every PR touching `src/`
- **Observability:** Application Insights connected to the `taskmanager-api` container

## Architecture

```text
[Browser]
    │ HTTPS (port 443)
    ▼
[Storage Account Static Website]  ← public, Azure-managed HTTPS
    │
    │ HTTPS API calls to App Gateway public IP / FQDN
    ▼
[Application Gateway Standard_v2]  ← snet-appgw /24, self-signed KV cert
    │ HTTPS/443 → ACA internal FQDN (resolved within VNet)
    ▼
[ACA Environment — internal load balancer]  ← snet-aca /23
    │
    ├─ taskmanager-api  (external_enabled=true  → reachable from App Gateway)
    │       │ http://ca-labels-<suffix>  (ACA internal service discovery)
    │       ▼
    │  labels-api       (external_enabled=false → reachable only within ACA env)
    │
    │ Key Vault secret reference via UAMI
    ▼
[Azure Key Vault]
    │ Cosmos DB connection string
    ▼
[Cosmos DB private endpoint]  ← snet-data /24
    │ Private DNS: privatelink.documents.azure.com
    ▼
[Cosmos DB for NoSQL — serverless]
```

## ACA service-to-service: how it works

Within an ACA environment, apps call each other using the app name as the hostname — no service mesh configuration, no DNS zone setup. The `taskmanager-api` container calls:

```
http://ca-labels-<suffix>/labels
```

ACA resolves the short name to the `labels-api` container within the same environment. The `labels-api` has `external_enabled = false`, so it is unreachable from the VNet or the internet — only other containers in the same environment can call it.

## Folder structure

```text
session-3-capstone-task-manager-alternate/
├── README.md
├── frontend/
│   ├── app.js            ← fetches /labels from API to populate status dropdown
│   ├── config.js         ← set apiBaseUrl to the App Gateway FQDN after deploy
│   ├── index.html
│   └── styles.css
├── infra/
│   └── terraform/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── providers.tf
│       ├── backend.tf
│       └── terraform.tfvars.example
└── src/
    ├── labels-api/
    │   ├── main.py
    │   ├── requirements.txt
    │   └── Dockerfile
    └── taskmanager-api/
        ├── main.py
        ├── requirements.txt
        └── Dockerfile
.github/
└── workflows/
    └── deploy-aca.yml
```

## Prerequisites

- Azure subscription access
- Azure CLI installed and authenticated (`az login`)
- Terraform CLI >= 1.6.0
- Docker Desktop (optional — only needed for local builds; `az acr build` builds in the cloud)
- PowerShell 7

## Step 0 — Create the resource group

```powershell
$location = "eastus"
$resourceGroupName = "rg-session3-capstone-alt"

az group create --name $resourceGroupName --location $location
```

## Step 1 — Deploy infrastructure with Terraform

From `infra/terraform`:

```powershell
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
# Edit terraform.tfvars and set github_repo = "your-org/your-repo"

terraform init
terraform apply -auto-approve
```

Terraform creates:

- VNet with three subnets: `snet-appgw`, `snet-aca`, `snet-data`
- NSGs for each subnet
- Cosmos DB serverless account, database, and container with private endpoint and private DNS
- Key Vault with self-signed TLS certificate (for App Gateway) and Cosmos DB connection string secret
- Log Analytics workspace and Application Insights
- Storage Account with static website enabled
- Azure Container Registry (Basic, admin disabled)
- User-Assigned Managed Identities for ACA workload and App Gateway
- Role assignments: AcrPull, Key Vault Secrets User, Key Vault Certificates Officer
- Azure Container App Environment (internal load balancer, `snet-aca`)
- Container Apps `labels-api` (internal only) and `taskmanager-api` (VNet-accessible) — both start with a placeholder image
- Application Gateway Standard_v2 with self-signed cert, routing HTTPS to `taskmanager-api`

Review outputs:

```powershell
terraform output
terraform output -raw api_url
terraform output -raw api_docs_url
terraform output -raw frontend_url
terraform output -raw acr_login_server
terraform output -raw aca_taskmanager_name
terraform output -raw aca_labels_name
```

## Step 2 — Build and push initial images to ACR

Terraform deploys the Container Apps with a Microsoft placeholder image. Replace both images with the real application using `az acr build` (cloud build — no local Docker required):

```powershell
$resourceGroupName = terraform output -raw resource_group_name
$acrName           = terraform output -raw acr_name
$taskmanagerName   = terraform output -raw aca_taskmanager_name
$labelsName        = terraform output -raw aca_labels_name

# Build and push both images
az acr build --registry $acrName --image "labels-api:latest"     ..\..\src\labels-api
az acr build --registry $acrName --image "taskmanager-api:latest" ..\..\src\taskmanager-api

# Point the Container Apps to the new images
$acrServer = terraform output -raw acr_login_server

az containerapp update `
  --name $labelsName `
  --resource-group $resourceGroupName `
  --image "${acrServer}/labels-api:latest"

az containerapp update `
  --name $taskmanagerName `
  --resource-group $resourceGroupName `
  --image "${acrServer}/taskmanager-api:latest"
```

Verify both apps are running:

```powershell
az containerapp show --name $taskmanagerName --resource-group $resourceGroupName --query "properties.latestRevisionFqdn" -o tsv
az containerapp show --name $labelsName      --resource-group $resourceGroupName --query "properties.runningStatus" -o tsv
```

## Step 3 — Test the API through App Gateway

The App Gateway uses a self-signed certificate. Browsers show a warning — click through (or use `-k` in curl for testing).

```powershell
$apiUrl = terraform output -raw api_url

# Health check
curl -k "$apiUrl/health"

# Get valid labels (demonstrates service-to-service call to labels-api)
curl -k "$apiUrl/labels"

# Create a task
curl -k -X POST "$apiUrl/tasks" `
  -H "Content-Type: application/json" `
  -d '{"title":"Verify ACA service discovery","description":"labels-api called internally","status":"todo"}'

# List tasks
curl -k "$apiUrl/tasks"
```

Open the interactive API docs:

```powershell
terraform output -raw api_docs_url
```

Note: the `GET /labels` endpoint shows `["todo", "in-progress", "done"]` returned by `labels-api`. The `POST /tasks` endpoint validates the submitted status against that list.

## Step 4 — Deploy the frontend

```powershell
$apiUrl              = terraform output -raw api_url
$storageAccountName  = terraform output -raw frontend_storage_account_name

# Write config.js pointing to the App Gateway URL
@"
window.APP_CONFIG = {
  apiBaseUrl: "$apiUrl"
};
"@ | Set-Content -Path ..\..\frontend\config.js

az storage blob upload-batch `
  --account-name $storageAccountName `
  --source ..\..\frontend `
  --destination '$web' `
  --auth-mode login `
  --overwrite
```

Open the frontend:

```powershell
terraform output -raw frontend_url
```

The status dropdown in the form is populated live by calling `GET /labels` → `taskmanager-api` → `labels-api`. Add a task, refresh the list, then confirm it appears in Cosmos DB Data Explorer.

## Step 5 — Set up GitHub Actions CI/CD

### Create the service principal and configure OIDC

```powershell
$subscriptionId    = az account show --query id -o tsv
$resourceGroupName = terraform output -raw resource_group_name
$acrName           = terraform output -raw acr_name

# Create app registration and service principal
$appId = az ad app create --display-name "sp-session3-alt-github-actions" --query appId -o tsv
az ad sp create --id $appId

$spObjectId = az ad sp show --id $appId --query id -o tsv

# Grant Contributor on the resource group (covers Container App updates)
az role assignment create `
  --assignee $spObjectId `
  --role Contributor `
  --scope "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"

# Federated credential for pull_request events
az ad app federated-credential create --id $appId --parameters '{
  "name": "github-pr",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:YOUR-ORG/YOUR-REPO:pull_request",
  "audiences": ["api://AzureADTokenExchange"]
}'

# Federated credential for push to main
az ad app federated-credential create --id $appId --parameters '{
  "name": "github-main",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:YOUR-ORG/YOUR-REPO:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

### Configure GitHub secrets

In your repository → Settings → Secrets and variables → Actions, add:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | `$appId` |
| `AZURE_TENANT_ID` | `az account show --query tenantId -o tsv` |
| `AZURE_SUBSCRIPTION_ID` | `$subscriptionId` |
| `ACR_LOGIN_SERVER` | `terraform output -raw acr_login_server` |
| `ACA_RESOURCE_GROUP` | `terraform output -raw resource_group_name` |
| `ACA_TASKMANAGER_NAME` | `terraform output -raw aca_taskmanager_name` |
| `ACA_LABELS_NAME` | `terraform output -raw aca_labels_name` |

### Trigger the workflow

Open a PR that touches any file under `session-3-capstone-task-manager-alternate/src/`. The workflow:

1. Logs in to Azure via OIDC (no stored credentials)
2. Builds and pushes both images to ACR using `az acr build` (cloud build)
3. Updates both Container App revisions to the new image tag
4. Posts a comment on the PR confirming deployment

On merge to `main`, the same steps run against the `latest` tag.

## Step 6 — Validate security controls

In the Azure portal:

1. Open the Container App Environment and confirm **Internal only** load balancer is enabled.
2. Open `taskmanager-api` Container App → **Ingress** and confirm external is enabled but the FQDN is an internal ACA domain (not a public endpoint).
3. Open `labels-api` Container App → **Ingress** and confirm external ingress is **disabled**.
4. Open **Container Apps** → `taskmanager-api` → **Secrets** and confirm the Cosmos DB connection string is a Key Vault reference, not a plaintext value.
5. Open **Key Vault** → **Access control (IAM)** and confirm the ACA UAMI has **Key Vault Secrets User**.
6. Open **Cosmos DB** → **Networking** and confirm public network access is disabled.
7. Open **Application Gateway** → **Backend health** and confirm the `taskmanager-api` backend is healthy.
8. Open **Application Insights** → **Live Metrics** and trigger a few API calls to see telemetry.

## Step 7 — Cleanup

```powershell
terraform -chdir=.\infra\terraform destroy -auto-approve
az group delete --name rg-session3-capstone-alt --yes --no-wait
```

## Facilitator notes

- `terraform apply` takes approximately 15–20 minutes due to the Application Gateway provisioning time (~10 min) and the Key Vault RBAC propagation sleeps.
- The Container Apps start with a Microsoft placeholder image. Step 2 is required before the API works end-to-end.
- The App Gateway self-signed certificate will trigger a browser security warning. Students should click "Advanced → Proceed" or use `-k` in curl during the lab. This is expected and intentional — it demonstrates that cert management is the next production step.
- If the App Gateway backend health shows **unhealthy** after first deploy, wait 2–3 minutes for the Container App to finish starting, then check again.
- `labels-api` has `min_replicas = 0`. On first call after idle, there is a cold start (~10s). If the status dropdown is empty on page load, refresh.
- Cosmos DB public access is disabled. Local debugging against the deployed database requires being on a network with VNet access.
