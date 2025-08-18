targetScope = 'resourceGroup'

@description('The region in which this architecture is deployed. Should match the region of the resource group.')
@minLength(1)
param location string = resourceGroup().location

@description('This is the base name for each Azure resource name (6-8 chars)')
@minLength(6)
@maxLength(8)
param baseName string

@description('The name of the workload\'s existing Log Analytics workspace.')
@minLength(4)
param logAnalyticsWorkspaceName string

@description('The resource ID for the subnet that private endpoints in the workload should surface in.')
@minLength(1)
param privateEndpointSubnetResourceId string

// ---- Existing resources ----

resource cosmosDbLinkedPrivateDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.documents.azure.com'
}

// Cosmos DB Account Reader Role
#disable-next-line no-unused-existing-resources // Kept for optional debug role assignment wiring
resource cosmosDbAccountReaderRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: 'fbdf93bf-df7d-467e-a4d2-9458aa1360c8'
  scope: subscription()
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2025-02-01' existing = {
  name: logAnalyticsWorkspaceName
}

// ---- New resources ----

@description('Deploy an Azure Cosmos DB account. This is a BYO dependency for the Azure AI Foundry Agent Service. It\'s used to store threads and agent definitions.')
resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2024-12-01-preview' = {
  name: 'cdb-ai-agent-threads-${baseName}'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    disableLocalAuth: false // Enable local authentication for development
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    minimalTlsVersion: 'Tls12'
    publicNetworkAccess: 'Disabled'
    enableFreeTier: false
    ipRules: []
    virtualNetworkRules: []
    networkAclBypass: 'None'
    networkAclBypassResourceIds: []
    diagnosticLogSettings: {
      enableFullTextQuery: 'False'
    }
    enableBurstCapacity: false
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false // Production readiness change: Some subscriptions do not have quota to support zone redundancy in their selected region. Before going to production, test this capability and if not available, work with Microsoft support to ensure you have capacity in your region and enable this.
      }
    ]
    databaseAccountOfferType: 'Standard'
    backupPolicy: {
      type: 'Continuous'
      continuousModeProperties: {
        tier: 'Continuous7Days' // You have seven days of continuous backup to address point-in-time restore needs.
      }
    }
  }

  @description('Built-in Cosmos DB Data Contributor role that can be assigned to Entra identities to grant data access on a Cosmos DB database.')
  resource dataContributorRole 'sqlRoleDefinitions' existing = {
    name: '00000000-0000-0000-0000-000000000002'
  }
}

@description('Capture platform logs for the Cosmos DB account.')
resource azureDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'default'
  scope: cosmosDbAccount
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'DataPlaneRequests'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'PartitionKeyRUConsumption'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'ControlPlaneRequests'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'DataPlaneRequests5M'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
      {
        category: 'DataPlaneRequests15M'
        enabled: true
        retentionPolicy: {
          enabled: false
          days: 0
        }
      }
    ]
  }
}

// Private endpoints

resource cosmosDbPrivateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-ai-agent-threads'
  location: resourceGroup().location
  properties: {
    subnet: {
      id: privateEndpointSubnetResourceId
    }
    customNetworkInterfaceName: 'nic-ai-agent-threads'
    privateLinkServiceConnections: [
      {
        name: 'ai-agent-cosmosdb'
        properties: {
          privateLinkServiceId: cosmosDbAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }

  resource dnsGroup 'privateDnsZoneGroups' = {
    name: 'ai-agent-cosmosdb'
    properties: {
      privateDnsZoneConfigs: [
        {
          name: 'ai-agent-cosmosdb'
          properties: {
            privateDnsZoneId: cosmosDbLinkedPrivateDnsZone.id
          }
        }
      ]
    }
  }
}

// ---- Outputs ----

output cosmosDbAccountName string = cosmosDbAccount.name
