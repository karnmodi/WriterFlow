// Least-privilege workload assignments for API/website Container App identities.

param containerRegistryName string
param keyVaultName string
param azureOpenAIAccountName string
param apiPrincipalId string
param websitePrincipalId string
param workerPrincipalId string = ''
param includeWorker bool = false
param migrationPrincipalId string = ''
param includeMigrationJob bool = false
param apimPrincipalId string = ''
param includeApimKeyVault bool = false
param includeAzureOpenAI bool

resource registry 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: containerRegistryName
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

resource azureOpenAI 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = if (includeAzureOpenAI) {
  name: azureOpenAIAccountName
}

// Azure Container Registry Repository Reader (data-plane pull).
var acrPullRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '7f951dda-4ed3-4680-a7ca-43fe172d538d'
)
// Key Vault Secrets User.
var keyVaultSecretsUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '4633458b-17de-408a-b874-0445c86b69e6'
)
// Key Vault Crypto User (JWT signing key).
var keyVaultCryptoUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '12338af0-0e69-4776-bea7-57ae8d297424'
)
// Cognitive Services OpenAI User.
var openAIUserRoleDefinitionId = subscriptionResourceId(
  'Microsoft.Authorization/roleDefinitions',
  '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
)

resource apiAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, apiPrincipalId, acrPullRoleDefinitionId)
  scope: registry
  properties: {
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource websiteAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(registry.id, websitePrincipalId, acrPullRoleDefinitionId)
  scope: registry
  properties: {
    principalId: websitePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource workerAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (includeWorker) {
  name: guid(registry.id, workerPrincipalId, acrPullRoleDefinitionId)
  scope: registry
  properties: {
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource migrationAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (includeMigrationJob) {
  name: guid(registry.id, migrationPrincipalId, acrPullRoleDefinitionId)
  scope: registry
  properties: {
    principalId: migrationPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: acrPullRoleDefinitionId
  }
}

resource apiKeyVaultSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, apiPrincipalId, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource apiKeyVaultCrypto 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, apiPrincipalId, keyVaultCryptoUserRoleDefinitionId)
  scope: keyVault
  properties: {
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultCryptoUserRoleDefinitionId
  }
}

resource websiteKeyVaultSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, websitePrincipalId, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    principalId: websitePrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource workerKeyVaultSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (includeWorker) {
  name: guid(keyVault.id, workerPrincipalId, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    principalId: workerPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource migrationKeyVaultSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (includeMigrationJob) {
  name: guid(keyVault.id, migrationPrincipalId, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    principalId: migrationPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource apimKeyVaultSecrets 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (includeApimKeyVault) {
  name: guid(keyVault.id, apimPrincipalId, keyVaultSecretsUserRoleDefinitionId)
  scope: keyVault
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsUserRoleDefinitionId
  }
}

resource apiOpenAIUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (includeAzureOpenAI) {
  name: guid(azureOpenAI!.id, apiPrincipalId, openAIUserRoleDefinitionId)
  scope: azureOpenAI!
  properties: {
    principalId: apiPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: openAIUserRoleDefinitionId
  }
}
