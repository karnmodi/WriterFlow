// Hard spend ceiling — Stage 5.4 "Add hard Azure budget, quota, and anomaly
// alerts", V2-ARCHITECTURE.md §17 "Hard provider and WriterFlow spend
// ceilings are active before paid/public inference." Status: code complete;
// cloud apply pending — notificationEmail must be set to a real monitored
// address before this is deployed.

param namePrefix string
@allowed(['dev', 'staging', 'prod'])
param environmentName string
param notificationEmail string = 'engineering@writerflow.app'

var monthlyAmountByEnvironment = {
  dev: 100
  staging: 500
  prod: 5000
}

resource budget 'Microsoft.Consumption/budgets@2024-08-01' = {
  name: '${namePrefix}-monthly-budget'
  properties: {
    category: 'Cost'
    amount: monthlyAmountByEnvironment[environmentName]
    timeGrain: 'Monthly'
    timePeriod: {
      startDate: '2026-08-01'
    }
    notifications: {
      actual80Percent: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 80
        contactEmails: [notificationEmail]
        thresholdType: 'Actual'
      }
      forecasted100Percent: {
        enabled: true
        operator: 'GreaterThanOrEqualTo'
        threshold: 100
        contactEmails: [notificationEmail]
        thresholdType: 'Forecasted'
      }
    }
  }
}
