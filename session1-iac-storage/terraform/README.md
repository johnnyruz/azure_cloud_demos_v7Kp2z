# Terraform Demo

This folder contains the same Storage Account pattern as the ARM and Bicep demos, implemented with Terraform and the AzureRM provider.

## Highlights

- `versions.tf` pins Terraform and provider requirements.
- `variables.tf` defines inputs and validation.
- `main.tf` declares resources and references.
- `outputs.tf` returns values after apply.
- `terraform.tfstate` tracks deployed infrastructure locally after apply.
- The `random_id` resource makes the Storage Account name globally unique and demonstrates Terraform state.

## Prepare variables

From this folder:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` if you want a different region, resource group, prefix, or environment tag.

## Deploy

```powershell
terraform init
terraform fmt
terraform validate
terraform plan
terraform apply
```

## Validate

```powershell
terraform output

az storage account list `
  --resource-group $(terraform output -raw resource_group_name) `
  --query "[].{name:name, location:location, sku:sku.name}" `
  --output table
```

## Cleanup

```powershell
terraform destroy
```

## Training note: import a pre-created resource group

In the training environment, each student may already have an assigned resource group. If Terraform tries to create that resource group, the deployment will fail because the name already exists.

To use an existing resource group, first make sure `resource_group_name` in `terraform.tfvars` matches the assigned resource group name.

Sign in to Azure and confirm the correct subscription:

```powershell
az login
az account show --output table
```

Set values for the current subscription and assigned resource group:

```powershell
$subscriptionId = az account show --query id --output tsv
$resourceGroupName = "rg-your-assigned-student-resource-group"
```

Import the existing resource group into Terraform state:

```powershell
terraform import `
  azurerm_resource_group.demo `
  "/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName"
```

After the import succeeds, run the normal deploy commands:

```powershell
terraform plan
terraform apply
```

