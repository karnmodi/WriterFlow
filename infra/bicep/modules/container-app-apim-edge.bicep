// Public TLS edge used only with Developer APIM, whose custom-hostname
// provisioning is unreliable for this environment. The image is built from
// scripts/cloud/apim-edge and proxies to APIM's default gateway hostname.
// Custom-domain DNS validation and managed-certificate binding remain an
// explicit post-deploy step in scripts/cloud/bind-apiwriterflow.sh.

param namePrefix string
param location string
param containerAppsEnvironmentId string
param containerRegistryLoginServer string
param apimGatewayHost string
param imageTag string = 'latest'

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: '${namePrefix}-apim-edge-identity'
  location: location
}

resource edge 'Microsoft.App/containerApps@2024-10-02-preview' = {
  name: '${namePrefix}-apim-edge'
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
          name: 'apim-edge'
          image: '${containerRegistryLoginServer}/writerflow-apim-edge:${imageTag}'
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
          env: [
            {
              name: 'APIM_GATEWAY_HOST'
              value: apimGatewayHost
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
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 3
      }
    }
  }
}

output fqdn string = edge.properties.configuration.ingress.fqdn
output identityPrincipalId string = identity.properties.principalId
