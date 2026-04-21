// ---------------------------------------------------------------------------
// monitoring.bicep — Log Analytics workspace + Application Insights
// ---------------------------------------------------------------------------

@description('Name of the Log Analytics workspace.')
param logAnalyticsName string

@description('Name of the Application Insights resource.')
param appInsightsName string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
  }
}

@description('Application Insights connection string for App Service configuration.')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Application Insights instrumentation key.')
output instrumentationKey string = appInsights.properties.InstrumentationKey
