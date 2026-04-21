// ---------------------------------------------------------------------------
// role-assignments.bicep — Storage Blob Data Reader for API Managed Identity
// ---------------------------------------------------------------------------

@description('Name of the Storage Account to scope the role assignment.')
param storageAccountName string

@description('Principal ID of the API App Service system-assigned Managed Identity.')
param apiPrincipalId string

// Storage Blob Data Reader built-in role
var storageBlobDataReaderRoleId = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource storageBlobDataReaderAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, apiPrincipalId, storageBlobDataReaderRoleId)
  scope: storageAccount
  properties: {
    principalId: apiPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataReaderRoleId)
    principalType: 'ServicePrincipal'
  }
}
