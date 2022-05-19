targetScope = 'resourceGroup'

param location string = 'westeurope'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageVersion string = 'v1.0.0'
param imageName string = 'adoagent'

param laWorkspaceName string = 'ado-agents-la'

param containerAppEnvironmentName string = 'ado-agents-ce'
param containerAppName string = 'ado-agents-ca'
@minValue(1)
param containerCount int = 1

@secure()
param azpUrl string
@secure()
param azpToken string
@secure()
param azpPool string

param multipleRevisions bool = false

param experimentalScaling bool = false
param experimentalScalingCount int = 0

var fullImageName = '${imageName}:${imageVersion}'

var minContainerCount = containerCount
var maxContainerCount = (experimentalScalingCount > 0 && experimentalScaling) ? experimentalScalingCount : containerCount

// Prepare
resource laWorkspace 'Microsoft.OperationalInsights/workspaces@2020-10-01' = {
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

resource containerAppEnvironment 'Microsoft.App/managedEnvironments@2022-01-01-preview' = {
  name: containerAppEnvironmentName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: laWorkspace.properties.customerId
        sharedKey: laWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' existing = {
  name: acrName
}

resource aca 'Microsoft.App/containerApps@2022-01-01-preview' = {
  name: containerAppName
  location: location
  properties:{
    managedEnvironmentId: containerAppEnvironment.id
    configuration:{
      activeRevisionsMode: multipleRevisions ? 'multiple' : 'single'
      registries:[
        {
          server: '${acrName}.azurecr.io'
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
          image: '${acrName}.azurecr.io/${fullImageName}'
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
        rules: !experimentalScaling ? [] : [
          {
            name: 'cpu-scaling-rule'
            custom: {
              type: 'cpu'
              metadata: {
                type: 'Utilization'
                value: '25'
              }
            }
          }
          {
            name: 'memory-scaling-rule'
            custom: {
              type: 'memory'
              metadata: {
                type: 'Utilization'
                value: '50'
              }
            }
          }
        ]
      }
    }
  }
}
