// ---------------------------------------------------------------------------
// vnet.bicep — Virtual Network with two subnets:
//   * snet-app — delegated to Microsoft.Web/serverFarms for App Service
//                Regional VNet integration (outbound traffic to private endpoints)
//   * snet-pe  — hosts private endpoints; private-endpoint network policies
//                disabled per platform requirements
// ---------------------------------------------------------------------------

@description('Name of the Virtual Network.')
param name string

@description('Azure region.')
param location string

@description('VNet address space (CIDR).')
param addressPrefix string = '10.20.0.0/16'

@description('Address prefix for the App Service integration subnet.')
param appSubnetPrefix string = '10.20.1.0/24'

@description('Address prefix for the private endpoints subnet.')
param peSubnetPrefix string = '10.20.2.0/24'

@description('Resource tags.')
param tags object = {}

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressPrefix
      ]
    }
    subnets: [
      {
        name: 'snet-app'
        properties: {
          addressPrefix: appSubnetPrefix
          delegations: [
            {
              name: 'webapp-delegation'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          // Allow App Service to reach the storage private endpoint
          serviceEndpoints: []
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: peSubnetPrefix
          // Required to host private endpoints
          privateEndpointNetworkPolicies: 'Disabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
    ]
  }
}

@description('Resource ID of the VNet.')
output id string = vnet.id

@description('Resource ID of the snet-app subnet (App Service VNet integration).')
output appSubnetId string = '${vnet.id}/subnets/snet-app'

@description('Resource ID of the snet-pe subnet (Private Endpoints).')
output peSubnetId string = '${vnet.id}/subnets/snet-pe'
