// Developer APIM is the cost-controlled private-beta gateway. Standard v2
// remains available for a future private-origin production profile.
// (V2-ARCHITECTURE.md §2, Stage 5.1 "Put APIM Standard v2 outbound VNet
// integration in its delegated subnet and link private DNS so the Container
// Apps environment wildcard domain resolves to its internal static IP").
// Consumption tier is deliberately excluded — no long-running SSE support.
// Status: code complete; cloud apply pending.

// containerAppsEnvironmentDefaultDomain/StaticIp resolution to the internal
// static IP is provided by cae-dns.bicep's private DNS zone + VNet link, not
// by this module — APIM's outbound VNet integration into outboundSubnetId is
// what lets it consume that zone.
param namePrefix string
param location string
param outboundSubnetId string
param apiAppFqdn string
param publisherEmail string = 'engineering@writerflow.aviusolutions.com'
param publisherName string = 'WriterFlow'
param writerflowIssuer string = 'https://apiwriterflow.aviusolutions.com'
param writerflowJwksUri string = 'https://apiwriterflow.aviusolutions.com/.well-known/jwks.json'
@description('Versionless Key Vault secret URI used to authenticate APIM to a public Container Apps origin.')
param originSharedSecretUri string = ''
@description('Use cost-controlled Developer APIM without VNet integration. The API backend must then be publicly reachable.')
param developerFallback bool = false
@description('Enable only after the StandardV2 service exists and DNS validation points at its gateway.')
param configureCustomDomain bool = false
param customGatewayHostname string = 'apiwriterflow.aviusolutions.com'

resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: developerFallback ? '${namePrefix}-apim-dev' : '${namePrefix}-apim'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: developerFallback ? 'Developer' : 'StandardV2'
    capacity: 1
  }
  properties: union({
    publisherEmail: publisherEmail
    publisherName: publisherName
  }, developerFallback ? {} : union({
    virtualNetworkType: 'External'
    virtualNetworkConfiguration: {
      subnetResourceId: outboundSubnetId
    }
  }, configureCustomDomain ? {
    hostnameConfigurations: [
      {
        type: 'Proxy'
        hostName: customGatewayHostname
        certificateSource: 'Managed'
        defaultSslBinding: true
        negotiateClientCertificate: false
      }
    ]
  } : {}))
}

resource originSecretNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apim
  name: 'writerflow-origin-secret'
  properties: empty(originSharedSecretUri) ? {
    displayName: 'writerflow-origin-secret'
    value: 'origin-secret-not-configured'
    secret: true
  } : {
    displayName: 'writerflow-origin-secret'
    secret: true
    keyVault: {
      secretIdentifier: originSharedSecretUri
    }
  }
}

resource jwksUriNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apim
  name: 'writerflow-jwks-uri'
  properties: {
    displayName: 'writerflow-jwks-uri'
    value: writerflowJwksUri
  }
}

resource issuerNamedValue 'Microsoft.ApiManagement/service/namedValues@2024-06-01-preview' = {
  parent: apim
  name: 'writerflow-issuer'
  properties: {
    displayName: 'writerflow-issuer'
    value: writerflowIssuer
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
    value: developerFallback
      ? loadTextContent('../../apim/api-policy-dev.xml')
      : loadTextContent('../../apim/api-policy.xml')
  }
}

resource deviceAuthorizeOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: api
  name: 'device-authorize'
  properties: {
    displayName: 'Device authorize'
    method: 'POST'
    urlTemplate: '/device/authorize'
  }
}

resource deviceAuthorizePolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: deviceAuthorizeOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: developerFallback
      ? loadTextContent('../../apim/pairing-operations-policy-dev.xml')
      : loadTextContent('../../apim/pairing-operations-policy.xml')
  }
}

resource deviceTokenOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: api
  name: 'device-token'
  properties: {
    displayName: 'Device token poll'
    method: 'POST'
    urlTemplate: '/device/token'
  }
}

