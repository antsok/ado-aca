targetScope = 'resourceGroup'

param location string = 'westeurope'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageVersion string = 'v1.0.0'
param imageName string = 'adoagent'

param laWorkspaceName string = 'ado-agents-la'
param appInsightsName string = 'ado-agents-appinsights'

param containerAppEnvironmentName string = 'ado-agents-ce'
param containerAppName string = 'ado-agents-ca'
@minValue(1)
param containerMinCount int = 1
param experimentalScaling bool = false
@minValue(1)
param containerMaxCount int = 1


@secure()
param azpUrl string
@secure()
param azpToken string
@secure()
param azpPool string

param multipleRevisions bool = false


var fullImageName = '${imageName}:${imageVersion}'

var minContainerCount = containerMinCount
var maxContainerCount = (containerMaxCount > 0 && experimentalScaling) ? containerMaxCount : containerMinCount

// Prepare
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

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2022-10-01' = {
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

resource acr 'Microsoft.ContainerRegistry/registries@2022-12-01' existing = {
  name: acrName
}

resource containerApp 'Microsoft.App/containerApps@2022-10-01' = if(!experimentalScaling) {
  name: containerAppName
  location: location
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
        minReplicas: minContainerCount
        maxReplicas: maxContainerCount
      }
    }
  }
}

// https://learn.microsoft.com/en-us/azure/container-apps/tutorial-ci-cd-runners-jobs?tabs=bash&pivots=container-apps-jobs-self-hosted-ci-cd-azure-pipelines

resource containerJobInitial 'Microsoft.App/jobs@2023-04-01-preview' = if (experimentalScaling) {
  name: '${containerAppName}-initial'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    environmentId: containerAppEnvironment.id
    configuration: {
      replicaTimeout: 300
      triggerType: 'Manual'
      replicaRetryLimit: 1
      manualTriggerConfig: {
        replicaCompletionCount: 1
        parallelism: 1
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

resource containerJobScaling 'Microsoft.App/jobs@2023-04-01-preview' = if (experimentalScaling) {
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
          maxExecutions: 10
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
