targetScope = 'resourceGroup'

param location string = 'westeurope'

@description('Name of the Azure Container Registry. Default: "adoagentsacr" + unique string')
param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'

@description('Name of the image to build. Default: "adoagent"')
param imageName string = 'adoagent'

@description('Version of the image to build. Default: "v1.0.0"')
param imageVersion string = 'v1.0.0'

@secure()
@description('GitHub personal access token with repo access. Default: ""')
param ghToken string = ''

@description('Github user or organization. Default: "antsok"')
@minLength(1)
param ghUser string = 'antsok'

@description('GitHub repository name. Default: "ado-aca"')
@minLength(1)
param ghRepo string = 'ado-aca'

@description('Branch to use for the source code. Default: "main"')
@minLength(1)
param ghBranch string = 'main'

@description('Path to agent\'s Dockerfile relative to the repository root. Default: "src/agent"')
param ghPath string = 'src/agent'

@description('Should agents image be rebuilt on schedule. Default: false')
param isImageRebuildTriggeredByTime bool = false

@description('Cron config of image rebuild. Default: "0 4 * * *"')
param cronSchedule string = '0 4 * * *'

@description('Should agents image be rebuilt when source files change. Default: false')
param isImageRebuildTriggeredBySource bool = false

@description('Should agents image be rebuilt when base image changes. Default: false')
param isImageRebuildTriggeredByBaseImage bool = false

@description('A parameter to force image update. Should not be used.')
param forceUpdateTag string = utcNow('yyyyMMddHHmmss')

@description('Name of the Log Analytics workspace for infrastructure logs.')
param laWorkspaceName string

@description('Whether to use a private network for the solution. Default: true')
param usePrivateNetwork bool = true

@description('Name of the virtual network. Default: "ado-agents-infra-vnet"')
param vnetName string = 'ado-agents-infra-vnet'

@allowed([0,1])
param subnetIndex int = 0

var dockerFilePath = 'Dockerfile'
var ghRepositoryContextUrl = 'https://github.com/${ghUser}/${ghRepo}.git#${ghBranch}:${ghPath}'
var fullImageName = '${imageName}:${imageVersion}'

resource laWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: laWorkspaceName
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: usePrivateNetwork ? 'Premium' : 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: usePrivateNetwork ? 'Disabled' : 'Enabled'
    networkRuleBypassOptions: usePrivateNetwork ? 'None' : 'AzureServices'
    networkRuleSet:{
      defaultAction: usePrivateNetwork ? 'Deny' : 'Allow'
    }
  }
}

resource acrDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'acrSendAllLogsToLogAnalytics'
  scope: acr
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

resource acrTask 'Microsoft.ContainerRegistry/registries/tasks@2019-06-01-preview' = {
  name: 'adoagent-build-task'
  parent: acr
  location: location
  properties: {
    status: 'Enabled'
    agentConfiguration: {
      cpu: 2
    }
    platform: {
      os: 'Linux'
      architecture: 'amd64'
    }
    step: {
      type: 'Docker'
      contextAccessToken: !empty(ghToken) ? ghToken : null
      contextPath: ghRepositoryContextUrl
      dockerFilePath: dockerFilePath
      imageNames:[
        fullImageName
      ]
      isPushEnabled: true
    }
    trigger: {
      timerTriggers: isImageRebuildTriggeredByTime ? [
        {
          name: 'adoagent-build-task-timer'
          schedule: cronSchedule
        }
      ] : null
      baseImageTrigger: isImageRebuildTriggeredByBaseImage ? {
        name: 'adoagent-build-task-base-image-trigger'
        baseImageTriggerType: 'All'
        status: 'Enabled'
      } : null
      sourceTriggers: isImageRebuildTriggeredBySource ? [
        {
          name: 'adoagent-build-task-source-trigger'
          sourceTriggerEvents: [
            'pullrequest'
            'commit'
          ]
          sourceRepository: {
            repositoryUrl: ghRepositoryContextUrl
            sourceControlType: 'Github'
            branch: ghBranch
            sourceControlAuthProperties: !empty(ghToken) ? {
              token:  ghToken
              tokenType: 'PAT'
            } : null
          }
        }
      ] : null
    }
  }
}

resource acrTaskRun 'Microsoft.ContainerRegistry/registries/taskRuns@2019-06-01-preview' = {
  name: 'adoagent-taskrun'
  parent: acr
  location: location
  properties: {
    forceUpdateTag: forceUpdateTag
    runRequest: {
      type: 'TaskRunRequest'
      taskId: acrTask.id
      isArchiveEnabled: false
    }
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = if (usePrivateNetwork) {
  name: vnetName
}

resource subnetPrivateEndpoints 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' = if (usePrivateNetwork) {
  parent: vnet
  name: 'endpoints-subnet'
  properties: {
    addressPrefix: cidrSubnet(vnet.properties.addressSpace.addressPrefixes[0], parseCidr(vnet.properties.addressSpace.addressPrefixes[0]).cidr+1, subnetIndex)
    privateEndpointNetworkPolicies: 'Disabled'
    privateLinkServiceNetworkPolicies: 'Enabled'
  }
}


resource acrPrivateEndpoint 'Microsoft.Network/privateEndpoints@2022-05-01' = if (usePrivateNetwork) {
  name: '${acrName}-pep'
  location: location
  properties: {
    privateLinkServiceConnections: [
      {
        name: '${acrName}-pep-conn'
        properties: {
          privateLinkServiceId: acr.id
          groupIds: [
            'registry'
          ]
        }
      }
    ]
    subnet: {
      id: subnetPrivateEndpoints.id
    }
  }
}

resource acrPrivateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' existing = if(usePrivateNetwork) {
  name: 'privatelink${environment().suffixes.acrLoginServer}'
}

resource acrPrivateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = if (usePrivateNetwork) {
  parent: acrPrivateEndpoint
  name: 'registryPrivateDnsZoneGroup'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'dnsConfig'
        properties: {
          privateDnsZoneId: acrPrivateDnsZone.id
        }
      }
    ]
  }
}

@description('Output the name of the ACR')
output name string = acr.name

@description('Output the login server property for later use')
output loginServer string = acr.properties.loginServer

@description('Output the name of the built image')
output imageName string = acrTask.properties.step.imageNames[0]

@description('Output the name of the task run')
output taskRunName string = acrTaskRun.name
