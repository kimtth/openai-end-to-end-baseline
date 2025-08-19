targetScope = 'resourceGroup'

/* 
Role assignments from failed deployments:
Consolidate all role assignments into this file which failed during deployment. 
*/

// Parameters
@minLength(6)
@maxLength(8)
param baseName string

@maxLength(36)
@minLength(36)
param debugUserPrincipalId string

@maxLength(36)
@minLength(36)
param aiFoundryPortalUserPrincipalId string

@description('The principal ID of the AI Foundry project managed identity')
@minLength(36)
@maxLength(36)
param aiFoundryProjectPrincipalId string

@description('The resource ID of the AI Foundry project')
param aiFoundryProjectId string

@description('The workspace ID as GUID for storage container conditions')
param workspaceIdAsGuid string

@description('The Cosmos SQL role assignment scope. ')
param cosmosDbAccountId string = ''

@description('The principal ID (GUID) of the Function App user-assigned managed identity.')
@minLength(36)
@maxLength(36)
param functionAppManagedIdentityPrincipalId string

@description('The name of the Key Vault used by Application Gateway for its certificate.')
param keyVaultName string

@description('The principal ID (GUID) of the App Gateway user-assigned managed identity.')
@minLength(36)
@maxLength(36)
param appGatewayManagedIdentityPrincipalId string

// Built-in roles (existing)
resource storageBlobDataOwnerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Storage Blob Data Owner
  name: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  scope: subscription()
}

resource storageBlobDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Storage Blob Data Contributor
  name: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  scope: subscription()
}

resource azureAISearchIndexDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Azure AI Search Index Data Contributor
  name: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  scope: subscription()
}

resource azureAISearchServiceContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Azure AI Search Service Contributor
  name: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  scope: subscription()
}

resource cognitiveServicesUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Cognitive Services User
  name: 'a97b65f3-24c7-4388-baec-2e87135dc908'
  scope: subscription()
}

resource cosmosDbAccountReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Cosmos DB Account Reader Role
  name: 'fbdf93bf-df7d-467e-a4d2-9458aa1360c8'
  scope: subscription()
}

resource cosmosDbOperatorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Cosmos DB Operator
  name: '230815da-be43-4aae-9cb4-875f7bd000aa'
  scope: subscription()
}

resource blobDataReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Storage Blob Data Reader
  name: '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
  scope: subscription()
}

resource storageQueueDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Storage Queue Data Contributor
  name: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  scope: subscription()
}

resource storageTableDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Storage Table Data Contributor
  name: '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3'
  scope: subscription()
}

resource azureAiUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Azure AI User
  name: '53ca6127-db72-4b80-b1b0-d745d6d5456d'
  scope: subscription()
}

resource keyVaultSecretsUserRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  // Key Vault Secrets User
  name: '4633458b-17de-408a-b874-0445c86b69e6'
  scope: subscription()
}

// Existing resources (by naming convention from the base templates)
resource agentStorageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  // stagent${baseName}
  name: 'stagent${baseName}'
}

resource appDeployStorage 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  // stwebapp${baseName}
  name: 'stwebapp${baseName}'
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2024-01-01' existing = {
  name: 'default'
  parent: appDeployStorage
}

resource deployContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' existing = {
  name: 'deploy'
  parent: blobService
}

resource azureAiSearchService 'Microsoft.Search/searchServices@2025-02-01-preview' existing = {
  // ais-ai-agent-vector-store-${baseName}
  name: 'ais-ai-agent-vector-store-${baseName}'
}

resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  // aif${baseName}
  name: 'aif${baseName}'
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' existing = {
  // cdb-ai-agent-threads-${baseName}
  name: 'cdb-ai-agent-threads-${baseName}'
}

resource cosmosDataContributorRole 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions@2024-12-01-preview' existing = {
  // Built-in Cosmos DB Data Contributor
  name: '00000000-0000-0000-0000-000000000002'
  parent: cosmosDbAccount
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-11-01' existing = {
  name: keyVaultName
}