resource deviceTokenPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: deviceTokenOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: developerFallback
      ? loadTextContent('../../apim/pairing-operations-policy-dev.xml')
      : loadTextContent('../../apim/pairing-operations-policy.xml')
  }
}

resource tokenRefreshOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: api
  name: 'token-refresh'
  properties: {
    displayName: 'Refresh device token'
    method: 'POST'
    urlTemplate: '/token/refresh'
  }
}

resource tokenRefreshPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: tokenRefreshOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: developerFallback
      ? loadTextContent('../../apim/pairing-operations-policy-dev.xml')
      : loadTextContent('../../apim/pairing-operations-policy.xml')
  }
}

var webPairingOperations = [
  {
    name: 'device-approve'
    displayName: 'Approve device'
    method: 'POST'
    urlTemplate: '/device/approve'
  }
  {
    name: 'web-session-token'
    displayName: 'Mint web session token'
    method: 'POST'
    urlTemplate: '/web-session/token'
  }
  {
    // ADR-0013 account sign-in — Entra ID token in body, no device JWT.
    name: 'web-account-token'
    displayName: 'Mint web account token'
    method: 'POST'
    urlTemplate: '/web-account/token'
  }
  {
    // ADR-0013 — web-account bearer (not device JWT with device_id).
    name: 'web-session-bridge'
    displayName: 'Bridge web session for pairing'
    method: 'POST'
    urlTemplate: '/web-session/bridge'
  }
  {
    // ADR-0013 — web-account bearer for website Account page.
    name: 'web-me'
    displayName: 'Get web account snapshot'
    method: 'GET'
    urlTemplate: '/web/me'
  }
]

resource webPairingOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = [for operation in webPairingOperations: {
  parent: api
  name: operation.name
  properties: {
    displayName: operation.displayName
    method: operation.method
    urlTemplate: operation.urlTemplate
  }
}]

resource webPairingPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = [for (operation, index) in webPairingOperations: {
  parent: webPairingOperation[index]
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: developerFallback
      ? loadTextContent('../../apim/pairing-operations-policy-dev.xml')
      : loadTextContent('../../apim/pairing-operations-policy.xml')
  }
}]

var authenticatedOperations = [
  {
    name: 'account-me'
    displayName: 'Get current account'
    method: 'GET'
    urlTemplate: '/me'
  }
  {
    name: 'device-revoke'
    displayName: 'Revoke device'
    method: 'DELETE'
    urlTemplate: '/devices/{id}'
  }
  {
    name: 'cohort-flags'
    displayName: 'Get cohort flags'
    method: 'GET'
    urlTemplate: '/cohort/flags'
  }
]

resource authenticatedOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = [for operation in authenticatedOperations: {
  parent: api
  name: operation.name
  properties: {
    displayName: operation.displayName
    method: operation.method
    urlTemplate: operation.urlTemplate
    templateParameters: operation.name == 'device-revoke' ? [
      {
        name: 'id'
        type: 'string'
        required: true
      }
    ] : []
  }
}]

resource inferenceStreamOperation 'Microsoft.ApiManagement/service/apis/operations@2024-06-01-preview' = {
  parent: api
  name: 'inference-stream'
  properties: {
    displayName: 'Inference stream (SSE)'
    method: 'POST'
    urlTemplate: '/inference/stream'
  }
}

resource inferenceStreamPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2024-06-01-preview' = {
  parent: inferenceStreamOperation
  name: 'policy'
  properties: {
    format: 'rawxml'
    value: loadTextContent('../../apim/inference-stream-operation-policy.xml')
  }
}

// ADR-0012: JWKS is a fixed RFC 8615 well-known path at the issuer's true
// root (apiwriterflow.aviusolutions.com/.well-known/jwks.json), not under /v2 — a
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
output gatewayHost string = '${apim.name}.azure-api.net'
output identityPrincipalId string = apim.identity.principalId
