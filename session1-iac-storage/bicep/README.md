# Bicep Demo with Modules

This folder contains the same Storage Account pattern as the ARM demo, implemented in Bicep.

## Highlights

- `main.bicep` is the orchestration file.
- `modules/storage-account.bicep` encapsulates the Storage Account and blob container.
- Parameters and decorators make the contract clearer than ARM JSON.
- Module outputs are surfaced back through `main.bicep`.
- Bicep compiles to ARM, so it uses the same Azure Resource Manager deployment engine.

## Optional: build to ARM JSON

```powershell
az bicep build --file main.bicep
```

This produces `main.json`, which is useful for showing that Bicep is an authoring experience over ARM.

## Deploy

From this folder:

```powershell
az deployment group what-if `
  --resource-group $resourceGroupName `
  --template-file main.bicep `
  --parameters main.bicepparam

az deployment group create `
  --resource-group $resourceGroupName `
  --template-file main.bicep `
  --parameters main.bicepparam
```

## Validate

```powershell
az storage account list `
  --resource-group $resourceGroupName `
  --query "[].{name:name, location:location, sku:sku.name}" `
  --output table
```
