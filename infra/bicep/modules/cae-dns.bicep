// Private DNS for a Container Apps environment's default domain so VNet-linked
// workloads (APIM outbound, website CAE with VNet integration) resolve
// *.${defaultDomain} to the environment static IP instead of the public edge.
//
// The default domain is only known after the environment is created — pass
// containerAppsEnv.outputs.defaultDomain/staticIp here from main.bicep.

param defaultDomain string
param staticIp string
param vnetId string
param linkName string
@description('Skip when the CAE default domain zone is already linked to this VNet (common after platform auto-link).')
param createVnetLink bool = true

resource zone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: defaultDomain
  location: 'global'
}

resource vnetLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = if (createVnetLink) {
  parent: zone
  name: linkName
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnetId
    }
    registrationEnabled: false
  }
}

resource wildcardA 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: zone
  name: '*'
  properties: {
    ttl: 300
    aRecords: [
      {
        ipv4Address: staticIp
      }
    ]
  }
}

output privateDnsZoneId string = zone.id
