targetScope = 'resourceGroup'

/*
  Deploy an Azure Function App with Flex Consumption plan, managed identity, diagnostics, and a private endpoint
  https://raw.githubusercontent.com/Azure-Samples/azure-functions-flex-consumption-samples/refs/heads/main/IaC/bicep/main.bicep
*/

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('The name of the workload\'s existing Log Analytics workspace.')
@minLength(4)
param logAnalyticsWorkspaceName string

@description('The name of the existing virtual network that this Web App instance will be deployed into for egress and a private endpoint for ingress.')
@minLength(1)
param virtualNetworkName string

@description('The name of the existing subnet in the virtual network that is where this web app will have its egress point.')
@minLength(1)
param appServicesSubnetName string

@description('The name of the subnet that private endpoints in the workload should surface in.')
@minLength(1)
param privateEndpointsSubnetName string

@description('The name of the existing Azure Storage account that the Azure Web App will be pulling code deployments from.')
@minLength(3)
param existingWebAppDeploymentStorageAccountName string

@description('The name of the existing Azure Application Insights instance that the Azure Web App will be using.')
@minLength(1)
param existingWebApplicationInsightsResourceName string

@description('The name of the existing Azure AI Foundry instance that the Azure Web App code will be calling for Foundry Agent Service agents.')
@minLength(2)
param existingAzureAiFoundryResourceName string

@description('The name of the existing Azure AI Foundry project name.')
@minLength(2)
param existingAzureAiFoundryProjectName string

// variables
var appName = 'func-${baseName}'

// ---- Existing resources ----

@description('Existing Application Insights instance. Logs from the web app will be sent here.')
resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: existingWebApplicationInsightsResourceName
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: virtualNetworkName

  resource appServicesSubnet 'subnets' existing = {
    name: appServicesSubnetName
  }
  resource privateEndpointsSubnet 'subnets' existing = {
    name: privateEndpointsSubnetName
  }
}

@description('Existing Azure Storage account. This is where the web app code is deployed from.')
resource webAppDeploymentStorageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: existingWebAppDeploymentStorageAccountName
}

resource logWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

// If your web app/API code is going to be creating agents dynamically, you will need to assign a role such as this to App Service managed identity.
/*@description('Built-in Role: [Azure AI Project Manager](https://learn.microsoft.com/azure/ai-foundry/concepts/rbac-azure-ai-foundry?pivots=fdp-project#azure-ai-user)')
resource azureAiProjectManagerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'eadc314b-1a2d-4efa-be10-5d325db5065e'
  scope: subscription()
}*/

resource appServiceExistingPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.azurewebsites.net'
}

@description('Existing Azure AI Foundry account. This account is where the agents hosted in Foundry Agent Service will be deployed. The web app code calls to these agents.')
resource aiFoundry 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: existingAzureAiFoundryResourceName

  resource project 'projects' existing = {
    name: existingAzureAiFoundryProjectName
  }
}

// ---- New resources ----

@description('Managed Identity for Function App')
resource appServiceManagedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${appName}'
  location: location
}

@description('Flex Consumption plan for the Python Function App')
resource flexFuncPlan 'Microsoft.Web/serverfarms@2024-11-01' = {
  name: 'asp-${appName}${uniqueString(subscription().subscriptionId)}'
  location: location
  kind: 'functionapp'
  sku: {
    tier: 'FlexConsumption'
    name: 'FC1'
  }
  properties: {
    reserved: true
    zoneRedundant: false
  }
}

@description('Azure Function App with Python runtime on Flex Consumption plan')
resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: appName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${appServiceManagedIdentity.id}': {}
    }
  }
  properties: {
    serverFarmId: flexFuncPlan.id
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${webAppDeploymentStorageAccount.properties.primaryEndpoints.blob}deploy'
          authentication: {
            type: 'UserAssignedIdentity'
            userAssignedIdentityResourceId: appServiceManagedIdentity.id
          }
        }
      }
      scaleAndConcurrency: {
        maximumInstanceCount: 100
        instanceMemoryMB: 2048
      }
      runtime: {
        name: 'python'
        version: '3.12'
      }
    }
  }
  resource configAppSettings 'config' = {
    name: 'appsettings'
    properties: {
      AzureWebJobsStorage__accountName: webAppDeploymentStorageAccount.name
      AzureWebJobsStorage__clientId: appServiceManagedIdentity.properties.clientId
      AzureWebJobsStorage__credential: 'managedidentity'
      APPLICATIONINSIGHTS_CONNECTION_STRING: applicationInsights.properties.ConnectionString
      APPLICATIONINSIGHTS_AUTHENTICATION_STRING: 'ClientId=${appServiceManagedIdentity.properties.clientId};Authorization=AAD;'
      // Azure AI integration
      AZURE_CLIENT_ID: appServiceManagedIdentity.properties.clientId
      AIProjectEndpoint: aiFoundry::project.properties.endpoints['AI Foundry API']
      AIAgentId: 'Not yet set' // Will be set once the agent is created
      XDT_MicrosoftApplicationInsights_Mode: 'Recommended'
    }
  }

  // Removed dependsOn for role assignments (now created in role-assign-aad.bicep)
  @description('Disable SCM publishing integration.')
  resource scm 'basicPublishingCredentialsPolicies' = {
    name: 'scm'
    properties: {
      allow: false
    }
  }

  @description('Disable FTP publishing integration.')
  resource ftp 'basicPublishingCredentialsPolicies' = {
    name: 'ftp'
    properties: {
      allow: false
    }
  }
}

resource appServicePrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-front-end-func-app'
  location: location
  properties: {
    subnet: {
      id: virtualNetwork::privateEndpointsSubnet.id
    }
    customNetworkInterfaceName: 'nic-front-end-func-app'
    privateLinkServiceConnections: [
      {
        name: 'front-end-func-app'
        properties: {
          privateLinkServiceId: webApp.id
          groupIds: [
            'sites'
          ]
        }
      }
    ]
  }

  resource appServiceDnsZoneGroup 'privateDnsZoneGroups' = {
    name: 'front-end-func-app'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'func-app'
          properties: {
            privateDnsZoneId: appServiceExistingPrivateDnsZone.id
          }
        }
      ]
    }
  }
}

// Note: Autoscale is built into Flex Consumption plan, no separate autoscale settings needed

// ---- Outputs ----

@description('The name of the function app plan.')
output appServicePlanName string = flexFuncPlan.name

@description('The name of the function app.')
output appName string = webApp.name
