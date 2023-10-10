targetScope = 'resourceGroup'

param location string = 'westeurope'

@description('Name of the Log Analytics workspace. Default: "ado-agents-infra-la-<uniquestring>"')
param laWorkspaceName string = 'ado-agents-infra-la-${uniqueString(resourceGroup().id)}'

@description('Whether to use a private network for the solution. Default: true')
param usePrivateNetwork bool = true

@description('Name of the virtual network. Default: "ado-agents-infra-vnet"')
param vnetName string = 'ado-agents-infra-vnet'

@description('Address prefix of the virtual network. Default: 10.0.0.0/24 ')
param vnetPrefix string = '10.0.0.0/24'

resource laWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: laWorkspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      immediatePurgeDataOn30Days: true
    }
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = if(usePrivateNetwork) {
  name: vnetName
  location: location
  properties:{
    addressSpace:{
      addressPrefixes:[
        vnetPrefix
      ]
    }
  }
}

resource vnetDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if(usePrivateNetwork) {
  name: 'acrSendAllLogsToLogAnalytics'
  scope: vnet
  properties: {
    workspaceId: laWorkspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        enabled: true
        categoryGroup: 'allLogs'
      }
    ]
    metrics: [
      {
        enabled: true
        category: 'AllMetrics'
      }
    ]
  }
}

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = if(usePrivateNetwork) {
  name: 'privatelink${environment().suffixes.acrLoginServer}'
  location: 'global'
  properties: {}
}

resource acrToVirtualNetwork 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = if (usePrivateNetwork) {
  parent: acrPrivateDnsZone
  name: 'link_to_${toLower(vnet.name)}'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

output laWorkspaceId string = laWorkspace.id
output laWorkspaceName string = laWorkspace.name
output vnetId string = usePrivateNetwork ? vnet.id : ''
output vnetName string = usePrivateNetwork ? vnet.name : ''
output acrPrivateDnsZoneId string = usePrivateNetwork ? acrPrivateDnsZone.id : ''
