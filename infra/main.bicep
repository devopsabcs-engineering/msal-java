// ---------------------------------------------------------------------------
// main.bicep — MSAL Java Workshop Infrastructure Orchestration
// Deploys: App Service Plan, SPA + API App Services, Storage, Monitoring, RBAC
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Deployment environment name used as a suffix for resource names.')
param environmentName string = 'workshop'

@description('Azure region for all resources. Canada Central recommended for data residency.')
param location string = 'canadacentral'

@description('App Service Plan SKU. S1 or higher is required for VNet integration.')
@allowed(['S1', 'P1v3', 'P2v3', 'P3v3'])
param appServicePlanSku string = 'S1'

@description('Globally unique storage account name (3-24 lowercase alphanumeric).')
@minLength(3)
@maxLength(24)
param storageAccountName string

@description('SPA app registration client ID from Microsoft Entra ID.')
param spaClientId string

@description('API app registration client ID from Microsoft Entra ID.')
param apiClientId string

@description('Microsoft Entra ID tenant ID.')
param tenantId string

@description('Optional public IP (or CIDR) of the deployer to temporarily allow on storage networkAcls so the seed step can upload sample evidence over OAuth. Leave empty to keep the storage account fully private (no seeding).')
param deployerIp string = ''

@description('Optional principal ID (objectId) of the deployer (User or Service Principal). When set, the deployer is granted Storage Blob Data Contributor on the storage account so the seed step can upload sample evidence using OAuth (no shared keys).')
param deployerPrincipalId string = ''

@description('Principal type of the deployer principal.')
@allowed(['User', 'ServicePrincipal', 'Group'])
param deployerPrincipalType string = 'User'

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var resourceSuffix = environmentName
var appServicePlanName = 'asp-evidence-${resourceSuffix}'
var spaAppName = 'app-evidence-spa-${resourceSuffix}'
var apiAppName = 'app-evidence-api-${resourceSuffix}'
var logAnalyticsName = 'log-evidence-${resourceSuffix}'
var appInsightsName = 'appi-evidence-${resourceSuffix}'
var vnetName = 'vnet-evidence-${resourceSuffix}'
var storagePrivateEndpointName = 'pe-${storageAccountName}-dfs'
var tags = {
  project: 'msal-java-workshop'
  environment: environmentName
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

module vnet 'modules/vnet.bicep' = {
  name: 'vnet'
  params: {
    name: vnetName
    location: location
    tags: tags
  }
}

module appServicePlan 'modules/app-service-plan.bicep' = {
  name: 'appServicePlan'
  params: {
    name: appServicePlanName
    location: location
    skuName: appServicePlanSku
    tags: tags
  }
}

module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring'
  params: {
    logAnalyticsName: logAnalyticsName
    appInsightsName: appInsightsName
    location: location
    tags: tags
  }
}

module storageAccount 'modules/storage-account.bicep' = {
  name: 'storageAccount'
  params: {
    name: storageAccountName
    location: location
    tags: tags
    deployerIp: deployerIp
    appSubnetId: vnet.outputs.appSubnetId
  }
}

module storagePrivateEndpoint 'modules/private-endpoint-storage.bicep' = {
  name: 'storagePrivateEndpoint'
  params: {
    name: storagePrivateEndpointName
    location: location
    storageAccountId: storageAccount.outputs.id
    subnetId: vnet.outputs.peSubnetId
    vnetId: vnet.outputs.id
    tags: tags
  }
}

module spaApp 'modules/app-service-spa.bicep' = {
  name: 'spaApp'
  params: {
    name: spaAppName
    location: location
    appServicePlanId: appServicePlan.outputs.id
    spaClientId: spaClientId
    tenantId: tenantId
    apiBaseUrl: 'https://${apiAppName}.azurewebsites.net'
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    virtualNetworkSubnetId: vnet.outputs.appSubnetId
    tags: tags
  }
}

module apiApp 'modules/app-service-api.bicep' = {
  name: 'apiApp'
  params: {
    name: apiAppName
    location: location
    appServicePlanId: appServicePlan.outputs.id
    apiClientId: apiClientId
    tenantId: tenantId
    storageAccountName: storageAccountName
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    allowedOrigin: 'https://${spaAppName}.azurewebsites.net'
    virtualNetworkSubnetId: vnet.outputs.appSubnetId
    tags: tags
  }
  dependsOn: [
    storagePrivateEndpoint
  ]
}

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'roleAssignments'
  params: {
    storageAccountName: storageAccountName
    apiPrincipalId: apiApp.outputs.principalId
    deployerPrincipalId: deployerPrincipalId
    deployerPrincipalType: deployerPrincipalType
  }
  dependsOn: [
    storageAccount
  ]
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('URL of the deployed SPA application.')
output spaUrl string = 'https://${spaAppName}.azurewebsites.net'

@description('URL of the deployed API application.')
output apiUrl string = 'https://${apiAppName}.azurewebsites.net'

@description('SPA App Service name.')
output spaAppName string = spaAppName

@description('API App Service name.')
output apiAppName string = apiAppName

@description('Storage account name for evidence blob container.')
output storageAccountNameOutput string = storageAccountName

@description('Application Insights connection string.')
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
