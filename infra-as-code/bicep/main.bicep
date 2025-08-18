targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('Domain name to use for App Gateway')
@minLength(3)
param customDomainName string = 'cloudapp.azure.com'

@description('The certificate data for app gateway TLS termination. The value is base64 encoded.')
@secure()
@minLength(1)
param appGatewayListenerCertificate string

@description('Specifies the password of the administrator account on the Windows jump box.\n\nComplexity requirements: 3 out of 4 conditions below need to be fulfilled:\n- Has lower characters\n- Has upper characters\n- Has a digit\n- Has a special character\n\nDisallowed values: "abc@123", "P@$$w0rd", "P@ssw0rd", "P@ssword123", "Pa$$word", "pass@word1", "Password!", "Password1", "Password22", "iloveyou!"')
@secure()
@minLength(8)
@maxLength(123)
param jumpBoxAdminPassword string

@description('Assign your user some roles to support fluid access when working in the Azure AI Foundry portal and its dependencies.')
@maxLength(36)
@minLength(36)
param yourPrincipalId string

@description('Set to true to opt-out of deployment telemetry.')
param telemetryOptOut bool = false

// Customer Usage Attribution Id
var varCuaid = 'a52aa8a8-44a8-46e9-b7a5-189ab3a64409'

// Toggle to activate role assignment module
var enableRoleAssignments = false

// ---- New resources ----

@description('Deploy an example set of Azure Policies to help you govern your workload. Expand the policy set as desired.')
module applyAzurePolicies 'azure-policies.bicep' = {
  name: 'policiesDeploy'
  scope: resourceGroup()
  params: {
    baseName: baseName
  }
}

@description('This is the log sink for all Azure Diagnostics in the workload.')
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' = {
  name: 'log-workload'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    forceCmkForQuery: false
    workspaceCapping: {
      dailyQuotaGb: 10 // Production readiness change: In production, tune this value to ensure operational logs are collected, but a reasonable cap is set.
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

@description('Deploy Virtual Network, with subnets, NSGs, and DDoS Protection.')
module deployVirtualNetwork 'network.bicep' = {
  name: 'networkDeploy'
  scope: resourceGroup()
  params: {
    location: location
  }
}

@description('Control egress traffic through Azure Firewall restrictions.')
module deployAzureFirewall 'azure-firewall.bicep' = {
  name: 'azureFirewallDeploy'
  scope: resourceGroup()
  params: {
    location: location
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    virtualNetworkName: deployVirtualNetwork.outputs.virtualNetworkName
    agentsEgressSubnetName: deployVirtualNetwork.outputs.agentsEgressSubnetName
    jumpBoxesSubnetName: deployVirtualNetwork.outputs.jumpBoxesSubnetName
  }
}

@description('Deploys Azure Bastion and the jump box, which is used for private access to Azure AI Foundry and its dependencies.')
module deployJumpBox 'jump-box.bicep' = {
  name: 'jumpBoxDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    virtualNetworkName: deployVirtualNetwork.outputs.virtualNetworkName
    jumpBoxSubnetName: deployVirtualNetwork.outputs.jumpBoxSubnetName
    jumpBoxAdminName: 'vmadmin'
    jumpBoxAdminPassword: jumpBoxAdminPassword
  }
  dependsOn: [
    deployAzureFirewall // Makes sure that egress traffic is controlled before workload resources start being deployed
  ]
}

// Deploy the Azure AI Foundry account and Foundry Agent Service components.

@description('Deploy Azure AI Foundry with Azure AI Foundry Agent capability. No projects yet deployed.')
module deployAzureAIFoundry 'ai-foundry.bicep' = {
  name: 'aiFoundryDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    agentSubnetResourceId: deployVirtualNetwork.outputs.agentsEgressSubnetResourceId
    privateEndpointSubnetResourceId: deployVirtualNetwork.outputs.privateEndpointsSubnetResourceId
  }
  dependsOn: [
    deployAzureFirewall // Makes sure that egress traffic is controlled before workload resources start being deployed
  ]
}

@description('Deploys the Azure AI Foundry Agent dependencies, Azure Storage, Azure AI Search, and Cosmos DB.')
module deployAIAgentServiceDependencies 'ai-agent-service-dependencies.bicep' = {
  name: 'aiAgentServiceDependenciesDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    privateEndpointSubnetResourceId: deployVirtualNetwork.outputs.privateEndpointsSubnetResourceId
  }
}

@description('Deploy the Bing account for Internet grounding data to be used by agents in the Azure AI Foundry Agent Service.')
module deployBingAccount 'bing-grounding.bicep' = {
  name: 'bingGroundingDeploy'
  scope: resourceGroup()
  params: {
    baseName: baseName
  }
}

@description('Deploy the Azure AI Foundry project into the AI Foundry account. This is the project is the home of the Foundry Agent Service.')
module deployAzureAiFoundryProject 'ai-foundry-project.bicep' = {
  name: 'aiFoundryProjectDeploy'
  scope: resourceGroup()
  params: {
    location: location
    existingAiFoundryName: deployAzureAIFoundry.outputs.aiFoundryName
    existingAISearchAccountName: deployAIAgentServiceDependencies.outputs.aiSearchName
    existingCosmosDbAccountName: deployAIAgentServiceDependencies.outputs.cosmosDbAccountName
    existingStorageAccountName: deployAIAgentServiceDependencies.outputs.storageAccountName
    existingBingAccountName: deployBingAccount.outputs.bingAccountName
    existingWebApplicationInsightsResourceName: deployApplicationInsights.outputs.applicationInsightsName
  }
  dependsOn: [
    deployJumpBox
  ]
}

