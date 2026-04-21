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

@description('App Service Plan SKU. B1 is sufficient for workshop use.')
@allowed(['B1', 'B2', 'B3', 'S1', 'P1v3'])
param appServicePlanSku string = 'B1'

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

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var resourceSuffix = environmentName
var appServicePlanName = 'asp-evidence-${resourceSuffix}'
var spaAppName = 'app-evidence-spa-${resourceSuffix}'
var apiAppName = 'app-evidence-api-${resourceSuffix}'
var logAnalyticsName = 'log-evidence-${resourceSuffix}'
var appInsightsName = 'appi-evidence-${resourceSuffix}'
var tags = {
  project: 'msal-java-workshop'
  environment: environmentName
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

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
    tags: tags
  }
}

module roleAssignments 'modules/role-assignments.bicep' = {
  name: 'roleAssignments'
  params: {
    storageAccountName: storageAccountName
    apiPrincipalId: apiApp.outputs.principalId
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

@description('Storage account name for evidence blob container.')
output storageAccountNameOutput string = storageAccountName