// ai-agent-blob-storage.bicep: Assign Storage Blob Data Owner at the storage account scope
@description('Assign your user the Storage Blob Data Owner role at the storage account scope.')
resource debugUserBlobDataOwnerAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(debugUserPrincipalId, storageBlobDataOwnerRole.id, agentStorageAccount.id)
  scope: agentStorageAccount
  properties: {
    principalId: debugUserPrincipalId
    roleDefinitionId: storageBlobDataOwnerRole.id
    principalType: 'User'
  }
}

// web-app-storage.bicep: Assign Storage Blob Data Contributor at the container scope
@description('Assign your user the ability to manage application deployment files in blob storage.')
resource blobStorageContributorForUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(deployContainer.id, debugUserPrincipalId, storageBlobDataContributorRole.id)
  scope: deployContainer
  properties: {
    roleDefinitionId: storageBlobDataContributorRole.id
    principalType: 'User'
    principalId: debugUserPrincipalId // Part of the deployment guide requires you to upload the web app to this storage container. Assigning that data plane permission here. Ideally your CD pipeline would have this permission instead.
  }
}

// ai-search.bicep: Assign Azure AI Search Index Data Contributor at search service scope
@description('Assign your user the Azure AI Search Index Data Contributor role to support troubleshooting post deployment. Not needed for normal operation.')
resource debugUserAISearchIndexDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(debugUserPrincipalId, azureAISearchIndexDataContributorRole.id, azureAiSearchService.id)
  scope: azureAiSearchService
  properties: {
    roleDefinitionId: azureAISearchIndexDataContributorRole.id
    principalId: debugUserPrincipalId
    principalType: 'User'
  }
}

// ai-foundry.bicep: Assign Cognitive Services User for Foundry portal access
@description('Assign yourself to have access to the Azure AI Foundry portal.')
resource cognitiveServicesUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundry.id, cognitiveServicesUserRole.id, aiFoundryPortalUserPrincipalId)
  scope: aiFoundry
  properties: {
    roleDefinitionId: cognitiveServicesUserRole.id
    principalId: aiFoundryPortalUserPrincipalId
    principalType: 'User'
  }
}

// cosmos-db.bicep: Assign Cosmos DB Account Reader at account scope
resource assignDebugUserToCosmosAccountReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(debugUserPrincipalId, cosmosDbAccountReaderRole.id, cosmosDbAccount.id)
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: cosmosDbAccountReaderRole.id
    principalId: debugUserPrincipalId
    principalType: 'User'
  }
}

// Assign Cosmos DB Account Data Contributor at account scope
@description('Assign your own user to access the enterprise_memory database contents for troubleshooting purposes. Not required for normal usage.')
resource userToCosmosAccountScope 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-12-01-preview' = {
  name: guid(debugUserPrincipalId, cosmosDataContributorRole.id, cosmosDbAccount.id)
  parent: cosmosDbAccount
  properties: {
    roleDefinitionId: cosmosDataContributorRole.id
    principalId: debugUserPrincipalId
    scope: empty(cosmosDbAccountId) ? '/' : cosmosDbAccountId
  }
}

// AI Foundry Project Role Assignments (moved from ai-foundry-project.bicep)
resource projectDbCosmosDbOperatorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiFoundryProjectPrincipalId)) {
  name: guid(aiFoundryProjectId, cosmosDbOperatorRole.id, cosmosDbAccount.id)
  scope: cosmosDbAccount
  properties: {
    roleDefinitionId: cosmosDbOperatorRole.id
    principalId: aiFoundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource projectBlobDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiFoundryProjectPrincipalId)) {
  name: guid(aiFoundryProjectId, storageBlobDataContributorRole.id, agentStorageAccount.id)
  scope: agentStorageAccount
  properties: {
    roleDefinitionId: storageBlobDataContributorRole.id
    principalId: aiFoundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource projectBlobDataOwnerConditionalAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiFoundryProjectPrincipalId) && !empty(workspaceIdAsGuid)) {
  name: guid(aiFoundryProjectId, storageBlobDataOwnerRole.id, agentStorageAccount.id)
  scope: agentStorageAccount
  properties: {
    principalId: aiFoundryProjectPrincipalId
    roleDefinitionId: storageBlobDataOwnerRole.id
    principalType: 'ServicePrincipal'
    conditionVersion: '2.0'
    condition: '((!(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/read\'})  AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/filter/action\'}) AND  !(ActionMatches{\'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/tags/write\'}) ) OR (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringStartsWithIgnoreCase \'${workspaceIdAsGuid}\'))'
  }
}

