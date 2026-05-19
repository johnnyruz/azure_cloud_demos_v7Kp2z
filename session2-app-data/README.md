# Session 2 Guided Mini-Project — C# REST API with Cosmos DB

This guided mini-project supports Session 2 Block 5: **App + Data**.

Participants deploy a simple C# ASP.NET Core REST API to Azure App Service, connect it to Azure Cosmos DB for NoSQL, and use Swagger/OpenAPI as the built-in API testing interface.

## What this project builds

- **ASP.NET Core Web API** using minimal APIs
- **Swagger/OpenAPI UI** for interactive testing
- **Azure Cosmos DB for NoSQL** using serverless capacity
- **Azure App Service** for API hosting
- **Application Insights** for request telemetry

## API endpoints

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/items` | Returns all items from Cosmos DB |
| `POST` | `/items` | Adds a new item to Cosmos DB |
| `DELETE` | `/items/{id}` | Stretch goal: deletes one item |

## Folder structure

```text
session2-app-data/
├── .gitignore
├── README.md
├── infra/
│   └── terraform/
│       ├── main.tf
│       ├── outputs.tf
│       ├── terraform.tfvars.example
│       ├── variables.tf
│       └── versions.tf
└── src/
    └── Session2.AppData.Api/
        ├── Program.cs
        ├── Session2.AppData.Api.csproj
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
- VS Code or Visual Studio

## Step 1 — Provision the data and app resources

From the `infra/terraform` folder:

```powershell
Copy-Item .\terraform.tfvars.example .\terraform.tfvars
terraform init
terraform plan
terraform apply
```

The Terraform configuration creates:

- Cosmos DB account using Serverless capacity mode
- Cosmos DB SQL database named `trainingdb`
- Cosmos DB container named `items` with partition key `/category`
- Linux App Service Plan
- Azure App Service for the API
- Application Insights workspace-based monitoring

After deployment, collect the outputs:

```powershell
terraform output
```

## Step 2 — Run the API locally

From the API project folder:

```powershell
dotnet restore
$env:CosmosDb__ConnectionString = terraform -chdir=..\..\infra\terraform output -raw cosmosdb_connection_string
dotnet run
```

The committed `appsettings.json` intentionally leaves `CosmosDb:ConnectionString` blank. For Azure, Terraform configures the value as an App Service setting. For local runs, the temporary environment variable above supplies the value only for the current PowerShell session.

Optional safety check before committing:

```powershell
git config core.hooksPath .githooks
powershell -NoProfile -ExecutionPolicy Bypass -File .githooks/pre-commit.ps1
```

This enables a pre-commit hook that blocks commits containing Azure Cosmos DB connection strings or account keys.

Open the Swagger UI shown in the console, usually:

```text
https://localhost:7145/swagger
```

## Step 3 — Test with Swagger

In Swagger UI:

1. Expand `POST /items`.
2. Select **Try it out**.
3. Use a sample request body:

```json
{
  "name": "First cloud item",
  "category": "training",
  "description": "Created from Swagger during Session 2"
}
```

4. Execute the request and confirm a `201` response.
5. Expand `GET /items`.
6. Select **Try it out** and execute the request.
7. Confirm the item appears in the response.
8. Open Cosmos DB Data Explorer and verify the item exists in the `trainingdb/items` container.

## Step 4 — Deploy the API to App Service

From the API project folder:

```powershell
$appName = terraform -chdir=..\..\infra\terraform output -raw app_service_name
$resourceGroupName = terraform -chdir=..\..\infra\terraform output -raw resource_group_name
```

Then deploy with:

```powershell
dotnet publish -c Release -o ./publish
Compress-Archive -Path ./publish/* -DestinationPath ./api.zip -Force
az webapp deploy --resource-group $resourceGroupName --name $appName --src-path ./api.zip --type zip
```

## Step 5 — Verify app settings

Terraform configures the Cosmos DB connection string as an App Setting. Do not hardcode it in source code.

Verify the settings:

```powershell
az webapp config appsettings list `
  --resource-group $resourceGroupName `
  --name $appName `
  --query "[?starts_with(name, 'CosmosDb') || name == 'EnableSwagger'].{name:name, value:value}"
```

Restart the app:

```powershell
az webapp restart --resource-group $resourceGroupName --name $appName
```

Then open:

```powershell
terraform -chdir=..\..\infra\terraform output -raw swagger_url
```

## Step 6 — View Application Insights

In the Azure portal:

1. Open the Application Insights resource created by Terraform.
2. Open **Live Metrics**.
3. Trigger `POST /items` and `GET /items` from Swagger.
4. Review request count, duration, and failures.
5. Open **Transaction search** to inspect individual requests.

## Cleanup

```powershell
terraform -chdir=.\infra\terraform destroy
```
