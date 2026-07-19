// Workload-profiles Container Apps environment on a custom VNet with the
// internal VIP, no public ingress at the environment level — Stage 5.1
// "Create a workload-profiles Container Apps environment on a custom VNet
// with an internal VIP/public network disabled." The API app itself uses
// app-level external=true ingress so APIM can reach it (see
// container-app-api.bicep); that is external to the environment, not the
// internet. Status: code complete; cloud apply pending.

param namePrefix string
param location string
param infrastructureSubnetId string
param logAnalyticsWorkspaceId string
param internal bool = true

resource environment 'Microsoft.App/managedEnvironments@2024-10-02-preview' = {
  name: '${namePrefix}-cae'
  location: location
  properties: {
    vnetConfiguration: {
      internal: internal
      infrastructureSubnetId: infrastructureSubnetId
    }
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: reference(logAnalyticsWorkspaceId, '2025-02-01').customerId
        sharedKey: listKeys(logAnalyticsWorkspaceId, '2025-02-01').primarySharedKey
      }
    }
    workloadProfiles: [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ]
  }
}

output environmentId string = environment.id
output defaultDomain string = environment.properties.defaultDomain
output staticIp string = environment.properties.staticIp
