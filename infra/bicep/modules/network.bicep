// VNet + delegated subnets for the private topology in V2-ARCHITECTURE.md §2.
// Status: code complete; cloud apply pending.

param namePrefix string
param location string
param vnetAddressPrefix string = '10.90.0.0/16'

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: 'container-apps'
        properties: {
          addressPrefix: '10.90.0.0/23'
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: 'postgres'
        properties: {
          addressPrefix: '10.90.2.0/24'
          delegations: [
            {
              name: 'Microsoft.DBforPostgreSQL.flexibleServers'
              properties: {
                serviceName: 'Microsoft.DBforPostgreSQL/flexibleServers'
              }
            }
          ]
        }
      }
      {
        name: 'apim-outbound'
        properties: {
          addressPrefix: '10.90.3.0/24'
          delegations: [
            {
              name: 'Microsoft.Web.serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
        }
      }
      {
        name: 'private-endpoints'
        properties: {
          addressPrefix: '10.90.4.0/24'
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
      {
        // A public Container Apps environment needs its own subnet — a
        // subnet delegated to Microsoft.App/environments can only back one
        // environment, and the website (real browsers hitting writerflow.aviusolutions.com
        // directly) cannot share the API's internal-only environment without
        // exposing the API's app-level external=true ingress to the open
        // internet too, which would break the "APIM is the only public
        // entry point to the API" posture. See container-app-website.bicep.
        name: 'website-container-apps'
        properties: {
          addressPrefix: '10.90.6.0/23'
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
    ]
  }
}

resource postgresPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${namePrefix}.postgres.private'
  location: 'global'
}

resource postgresPrivateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: postgresPrivateDnsZone
  name: '${namePrefix}-postgres-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

resource containerAppsPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: '${namePrefix}.internal.containerapps.private'
  location: 'global'
}

resource containerAppsPrivateDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: containerAppsPrivateDnsZone
  name: '${namePrefix}-cae-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

output vnetId string = vnet.id
output containerAppsSubnetId string = vnet.properties.subnets[0].id
output postgresSubnetId string = vnet.properties.subnets[1].id
output apimSubnetId string = vnet.properties.subnets[2].id
output privateEndpointsSubnetId string = vnet.properties.subnets[3].id
output websiteContainerAppsSubnetId string = vnet.properties.subnets[4].id
output postgresPrivateDnsZoneId string = postgresPrivateDnsZone.id
output containerAppsPrivateDnsZoneId string = containerAppsPrivateDnsZone.id
