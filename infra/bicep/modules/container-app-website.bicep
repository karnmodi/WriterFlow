// website/ Container App — V2-ARCHITECTURE.md §14: the confidential Entra
// client, Stripe membership, and /pair device-approval UI. Unlike
// container-app-api.bicep, this app's ingress is genuinely internet-facing:
// it runs in its own public Container Apps environment
// (container-apps-env.bicep with internal=false), not the API's
// internal-only one, since real browsers must reach writerflow.aviusolutions.com directly
// and the API's environment being internal-only is load-bearing for "APIM is
// the only public entry point to the API." Status: code complete; cloud
// apply pending — no custom domain/TLS binding is configured here yet (that
// needs a real DNS zone + managed certificate, a deploy-time step once a
// domain is available to bind).

param namePrefix string
param location string
param containerAppsEnvironmentId string
param containerRegistryLoginServer string
param keyVaultUri string
param imageTag string = 'latest'
param minReplicas int = 1
param maxReplicas int = 10
param configureCustomDomain bool = false
param customHostname string = 'writerflow.aviusolutions.com'
@description('Non-secret runtime settings, each shaped as { name, value }.')
param environmentVariables array = []
@description('Key Vault-backed settings, each shaped as { name, secretRef, keyVaultUrl }.')
param secretEnvironmentVariables array = []

var configuredEnvironment = [for setting in environmentVariables: {
  name: setting.name
  value: setting.value
}]
var configuredSecretEnvironment = [for secret in secretEnvironmentVariables: {
  name: secret.name
  secretRef: secret.secretRef
}]

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: '${namePrefix}-website-identity'
  location: location
}

resource environment 'Microsoft.App/managedEnvironments@2024-10-02-preview' existing = {
  name: last(split(containerAppsEnvironmentId, '/'))
}

resource managedCertificate 'Microsoft.App/managedEnvironments/managedCertificates@2024-10-02-preview' = if (configureCustomDomain) {
  parent: environment
  name: '${namePrefix}-website-cert'
  location: location
  properties: {
    subjectName: customHostname
    domainControlValidation: 'CNAME'
  }
}

resource websiteApp 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${namePrefix}-website'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${identity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      ingress: {
        external: true
        targetPort: 3000
        transport: 'auto'
        allowInsecure: false
        customDomains: configureCustomDomain ? [
          {
            name: customHostname
            certificateId: managedCertificate!.id
            bindingType: 'SniEnabled'
          }
        ] : []
      }
      registries: [
        {
          server: containerRegistryLoginServer
          identity: identity.id
        }
      ]
      secrets: [for secret in secretEnvironmentVariables: {
        name: secret.secretRef
        keyVaultUrl: secret.keyVaultUrl
        identity: identity.id
      }]
    }
    template: {
      containers: [
        {
          name: 'website'
          image: '${containerRegistryLoginServer}/writerflow-website:${imageTag}'
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: concat([
            {
              name: 'KEY_VAULT_URI'
              value: keyVaultUri
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: identity.properties.clientId
            }
          ], configuredEnvironment, configuredSecretEnvironment)
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/api/health/'
                port: 3000
              }
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/api/health/'
                port: 3000
              }
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        rules: [
          {
            name: 'http-concurrency'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ]
      }
    }
  }
}

output fqdn string = websiteApp.properties.configuration.ingress.fqdn
output identityPrincipalId string = identity.properties.principalId
output identityClientId string = identity.properties.clientId
