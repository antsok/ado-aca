targetScope = 'resourceGroup'

param location string = 'westeurope'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageVersion string = 'v1.0.0'
param imageName string = 'adoagent'

param containerAppEnvironmentName string = 'ado-agents-ace'
param containerAppName string = 'ado-agents-aca'

@description('If to enable autoscaled agents functionality. If not, a static number of agent will be running.')
param enableAutoscaling bool = true

// @description('When autoscaling is not enabled, this is the number of containers that will be running.')
// @minValue(1)
// param containerMinCount int = 1
@description('Number of containers to run. When autoscaling is enabled, this is the maximum number of executions that can be started per polling interval.')
@minValue(1)
param containerMaxCount int = 1

@secure()
param azpUrl string
@secure()
param azpToken string
@secure()
param azpPool string

param baseTime string = utcNow('u')


param multipleRevisions bool = false

param laWorkspaceName string = 'ado-agents-app-la'
param appInsightsName string = 'ado-agents-app-appin'


var fullImageName = '${imageName}:${imageVersion}'
var cronExpression = '${dateTimeAdd(baseTime, 'PT5M', 'mm HH')} * * *'


// Prepare
resource laWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: laWorkspaceName
  location: location
  identity:{
    type: 'SystemAssigned'
  }
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      immediatePurgeDataOn30Days: true
      searchVersion: 1
    }
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: laWorkspace.id
  }
}

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2023-05-02-preview' = {
  name: containerAppEnvironmentName
  location: location
  properties: {
    daprAIInstrumentationKey: appInsights.properties.InstrumentationKey
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: laWorkspace.properties.customerId
        sharedKey: laWorkspace.listKeys().primarySharedKey
      }
    }
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

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: acrName
}

resource containerApp 'Microsoft.App/containerApps@2023-05-02-preview' = if(!enableAutoscaling) {
  name: containerAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties:{
    environmentId: containerAppEnvironment.id
    configuration:{
      activeRevisionsMode: multipleRevisions ? 'multiple' : 'single'
      registries:[
        {
          server: acr.properties.loginServer
          username: acr.name
          passwordSecretRef: 'acr-password-ref'
        }
      ]
      secrets: [
        {
          name: 'acr-password-ref'
          value: acr.listCredentials().passwords[0].value
        }
        {
          name: 'azp-url'
          value: azpUrl
        }
        {
          name: 'azp-token'
          value: azpToken
        }
        {
          name: 'azp-pool'
          value: azpPool
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ado-agent'
          image: '${acr.properties.loginServer}/${fullImageName}'
          resources: {
            cpu: 1
            memory: '2Gi'
          }
          env: [
            {
              name: 'AZP_URL'
              secretRef: 'azp-url'
            }
            {
              name: 'AZP_TOKEN'
              secretRef: 'azp-token'
            }
            {
              name: 'AZP_POOL'
              secretRef: 'azp-pool'
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

resource containerJobInitial 'Microsoft.App/jobs@2023-05-02-preview' = if (enableAutoscaling) {
  name: '${containerAppName}-initial'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnvironment.id
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
          username: acr.name
          passwordSecretRef: 'acr-password-ref'
        }
      ]
      secrets: [
        {
          name: 'acr-password-ref'
          value: acr.listCredentials().passwords[0].value
        }
        {
          name: 'azp-url'
          value: azpUrl
        }
        {
          name: 'azp-token'
          value: azpToken
        }
        {
          name: 'azp-pool'
          value: azpPool
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ado-agent-placeholder'
          image: '${acrName}.azurecr.io/${fullImageName}'
          resources: {
            cpu: 2
            memory: '4Gi'
          }
          env: [
            {
              name: 'AZP_URL'
              secretRef: 'azp-url'
            }
            {
              name: 'AZP_TOKEN'
              secretRef: 'azp-token'
            }
            {
              name: 'AZP_POOL'
              secretRef: 'azp-pool'
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

resource containerJobScaling 'Microsoft.App/jobs@2023-05-02-preview' = if (enableAutoscaling) {
  name: '${containerAppName}-scaling'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnvironment.id
    configuration: {
      triggerType: 'Event'
      replicaTimeout: 1800
      replicaRetryLimit: 1
      eventTriggerConfig: {
        replicaCompletionCount: 1
        parallelism: 1
        scale: {
          minExecutions: 0
          maxExecutions: containerMaxCount
          pollingInterval: 30
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
          username: acr.name
          passwordSecretRef: 'acr-password-ref'
        }
      ]
      secrets: [
        {
          name: 'acr-password-ref'
          value: acr.listCredentials().passwords[0].value
        }
        {
          name: 'azp-url'
          value: azpUrl
        }
        {
          name: 'azp-token'
          value: azpToken
        }
        {
          name: 'azp-pool'
          value: azpPool
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ado-agent-scaling'
          image: '${acrName}.azurecr.io/${fullImageName}'
          resources: {
            cpu: 2
            memory: '4Gi'
          }
          env: [
            {
              name: 'AZP_URL'
              secretRef: 'azp-url'
            }
            {
              name: 'AZP_TOKEN'
              secretRef: 'azp-token'
            }
            {
              name: 'AZP_POOL'
              secretRef: 'azp-pool'
            }
          ]
        }
      ]
    }
  }
}
