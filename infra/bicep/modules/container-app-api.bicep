// services/api Container App. App-level external=true ingress (external to
// the Container Apps *environment*, which itself has no public ingress) so
// APIM's VNet-integrated outbound call can reach it — Stage 5.1 "do not use
// app-level internal ingress, which APIM cannot reach from outside that
// environment." Status: code complete; cloud apply pending.

param namePrefix string
param location string
param containerAppsEnvironmentId string
param containerRegistryLoginServer string
param keyVaultUri string
param appSuffix string = 'api'
param identitySuffix string = '${appSuffix}-identity'
param imageTag string = 'latest'
param minReplicas int = 1
param maxReplicas int = 10
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
  name: '${namePrefix}-${identitySuffix}'
  location: location
}

resource apiApp 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${namePrefix}-${appSuffix}'
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
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
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
          name: 'api'
          image: '${containerRegistryLoginServer}/writerflow-api:${imageTag}'
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
                path: '/healthz'
                port: 8080
              }
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/readyz'
                port: 8080
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

output fqdn string = apiApp.properties.configuration.ingress.fqdn
output identityPrincipalId string = identity.properties.principalId
output identityClientId string = identity.properties.clientId
