// ---------------------------------------------------------------------------
// storage-account.bicep — Hardened ADLS Gen2 (Hierarchical Namespace) account
//
// Posture:
//   * isHnsEnabled = true            → Azure Data Lake Storage Gen2.
//   * allowSharedKeyAccess = false   → only Entra ID (OAuth + RBAC) auth.
//   * publicNetworkAccess = Disabled → reachable only via Private Endpoint.
//   * networkAcls.defaultAction = Deny.
//   * allowBlobPublicAccess = false  → no anonymous access.
//
// Optional: a single deployer IP can be temporarily added to networkAcls.
// ipRules so seeding scripts can upload sample evidence over OAuth before
// the App Service starts using the private endpoint. Pass an empty string
// to omit.
// ---------------------------------------------------------------------------

@description('Globally unique storage account name (3-24 lowercase alphanumeric).')
@minLength(3)
@maxLength(24)
param name string

@description('Azure region.')
param location string

@description('Resource tags.')
param tags object = {}

@description('Optional public IP (or CIDR) of the deployer to temporarily allow over Entra ID auth (e.g. for sample-evidence seeding). Leave empty to keep the account fully private.')
param deployerIp string = ''

var hasDeployerIp = !empty(deployerIp)

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
    isHnsEnabled: true
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    defaultToOAuthAuthentication: true
    publicNetworkAccess: hasDeployerIp ? 'Enabled' : 'Disabled'
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
      ipRules: hasDeployerIp ? [
        {
          value: deployerIp
          action: 'Allow'
        }
      ] : []
      virtualNetworkRules: []
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

// On an HNS-enabled account, "containers" are filesystem roots in ADLS Gen2.
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
