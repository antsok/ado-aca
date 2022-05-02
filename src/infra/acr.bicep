targetScope = 'resourceGroup'

param location string = 'westeurope'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageName string = 'adoagent:v1.0.0'

@secure()
param ghToken string = ''
param ghUser string = 'antsok'
param ghPath string = 'ado-aca.git#main:src/agent'


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
  name: 'adoagent-task'
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
        imageName
      ]
      isPushEnabled: true
    }
  }
}

resource acrTaskRun 'Microsoft.ContainerRegistry/registries/taskRuns@2019-06-01-preview' = {
  name: 'adoagent-taskrun${uniqueString(resourceGroup().id)}'
  parent: acr
  location: location
  properties: {
    runRequest: {
      type: 'TaskRunRequest'
      taskId: acrTask.id
    }
  }
}

@description('Output the login server property for later use')
output acrLoginServer string = acr.properties.loginServer
