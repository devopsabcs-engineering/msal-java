// ---------------------------------------------------------------------------
// app-service-plan.bicep — Linux App Service Plan
// ---------------------------------------------------------------------------

@description('Name of the App Service Plan.')
param name string

@description('Azure region for the App Service Plan.')
param location string

@description('SKU name for the App Service Plan.')
@allowed(['B1', 'B2', 'B3', 'S1', 'P1v3'])
param skuName string = 'B1'

@description('Resource tags.')
param tags object = {}

resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: name
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: skuName
  }
  properties: {
    reserved: true // Required for Linux
  }
}

@description('Resource ID of the App Service Plan.')
output id string = appServicePlan.id
