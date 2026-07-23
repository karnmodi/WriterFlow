// Status: code complete; cloud apply pending.

param namePrefix string
param location string
param retentionInDays int = 30
param notificationEmail string

resource workspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: '${namePrefix}-logs'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${namePrefix}-appinsights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
  }
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: '${namePrefix}-operations'
  location: 'global'
  properties: {
    groupShortName: 'WriterFlow'
    enabled: true
    emailReceivers: [
      {
        name: 'engineering'
        emailAddress: notificationEmail
        useCommonAlertSchema: true
      }
    ]
  }
}

var logAlerts = [
  {
    name: 'api-5xx'
    description: 'WriterFlow API returned server errors.'
    severity: 1
    threshold: 4
    query: 'ContainerAppConsoleLogs_CL | extend record=parse_json(Log_s) | where toint(record.res.statusCode) >= 500'
  }
  {
    name: 'auth-failures'
    description: 'Authentication or authorization failures exceeded the beta baseline.'
    severity: 2
    threshold: 19
    query: 'ContainerAppConsoleLogs_CL | extend record=parse_json(Log_s) | where toint(record.res.statusCode) in (401, 403)'
  }
  {
    name: 'api-latency'
    description: 'API requests exceeded two seconds.'
    severity: 2
    threshold: 9
    query: 'ContainerAppConsoleLogs_CL | extend record=parse_json(Log_s) | where todouble(record.responseTime) > 2000'
  }
  {
    name: 'sse-disconnects'
    description: 'Inference clients disconnected before stream completion.'
    severity: 2
    threshold: 9
    query: 'ContainerAppConsoleLogs_CL | extend record=parse_json(Log_s) | where tostring(record.event) == "inference.sse_disconnect"'
  }
  {
    name: 'ledger-mismatch'
    description: 'The accounting reconciler detected a usage-ledger mismatch.'
    severity: 1
    threshold: 0
    query: 'ContainerAppConsoleLogs_CL | extend record=parse_json(Log_s) | where tostring(record.event) == "accounting.ledger_mismatch"'
  }
]

resource scheduledAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for alert in logAlerts: {
  name: '${namePrefix}-${alert.name}'
  location: location
  kind: 'LogAlert'
  properties: {
    displayName: alert.description
    severity: alert.severity
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    scopes: [
      workspace.id
    ]
    criteria: {
      allOf: [
        {
          query: alert.query
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: alert.threshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    autoMitigate: true
    actions: {
      actionGroups: [
        actionGroup.id
      ]
    }
  }
}]

output workspaceId string = workspace.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output actionGroupId string = actionGroup.id
