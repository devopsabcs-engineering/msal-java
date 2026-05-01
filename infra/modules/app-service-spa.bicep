// ---------------------------------------------------------------------------
// app-service-spa.bicep — Node 20 App Service for Angular SPA
// ---------------------------------------------------------------------------

@description('Name of the SPA App Service.')
param name string

@description('Azure region.')
param location string

@description('Resource ID of the App Service Plan.')
param appServicePlanId string

@description('SPA app registration client ID from Entra ID.')
param spaClientId string

@description('Microsoft Entra ID tenant ID.')
param tenantId string

@description('Base URL of the API App Service.')
param apiBaseUrl string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Resource ID of the subnet for App Service Regional VNet integration. Empty string disables integration.')
param virtualNetworkSubnetId string = ''

@description('Resource tags.')
param tags object = {}

var enableVnetIntegration = !empty(virtualNetworkSubnetId)

resource spaApp 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    virtualNetworkSubnetId: enableVnetIntegration ? virtualNetworkSubnetId : null
    publicNetworkAccess: 'Enabled'
    siteConfig: {
      linuxFxVersion: 'NODE|20-lts'
      appCommandLine: 'pm2 serve /home/site/wwwroot --spa --no-daemon'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      vnetRouteAllEnabled: enableVnetIntegration
      appSettings: [
        {
          name: 'MSAL_CLIENT_ID'
          value: spaClientId
        }
        {
          name: 'MSAL_TENANT_ID'
          value: tenantId
        }
        {
          name: 'API_BASE_URL'
          value: apiBaseUrl
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
      ]
    }
  }
}

@description('Default hostname of the SPA App Service.')
output hostname string = spaApp.properties.defaultHostName

@description('Principal ID of the system-assigned Managed Identity.')
output principalId string = spaApp.identity.principalId
