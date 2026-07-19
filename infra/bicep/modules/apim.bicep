// APIM Standard v2, outbound VNet integration into its delegated subnet
// (V2-ARCHITECTURE.md §2, Stage 5.1 "Put APIM Standard v2 outbound VNet
// integration in its delegated subnet and link private DNS so the Container
// Apps environment wildcard domain resolves to its internal static IP").
// Consumption tier is deliberately excluded — no long-running SSE support.
// Status: code complete; cloud apply pending.

// containerAppsEnvironmentDefaultDomain/StaticIp resolution to the internal
// static IP is provided by network.bicep's private DNS zone + VNet link, not
// by this module — APIM's outbound VNet integration into outboundSubnetId is
// what lets it consume that zone.
param namePrefix string
param location string
param outboundSubnetId string
param apiAppFqdn string
param publisherEmail string = 'engineering@writerflow.app'
param publisherName string = 'WriterFlow'

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: '${namePrefix}-apim'
  location: location
  sku: {
    name: 'StandardV2'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: outboundSubnetId
    }
  }
}

resource api 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: 'writerflow-v2'
  properties: {
    displayName: 'WriterFlow v2 API'
    path: 'v2'
    protocols: ['https']
    serviceUrl: 'https://${apiAppFqdn}'
    subscriptionRequired: false
  }
}

resource apiPolicy 'Microsoft.ApiManagement/service/apis/policies@2024-06-01-preview' = {
  parent: api
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/api-policy.xml')
  }
}

output gatewayUrl string = apim.properties.gatewayUrl