// Deploy the Azure Web App resources for the chat UI.

@description('Deploy an Azure Storage account that is used by the Azure Web App for the deployed application code.')
module deployWebAppStorage 'web-app-storage.bicep' = {
  name: 'webAppStorageDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    virtualNetworkName: deployVirtualNetwork.outputs.virtualNetworkName
    privateEndpointsSubnetName: deployVirtualNetwork.outputs.privateEndpointsSubnetName
  }
  dependsOn: [
    deployAIAgentServiceDependencies // There is a Storage account in the AI Agent dependencies module, both will be updating the same private DNS zone, want to run them in series to avoid conflict errors.
  ]
}

@description('Deploy Azure Key Vault. In this architecture, it\'s used to store the certificate for the Application Gateway.')
module deployKeyVault 'key-vault.bicep' = {
  name: 'keyVaultDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    virtualNetworkName: deployVirtualNetwork.outputs.virtualNetworkName
    privateEndpointsSubnetName: deployVirtualNetwork.outputs.privateEndpointsSubnetName
    appGatewayListenerCertificate: appGatewayListenerCertificate
  }
}

@description('Deploy Application Insights. Used by the Azure Web App to monitor the deployed application and connected to the Azure AI Foundry project.')
module deployApplicationInsights 'application-insights.bicep' = {
  name: 'applicationInsightsDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
  }
}

@description('Deploy the web app for the front end demo UI. The web application will call into the Azure AI Foundry Agent Service.')
module deployWebApp 'web-app.bicep' = {
  name: 'webAppDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    virtualNetworkName: deployVirtualNetwork.outputs.virtualNetworkName
    appServicesSubnetName: deployVirtualNetwork.outputs.appServicesSubnetName
    privateEndpointsSubnetName: deployVirtualNetwork.outputs.privateEndpointsSubnetName
    existingWebAppDeploymentStorageAccountName: deployWebAppStorage.outputs.appDeployStorageName
    existingWebApplicationInsightsResourceName: deployApplicationInsights.outputs.applicationInsightsName
    existingAzureAiFoundryResourceName: deployAzureAIFoundry.outputs.aiFoundryName
    existingAzureAiFoundryProjectName: deployAzureAiFoundryProject.outputs.aiAgentProjectName
  }
}

@description('Deploy an Azure Application Gateway with WAF and a custom domain name + TLS cert.')
module deployApplicationGateway 'application-gateway.bicep' = {
  name: 'applicationGatewayDeploy'
  scope: resourceGroup()
  params: {
    location: location
    baseName: baseName
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.name
    customDomainName: customDomainName
    appName: deployWebApp.outputs.appName
    virtualNetworkName: deployVirtualNetwork.outputs.virtualNetworkName
    applicationGatewaySubnetName: deployVirtualNetwork.outputs.applicationGatewaySubnetName
    keyVaultName: deployKeyVault.outputs.keyVaultName
    gatewayCertSecretKey: deployKeyVault.outputs.gatewayCertSecretKey
  }
}

// Existing reference to the Function App's user-assigned identity created in web-app.bicep
resource functionAppUserAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-func-${baseName}'
}

// Existing reference to the App Gateway managed identity created in application-gateway.bicep
resource appGatewayUserAssignedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' existing = {
  name: 'id-agw-${baseName}'
}

// Call role-assign-aad.bicep to grant roles to users, AI Foundry project, and the Function App identity
module roleAssignments 'role-assign-aad.bicep' = if (enableRoleAssignments) {
  name: 'roleAssignmentsDeploy'
  scope: resourceGroup()
  params: {
    baseName: baseName
    debugUserPrincipalId: yourPrincipalId
    aiFoundryPortalUserPrincipalId: yourPrincipalId
    aiFoundryProjectPrincipalId: deployAzureAiFoundryProject.outputs.aiFoundryProjectPrincipalId
    aiFoundryProjectId: deployAzureAiFoundryProject.outputs.aiFoundryProjectId
    workspaceIdAsGuid: deployAzureAiFoundryProject.outputs.workspaceIdAsGuid
    functionAppManagedIdentityPrincipalId: functionAppUserAssignedIdentity.properties.principalId
    keyVaultName: deployKeyVault.outputs.keyVaultName
    appGatewayManagedIdentityPrincipalId: appGatewayUserAssignedIdentity.properties.principalId
  }
  dependsOn: [
    deployWebApp
    deployApplicationGateway
  ]
}

// Optional Deployment for Customer Usage Attribution
module customerUsageAttributionModule 'customerUsageAttribution/cuaIdResourceGroup.bicep' = if (!telemetryOptOut) {
  #disable-next-line no-loc-expr-outside-params // Only to ensure telemetry data is stored in same location as deployment. See https://github.com/Azure/ALZ-Bicep/wiki/FAQ#why-are-some-linter-rules-disabled-via-the-disable-next-line-bicep-function for more information
  name: 'pid-${varCuaid}-${uniqueString(resourceGroup().location)}'
  scope: resourceGroup()
  params: {}
}
