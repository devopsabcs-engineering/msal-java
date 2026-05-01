// ---------------------------------------------------------------------------
// role-assignments.bicep — Storage Blob Data Contributor for API Managed Identity
//
// "Storage Blob Data Contributor" lets the API both read evidence files
// (download endpoint) and seed/upload data when the workshop seed step runs
// from inside the App Service. Using Entra ID role-based access removes the
// need for shared keys (which are disabled on the storage account).
// ---------------------------------------------------------------------------

@description('Name of the Storage Account to scope the role assignment.')
param storageAccountName string

@description('Principal ID of the API App Service system-assigned Managed Identity.')
param apiPrincipalId string

@description('Optional principal ID of the deployer (user or service principal) running the seed step. Empty string disables the assignment.')
param deployerPrincipalId string = ''

@description('Principal type of the deployer principal (User, ServicePrincipal, Group).')
@allowed([
  'User'
  'ServicePrincipal'
  'Group'
])
param deployerPrincipalType string = 'User'

// Storage Blob Data Contributor built-in role (read + write blob data).
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource apiAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, apiPrincipalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    principalId: apiPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalType: 'ServicePrincipal'
  }
}

resource deployerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(deployerPrincipalId)) {
  name: guid(storageAccount.id, deployerPrincipalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    principalId: deployerPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalType: deployerPrincipalType
  }
}
