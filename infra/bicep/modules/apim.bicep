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

// ADR-0012: JWKS is a fixed RFC 8615 well-known path at the issuer's true
// root (api.writerflow.app/.well-known/jwks.json), not under /v2 — a
// separate root-path API forwarding to the same backend, bypassing the
// 'writerflow-v2' API's validate-jwt policy entirely (this endpoint is what
// makes validate-jwt possible in the first place).
resource wellKnownApi 'Microsoft.ApiManagement/service/apis@2024-06-01-preview' = {
  parent: apim
  name: 'writerflow-well-known'
  properties: {
    displayName: 'WriterFlow well-known endpoints'
    path: '.well-known'
    protocols: ['https']
    serviceUrl: 'https://${apiAppFqdn}/.well-known'
    subscriptionRequired: false
  }
}

resource jwksOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: wellKnownApi
  name: 'jwks'
  properties: {
    displayName: 'Get JWKS'
    method: 'GET'
    urlTemplate: '/jwks.json'
  }
}

resource jwksOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: jwksOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><rate-limit-by-key calls="600" renewal-period="60" counter-key="@(context.Request.IpAddress)" /></inbound><backend><base /></backend><outbound><base /><set-header name="Cache-Control" exists-action="override"><value>public, max-age=300</value></set-header></outbound><on-error><base /></on-error></policies>'
  }
}

output gatewayUrl string = apim.properties.gatewayUrl
