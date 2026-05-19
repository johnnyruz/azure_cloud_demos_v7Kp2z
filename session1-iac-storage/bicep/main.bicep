targetScope = 'resourceGroup'

@description('Azure region for all resources in this deployment.')
param location string = resourceGroup().location

@description('Lowercase prefix used to build a globally unique storage account name. Keep this short so the generated name stays under 24 characters.')
@minLength(3)
@maxLength(11)
param storageAccountPrefix string = 'stsession1'

@description('Name of the private blob container to create.')
param containerName string = 'training'

@description('Storage account replication option.')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
  'Standard_ZRS'
])
param skuName string = 'Standard_LRS'

var storageAccountName = toLower('${storageAccountPrefix}${uniqueString(resourceGroup().id)}')

module storage './modules/storage-account.bicep' = {
  name: 'storageAccountDeployment'
  params: {
    location: location
    storageAccountName: storageAccountName
    skuName: skuName
    containerName: containerName
  }
}

// Create a container for Terraform state files
// Ideally should be part of the storage module but here for illustrative purposes
resource tfStateContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  name: '${storageAccountName}/default/tf-state-store'
  properties: {
    publicAccess: 'None'
  }
  dependsOn: [
    storage
  ]
}


output storageAccountName string = storage.outputs.storageAccountName
output storageAccountId string = storage.outputs.storageAccountId
output blobEndpoint string = storage.outputs.blobEndpoint