resource projectAISearchContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiFoundryProjectPrincipalId)) {
  name: guid(aiFoundryProjectId, azureAISearchServiceContributorRole.id, azureAiSearchService.id)
  scope: azureAiSearchService
  properties: {
    roleDefinitionId: azureAISearchServiceContributorRole.id
    principalId: aiFoundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

resource projectAISearchIndexDataContributorAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aiFoundryProjectPrincipalId)) {
  name: guid(aiFoundryProjectId, azureAISearchIndexDataContributorRole.id, azureAiSearchService.id)
  scope: azureAiSearchService
  properties: {
    roleDefinitionId: azureAISearchIndexDataContributorRole.id
    principalId: aiFoundryProjectPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// web-app.bicep: Role assignments for the Function App managed identity
@description('Assign the Function App managed identity the Storage Blob Data Reader role at the storage account scope.')
resource funcBlobDataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appDeployStorage.id, functionAppManagedIdentityPrincipalId, blobDataReaderRole.id)
  scope: appDeployStorage
  properties: {
    roleDefinitionId: blobDataReaderRole.id
    principalType: 'ServicePrincipal'
    principalId: functionAppManagedIdentityPrincipalId
  }
}

@description('Assign the Function App managed identity the Storage Queue Data Contributor role at the storage account scope.')
resource funcBlobDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appDeployStorage.id, functionAppManagedIdentityPrincipalId, storageBlobDataContributorRole.id)
  scope: appDeployStorage
  properties: {
    roleDefinitionId: storageBlobDataContributorRole.id
    principalType: 'ServicePrincipal'
    principalId: functionAppManagedIdentityPrincipalId
  }
}

@description('Assign the Function App managed identity the Storage Queue Data Contributor role at the storage account scope.')
resource funcQueueDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appDeployStorage.id, functionAppManagedIdentityPrincipalId, storageQueueDataContributorRole.id)
  scope: appDeployStorage
  properties: {
    roleDefinitionId: storageQueueDataContributorRole.id
    principalType: 'ServicePrincipal'
    principalId: functionAppManagedIdentityPrincipalId
  }
}

@description('Assign the Function App managed identity the Storage Table Data Contributor role at the storage account scope.')
resource funcTableDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appDeployStorage.id, functionAppManagedIdentityPrincipalId, storageTableDataContributorRole.id)
  scope: appDeployStorage
  properties: {
    roleDefinitionId: storageTableDataContributorRole.id
    principalType: 'ServicePrincipal'
    principalId: functionAppManagedIdentityPrincipalId
  }
}

// Scope: Azure AI Foundry account aif${baseName}
@description('Assign the Function App managed identity the Azure AI User role at the Azure AI Foundry account scope.')
resource funcAzureAiUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiFoundry.id, functionAppManagedIdentityPrincipalId, azureAiUserRole.id)
  scope: aiFoundry
  properties: {
    roleDefinitionId: azureAiUserRole.id
    principalType: 'ServicePrincipal'
    principalId: functionAppManagedIdentityPrincipalId
  }
}

// Grant App Gateway MI access to Key Vault secrets (moved from application-gateway.bicep)
@description('Assign the Application Gateway managed identity the Key Vault Secrets User role at the Key Vault scope.')
resource appGatewayKeyVaultSecretsUserAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, appGatewayManagedIdentityPrincipalId, keyVaultSecretsUserRole.id)
  scope: keyVault
  properties: {
    roleDefinitionId: keyVaultSecretsUserRole.id
    principalId: appGatewayManagedIdentityPrincipalId
    principalType: 'ServicePrincipal'
  }
}
