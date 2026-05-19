# ARM Template Demo

This folder contains a raw ARM JSON template for a Storage Account and blob container.

## Highlights

- `$schema` and `contentVersion` identify this as an ARM deployment template.
- `parameters` make the template reusable.
- `variables` create a deterministic storage account name suffix.
- `resources` declare the Storage Account and child blob container.
- `dependsOn` makes the container wait for the Storage Account.
- `outputs` return useful values after deployment.

## Deploy

From this folder:

```powershell
az deployment group what-if `
  --resource-group $resourceGroupName `
  --template-file azuredeploy.json `
  --parameters azuredeploy.parameters.json

az deployment group create `
  --resource-group $resourceGroupName `
  --template-file azuredeploy.json `
  --parameters azuredeploy.parameters.json
```

## Validate

```powershell
az storage account list `
  --resource-group $resourceGroupName `
  --query "[].{name:name, location:location, sku:sku.name}" `
  --output table
```
