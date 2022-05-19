targetScope = 'resourceGroup'

param location string = 'westeurope'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageVersion string = 'v1.0.0'
param imageName string = 'adoagent'

@secure()
param ghToken string = ''
param ghUser string = 'antsok'
param ghPath string = 'ado-aca.git#main:src/agent'

var fullImageName = '${imageName}:${imageVersion}'

resource acr 'Microsoft.ContainerRegistry/registries@2021-06-01-preview' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: true
  }
  identity: {
    type: 'SystemAssigned'
  }
}

resource acrTask 'Microsoft.ContainerRegistry/registries/tasks@2019-04-01' = {
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
    }
    step: {
      type: 'Docker'
      contextAccessToken: !empty(ghToken) ? ghToken : null
      contextPath: 'https://github.com/${ghUser}/${ghPath}'
      dockerFilePath: 'Dockerfile'
      imageNames:[
        fullImageName
      ]
      isPushEnabled: true
    }
  }
}

resource acrTaskRun 'Microsoft.ContainerRegistry/registries/taskRuns@2019-06-01-preview' = {
  name: 'adoagent-taskrun'
  parent: acr
  location: location
  properties: {
    forceUpdateTag: 'true'
    runRequest: {
      type: 'TaskRunRequest'
      taskId: acrTask.id
      isArchiveEnabled: false
    }
  }
}

@description('Output the login server property for later use')
output acrLoginServer string = acr.properties.loginServer

@description('Output the name of the built image')
output acrImageName string = acrTask.properties.step.imageNames[0]

@description('Output the name of the task run')
output acrTaskRunName string = acrTaskRun.name
