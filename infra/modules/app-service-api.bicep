// ---------------------------------------------------------------------------
// app-service-api.bicep — Java 17 App Service for Spring Boot API
// ---------------------------------------------------------------------------

@description('Name of the API App Service.')
param name string

@description('Azure region.')
param location string

@description('Resource ID of the App Service Plan.')
param appServicePlanId string

@description('API app registration client ID from Entra ID.')
param apiClientId string

@description('Microsoft Entra ID tenant ID.')
param tenantId string

@description('Storage account name for evidence blobs.')
param storageAccountName string

@description('Application Insights connection string.')
param appInsightsConnectionString string

@description('Allowed origin for CORS (typically the SPA App Service URL).')
param allowedOrigin string

@description('Resource ID of the subnet for App Service Regional VNet integration. Empty string disables integration.')
param virtualNetworkSubnetId string = ''

@description('Resource tags.')
param tags object = {}

var enableVnetIntegration = !empty(virtualNetworkSubnetId)

resource apiApp 'Microsoft.Web/sites@2023-12-01' = {
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
      linuxFxVersion: 'JAVA|17-java17'
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      vnetRouteAllEnabled: enableVnetIntegration
      appSettings: [
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        {
          name: 'SPRING_PROFILES_ACTIVE'
          value: 'prod'
        }
        {
          name: 'SPRING_CLOUD_AZURE_ACTIVE_DIRECTORY_CREDENTIAL_CLIENT_ID'
          value: apiClientId
        }
        {
          name: 'SPRING_CLOUD_AZURE_ACTIVE_DIRECTORY_PROFILE_TENANT_ID'
          value: tenantId
        }
        {
          name: 'SPRING_CLOUD_AZURE_ACTIVE_DIRECTORY_APP_ID_URI'
          value: 'api://${apiClientId}'
        }
        {
          name: 'JWT_ISSUER_URI'
          value: '${environment().authentication.loginEndpoint}${tenantId}/v2.0'
        }
        {
          name: 'JWT_AUDIENCE'
          value: 'api://${apiClientId},${apiClientId}'
        }
        {
          name: 'AZURE_TENANT_ID'
          value: tenantId
        }
        {
          name: 'AZURE_STORAGE_ACCOUNT_NAME'
          value: storageAccountName
        }
        {
          name: 'AZURE_STORAGE_CONTAINER_NAME'
          value: 'evidence'
        }
        {
          name: 'CORS_ALLOWED_ORIGINS'
          value: allowedOrigin
        }
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        {
          // Force all outbound traffic through the VNet (so the storage
          // call resolves via the privatelink.dfs.core.windows.net DNS zone).
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: enableVnetIntegration ? '1' : '0'
        }
        {
          // Honour Azure Private DNS for the integrated VNet.
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        }
      ]
    }
  }
}

@description('Default hostname of the API App Service.')
output hostname string = apiApp.properties.defaultHostName

@description('Principal ID of the system-assigned Managed Identity.')
output principalId string = apiApp.identity.principalId
