targetScope = 'resourceGroup'

param location string = 'westeurope'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageVersion string = 'v1.0.0'
param imageName string = 'adoagent'

param containerAppEnvironmentName string = 'adoagents-ace-${uniqueString(resourceGroup().id)}'
param containerAppName string = 'adoagents-aca'

@description('If to enable autoscaled agents functionality. If not, a static number of agent will be running. Default: true')
param enableAutoscaling bool = true

@description('In addition to AAD, should it also be possible to use local auth. Default: false')
param useLocalAuthenticationOptions bool = false

// @description('When autoscaling is not enabled, this is the number of containers that will be running.')
// @minValue(1)
// param containerMinCount int = 1
@description('Number of containers to run. When autoscaling is enabled, this is the maximum number of executions that can be started per polling interval. Default: 1')
@minValue(1)
param containerMaxCount int = 1

@secure()
param azpUrl string
@secure()
param azpToken string
@secure()
param azpPool string

param baseTime string = utcNow('u')
param delayInterval string = 'PT10M'

@description('Whether to use a private network for the solution. Default: true')
param usePrivateNetwork bool = true

@description('Name of the virtual network. Default: "ado-agents-infra-vnet"')
param vnetName string = 'ado-agents-infra-vnet'

@description('Name of the subnet for private endpoints. Default: "endpoints-subnet"')
param subnetName string = 'containers-subnet'


param laWorkspaceName string = 'adoagents-app-la-${uniqueString(resourceGroup().id)}'
param appInsightsName string = 'adoagents-app-appin-${uniqueString(resourceGroup().id)}'


var fullImageName = '${imageName}:${imageVersion}'
var cronExpression = '${dateTimeAdd(baseTime, delayInterval, 'mm HH dd MM')} *'


// Prepare
resource laWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: laWorkspaceName
}

resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' existing = if (usePrivateNetwork) {
  name: vnetName
}

resource subnetContainers 'Microsoft.Network/virtualNetworks/subnets@2023-05-01' existing = if (usePrivateNetwork) {
  parent: vnet
  name: subnetName
}

// App Insights
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: laWorkspace.id
    DisableLocalAuth: !useLocalAuthenticationOptions
    //publicNetworkAccessForIngestion: usePrivateNetwork ? 'Disabled' : 'Enabled'
    //publicNetworkAccessForQuery: usePrivateNetwork ? 'Disabled' : 'Enabled'
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-11-02-preview' = {
  name: containerAppEnvironmentName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    daprAIInstrumentationKey: appInsights.properties.InstrumentationKey  // this needs local auth
    appLogsConfiguration: {
      destination: 'log-analytics' // this needs local auth
      logAnalyticsConfiguration: {
        customerId: laWorkspace.properties.customerId
        sharedKey: laWorkspace.listKeys().primarySharedKey
      }
    }
    workloadProfiles: usePrivateNetwork ? [
      {
        name: 'Consumption'
        workloadProfileType: 'Consumption'
      }
    ] : null
    vnetConfiguration: usePrivateNetwork ? {
      infrastructureSubnetId: subnetContainers.id
      internal: true
    } : null
    zoneRedundant: false
  }
}

resource aceDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'acrSendAllLogsToLogAnalytics'
  scope: containerAppEnvironment
  properties: {
    workspaceId: laWorkspace.id
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      {
        enabled: true
        categoryGroup: 'allLogs'
      }
    ]
  }
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'acr-uami-${uniqueString(resourceGroup().id)}'
  location: location
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

// @description('This is the built-in AcrPull role. See https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles#acrpull')
// resource acrPullRoleDefinition 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
//   scope: subscription()
//   name: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
// }

resource rbacAcrContainers 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, uami.id, '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  scope: acr
  properties: {
    principalId: uami.properties.principalId
    principalType: 'ServicePrincipal'
    description: 'Allow ACR to pull images from ACR'
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
  }
}

