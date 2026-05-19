# Session 1 Demo — Storage Account with Three IaC Flavors

This demo supports Session 1 blocks 2-4 by deploying the same basic Azure Storage pattern three ways:

- **ARM template** — Azure Resource Manager JSON
- **Bicep** — Azure-native DSL compiled to ARM, including local modules
- **Terraform** — Cloud-agnostic HCL using the AzureRM provider

Each flavor creates a comparable setup:

- A general-purpose v2 Azure Storage Account
- Standard locally redundant storage (`Standard_LRS`)
- Hot access tier
- HTTPS-only traffic
- TLS 1.2 minimum
- One private blob container named `training`

## Prerequisites

- Azure subscription access
- Azure CLI installed and authenticated with `az login`
- Terraform CLI installed for the Terraform demo
- Optional but recommended: VS Code Bicep and Terraform extensions

## Suggested demo setup

Set a few shell variables before demonstrating ARM or Bicep:

```powershell
$location = "eastus"
$resourceGroupName = "rg-session1-iac-demo"
az group create --name $resourceGroupName --location $location
```

Azure Storage Account names must be globally unique, lowercase, 3-24 characters, and contain only numbers and letters. The ARM and Bicep demos generate a unique suffix from the resource group. The Terraform demo asks learners to provide a unique name in `terraform.tfvars`.

## Demo order

1. Start with `arm/` to show raw ARM JSON structure.
2. Move to `bicep/` to show the same idea with cleaner syntax and modules.
3. Finish with `terraform/` to show provider-based, stateful IaC.

## Cleanup

For ARM and Bicep deployments, delete the demo resource group:

```powershell
az group delete --name $resourceGroupName --yes --no-wait
```

For Terraform, run cleanup from the `terraform/` folder:

```powershell
terraform destroy
```
