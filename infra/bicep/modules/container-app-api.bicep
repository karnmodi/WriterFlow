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
param imageTag string = 'latest'
param minReplicas int = 1
param maxReplicas int = 10

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: '${namePrefix}-api-identity'
  location: location
}

resource apiApp 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${namePrefix}-api'
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
          env: [
            {
              name: 'KEY_VAULT_URI'
              value: keyVaultUri
            }
          ]
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
