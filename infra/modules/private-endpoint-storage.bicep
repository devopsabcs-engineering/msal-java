// ---------------------------------------------------------------------------
// private-endpoint-storage.bicep — Private Endpoint for ADLS Gen2 (dfs)
//
// Creates:
//   * Private Endpoint in the snet-pe subnet targeting the Storage Account
//     using groupId 'dfs' (ADLS Gen2 DataLake endpoint).
//   * Private DNS Zone privatelink.dfs.core.windows.net.
//   * VNet link from the zone to the workshop VNet.
//   * privateDnsZoneGroup association so the PE NIC IP is registered in DNS
//     automatically.
//
// Note: ADLS Gen2 traffic from inside the VNet resolves <account>.dfs.core
// .windows.net to the PE private IP via the privatelink zone. Spring Boot's
// AzureBlobStorageService must use the DataLake SDK (azure-storage-file-data
// lake) so the client sends requests to the .dfs endpoint rather than .blob.
// ---------------------------------------------------------------------------

@description('Base name (no suffix) used for the Private Endpoint resource.')
param name string

@description('Azure region.')
param location string

@description('Resource ID of the Storage Account to expose privately.')
param storageAccountId string

@description('Resource ID of the subnet that will host the Private Endpoint NIC.')
param subnetId string

@description('Resource ID of the VNet to link the Private DNS Zone to.')
param vnetId string

@description('Resource tags.')
param tags object = {}

// privatelink.dfs.<storage-suffix> — environment() returns the storage suffix
// for the active cloud (core.windows.net for Azure Public, core.usgovcloudapi.
// net for Azure Government, etc.).
var privateDnsZoneName = 'privatelink.dfs.${environment().suffixes.storage}'

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-dfs'
        properties: {
          privateLinkServiceId: storageAccountId
          // ADLS Gen2 uses the 'dfs' sub-resource (NOT 'blob').
          groupIds: [
            'dfs'
          ]
        }
      }
    ]
  }
}

resource privateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: privateDnsZoneName
  location: 'global'
  tags: tags
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: privateDnsZone
  name: '${name}-vnet-link'
  location: 'global'
  tags: tags
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnetId
    }
  }
}

resource dnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-11-01' = {
  parent: privateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'dfs'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

@description('Resource ID of the Private Endpoint.')
output privateEndpointId string = privateEndpoint.id

@description('Name of the Private DNS Zone created for ADLS Gen2.')
output privateDnsZoneName string = privateDnsZone.name
