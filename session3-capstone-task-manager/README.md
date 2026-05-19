# Session 3 Capstone — Serverless Task Manager

This capstone supports Session 3 Block 4: **Capstone Final Project**.

Participants deploy a production-adjacent Azure application with Terraform, then deploy a C# API and a static frontend that work together through a secured cloud backend.

## What this project builds

- **Frontend:** Static HTML/CSS/JavaScript task manager hosted from Azure Storage static website
- **API:** C# ASP.NET Core Web API hosted on Azure App Service
- **Database:** Azure Cosmos DB for NoSQL using serverless capacity
- **Secrets:** Cosmos DB connection string stored in Azure Key Vault
- **Identity:** App Service system-assigned Managed Identity reads the Key Vault secret
- **Networking:** VNet with app and data subnets, App Service VNet integration, Cosmos DB private endpoint, and private DNS
- **Observability:** Application Insights connected to the API
- **IaC:** Terraform AzureRM provider

## Architecture

```text
[Browser]
    |
    | HTTPS
    v
[Storage Account Static Website]
    |
    | HTTPS API calls
    v
[Azure App Service API]
    |
    | Key Vault reference resolved by Managed Identity
    v
[Azure Key Vault]
    |
    | Cosmos DB connection string
    v
[Cosmos DB private endpoint]
    |
    | Private DNS: privatelink.documents.azure.com
    v
[Cosmos DB for NoSQL]
```

## Folder structure

```text
session3-capstone-task-manager/
├── .gitignore
├── README.md
├── frontend/
│   ├── app.js
│   ├── config.js
│   ├── index.html
│   └── styles.css
├── infra/
│   └── terraform/
│       ├── main.tf
│       ├── outputs.tf
│       ├── terraform.tfvars.example
│       ├── variables.tf
│       └── versions.tf
└── src/
    └── TaskManager.Api/
        ├── Program.cs
        ├── TaskManager.Api.csproj
        ├── appsettings.Development.json
        ├── appsettings.json
        └── Properties/
            └── launchSettings.json
```

## Prerequisites

- Azure subscription access
- Azure CLI installed and authenticated with `az login`
- Terraform CLI installed
- .NET 8 SDK installed
- PowerShell 7 or Windows PowerShell
- Permission to create role assignments in the target resource group

## Step 0 — Create the resource group

The Terraform template uses a pre-created resource group so participants can clearly see the capstone resources land in one known container.

```powershell
$location = "eastus"
$resourceGroupName = "rg-session3-capstone"

az group create --name $resourceGroupName --location $location
```

## Step 1 — Deploy infrastructure with Terraform

From `infra/terraform`:

```powershell
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
terraform init
terraform apply -auto-approve
```

Terraform creates:

- VNet with `snet-app` and `snet-data`
- NSGs for the app and data subnets
- Cosmos DB serverless account, database, and container
- Cosmos DB private endpoint
- Private DNS zone and VNet link for Cosmos DB
- Key Vault with RBAC enabled
- Key Vault secret containing the Cosmos DB connection string
- App Service Plan and App Service API with system-assigned Managed Identity
- Key Vault Secrets User role assignment for the App Service identity
- App Service VNet integration
- Application Insights and Log Analytics workspace
- Storage Account static website for the frontend

Review outputs:

```powershell
terraform output
```

Useful outputs:

```powershell
terraform output -raw app_service_name
terraform output -raw app_service_url
terraform output -raw swagger_url
terraform output -raw frontend_storage_account_name
terraform output -raw frontend_url
```

## Step 2 — Deploy the API

From `src/TaskManager.Api`:

```powershell
$resourceGroupName = terraform -chdir=..\..\infra\terraform output -raw resource_group_name
$appName = terraform -chdir=..\..\infra\terraform output -raw app_service_name

dotnet publish -c Release -o .\publish
Compress-Archive -Path .\publish\* -DestinationPath .\taskmanager-api.zip -Force
az webapp deploy --resource-group $resourceGroupName --name $appName --src-path .\taskmanager-api.zip --type zip
az webapp restart --resource-group $resourceGroupName --name $appName
```

Open Swagger:

```powershell
terraform -chdir=..\..\infra\terraform output -raw swagger_url
```

Use Swagger to test:

- `POST /tasks`
- `GET /tasks`
- Optional stretch: `DELETE /tasks/{id}?status=todo`

Sample `POST /tasks` body:

```json
{
  "title": "Validate Key Vault reference",
  "description": "Confirm the API reads the Cosmos DB connection string through App Service and Managed Identity.",
  "status": "todo"
}
```

## Step 3 — Deploy the frontend

From `frontend`:

```powershell
$apiUrl = terraform -chdir=..\infra\terraform output -raw app_service_url
$storageAccountName = terraform -chdir=..\infra\terraform output -raw frontend_storage_account_name

@"
window.APP_CONFIG = {
  apiBaseUrl: "$apiUrl"
};
"@ | Set-Content -Path .\config.js

az storage blob upload-batch --account-name $storageAccountName --source . --destination '$web' --auth-mode login --overwrite
```

Open the frontend:

```powershell
terraform -chdir=..\infra\terraform output -raw frontend_url
```

Add a task in the UI, refresh the list, then confirm the item exists in Cosmos DB Data Explorer.

## Step 4 — Validate security controls

In the Azure portal:

1. Open the App Service and confirm **Identity** is enabled.
2. Open App Service **Environment variables** and confirm `CosmosDb__ConnectionString` is a Key Vault reference, not a plaintext connection string.
3. Open Key Vault **Access control (IAM)** and confirm the App Service managed identity has **Key Vault Secrets User**.
4. Open Cosmos DB **Networking** and confirm public network access is disabled.
5. Open the Cosmos DB private endpoint and confirm it is connected to `snet-data`.
6. Open the private DNS zone and confirm it is linked to the capstone VNet.
7. Open Application Insights and review live metrics or transaction search after API requests.

## Step 5 — Cleanup

From the project root:

```powershell
terraform -chdir=.\infra\terraform destroy
```

If you want to delete the pre-created resource group after Terraform cleanup:

```powershell
az group delete --name rg-session3-capstone --yes --no-wait
```

## Facilitator notes

- Pre-run Terraform in the training subscription before the workshop.
- Role assignment propagation for Key Vault can take a few minutes. If the Key Vault reference initially shows unresolved, restart the App Service after waiting briefly.
- Cosmos DB public access is disabled, so local API debugging against the deployed Cosmos DB will not work unless the developer is on an approved private network path.
- Keep the deployed reference environment available during the lab so participants can compare resource settings if their deployment hits quota or permission issues.