resource containerApp 'Microsoft.App/containerApps@2023-11-02-preview' = if(!enableAutoscaling) {
  name: take('${containerAppName}-${uniqueString(resourceGroup().id)}',32)
  location: location
  identity: {
    type:  'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties:{
    environmentId: containerAppEnvironment.id
    workloadProfileName: usePrivateNetwork ? 'Consumption' : null
    configuration:{
      activeRevisionsMode: 'single'
      registries:[
        {
          server: acr.properties.loginServer
          identity: uami.id
        }
      ]
      secrets: [
        {
          name: 'azp-token'
          value: azpToken
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ado-agent'
          image: '${acr.properties.loginServer}/${fullImageName}'
          resources: {
            cpu: 2
            memory: '4Gi'
          }
          env: [
            {
              name: 'AZP_URL'
              value: azpUrl
            }
            {
              name: 'AZP_TOKEN'
              secretRef: 'azp-token'
            }
            {
              name: 'AZP_POOL'
              value: azpPool
            }
          ]
        }
      ]
      scale: {
        minReplicas: containerMaxCount
        maxReplicas: containerMaxCount
      }
    }
  }
}

// https://learn.microsoft.com/en-us/azure/container-apps/tutorial-ci-cd-runners-jobs?tabs=bash&pivots=container-apps-jobs-self-hosted-ci-cd-azure-pipelines

resource containerJobInitial 'Microsoft.App/jobs@2023-11-02-preview' = if (enableAutoscaling) {
  name: take('${containerAppName}-init-${uniqueString(resourceGroup().id)}',32)
  location: location
  identity: {
    type:  'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    environmentId: containerAppEnvironment.id
    workloadProfileName: usePrivateNetwork ? 'Consumption' : null
    configuration: {
      replicaTimeout: 300
      triggerType: 'Schedule' //'Manual'
      replicaRetryLimit: 1
      scheduleTriggerConfig: {
        cronExpression: cronExpression
        replicaCompletionCount: 1
        parallelism: 1
      }
      // manualTriggerConfig: {
      //   replicaCompletionCount: 1
      //   parallelism: 1
      // }
      registries: [
        {
          server: acr.properties.loginServer
          identity: uami.id
        }
      ]
      secrets: [
        {
          name: 'azp-token'
          value: azpToken
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ado-agent-placeholder'
          image: '${acr.properties.loginServer}/${fullImageName}'
          resources: {
            cpu: 2
            memory: '4Gi'
          }
          env: [
            {
              name: 'AZP_URL'
              value: azpUrl
            }
            {
              name: 'AZP_TOKEN'
              secretRef: 'azp-token'
            }
            {
              name: 'AZP_POOL'
              value: azpPool
            }
            {
              name: 'AZP_PLACEHOLDER'
              value: '1'
            }
            {
              name: 'AZP_AGENT_NAME'
              value: 'ado-agent-placeholder'
            }
          ]
        }
      ]
    }
  }
}

resource containerJobScaling 'Microsoft.App/jobs@2023-11-02-preview' = if (enableAutoscaling) {
  name: take('${containerAppName}-scale-${uniqueString(resourceGroup().id)}',32)
  location: location
  identity: {
    type:  'SystemAssigned,UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    environmentId: containerAppEnvironment.id
    workloadProfileName: usePrivateNetwork ? 'Consumption' : null
    configuration: {
      triggerType: 'Event'
      replicaTimeout: 1800
      replicaRetryLimit: 1
      secrets: [
        {
          name: 'azp-url'
          value: azpUrl
        }
        {
          name: 'azp-token'
          value: azpToken
        }
      ]
      eventTriggerConfig: {
        replicaCompletionCount: 1
        parallelism: 1
        scale: {
          minExecutions: 0
          maxExecutions: containerMaxCount
          pollingInterval: 15
          rules: [
            {
              name: 'azure-pipelines'
              type: 'azure-pipelines'
              auth: [
                {
                  triggerParameter: 'personalAccessToken'
                  secretRef: 'azp-token'
                }
                {
                  triggerParameter: 'organizationURL'
                  secretRef: 'azp-url'
                }
              ]
              metadata: {
                poolName: azpPool
                //targetPipelinesQueueLength: '1'
              }
            }
          ]
        }
      }
      registries: [
        {
          server: acr.properties.loginServer
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ado-agent-scaling'
          image: '${acr.properties.loginServer}/${fullImageName}'
          args: [
            '--once'
          ]
          resources: {
            cpu: 2
            memory: '4Gi'
          }
          env: [
            {
              name: 'AZP_URL'
              value: azpUrl
            }
            {
              name: 'AZP_TOKEN'
              secretRef: 'azp-token'
            }
            {
              name: 'AZP_POOL'
              value: azpPool
            }
          ]
        }
      ]
    }
  }
}
