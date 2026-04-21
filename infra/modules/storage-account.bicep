// ---------------------------------------------------------------------------
// storage-account.bicep — Azure Storage Account with evidence blob container
// ---------------------------------------------------------------------------

@description('Globally unique storage account name (3-24 lowercase alphanumeric).')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Enabled'
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

resource evidenceContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: 'evidence'
  properties: {
    publicAccess: 'None'
  }
}

@description('Resource ID of the Storage Account.')
output id string = storageAccount.id

@description('Name of the Storage Account.')
output name string = storageAccount.name
