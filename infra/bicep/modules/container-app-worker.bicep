param namePrefix string
param location string
param containerAppsEnvironmentId string
param containerRegistryLoginServer string
param imageTag string = 'latest'
param databaseUrlSecretUri string
param minReplicas int = 1
param maxReplicas int = 2

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: '${namePrefix}-worker-identity'
  location: location
}

resource worker 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${namePrefix}-worker'
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
      activeRevisionsMode: 'Single'
      registries: [
        {
          server: containerRegistryLoginServer
          identity: identity.id
        }
      ]
      secrets: [
        {
          name: 'database-url'
          keyVaultUrl: databaseUrlSecretUri
          identity: identity.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'worker'
          image: '${containerRegistryLoginServer}/writerflow-worker:${imageTag}'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'NODE_ENV'
              value: 'production'
            }
            {
              name: 'DATABASE_URL'
              secretRef: 'database-url'
            }
            {
              name: 'AZURE_CLIENT_ID'
              value: identity.properties.clientId
            }
          ]
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
      }
    }
  }
}

output identityPrincipalId string = identity.properties.principalId
