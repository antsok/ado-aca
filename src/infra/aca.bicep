targetScope = 'resourceGroup'

param location string = 'westeurope'

param laWorkspaceName string = 'ado-agents-la'

param containerAppEnvironmentName string = 'ado-agents-ce'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageName string = 'adoagent:v1.0.0'

param containerAppName string = 'ado-agents-ca'
@minValue(1)
param minContainerCount int = 1
@minValue(1)
param maxContainerCount int = 5

@secure()
param azpUrl string
@secure()
param azpToken string
@secure()
param azpPool string
param azpPoolId string = ''

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
        {
          name: 'azp-poolid'
          value: azpPoolId
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'ado-agent'
          image: '${acrName}.azurecr.io/${imageName}'
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
            {
              name: 'AZP_POOLID'
              secretRef: 'azp-poolid'
            }
            {
              name: 'AZP_AGENT_NAME'
              value: 'ado-agent-aca'
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
