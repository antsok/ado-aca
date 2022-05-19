targetScope = 'resourceGroup'

param location string = 'westeurope'

param acrName string = 'adoagentsacr${uniqueString(resourceGroup().id)}'
param imageVersion string = 'v1.0.0'
param imageName string = 'adoagent'

@description('Cron config of daily image updates. Default: "0 4 * * *"')
param cronSchedule string = '0 4 * * *'

@secure()
param ghToken string = ''
param ghUser string = 'nlasok1'
param ghPath string = 'ado-aca.git#main:src/agent'

param isTriggeredByTime bool = false
param isTriggeredBySource bool = false
param isTriggeredByBaseImage bool = false

var fullImageName = '${imageName}:${imageVersion}'
var ghRepositoryUrl = 'https://github.com/${ghUser}/${ghPath}'

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
    }
    step: {
      type: 'Docker'
      contextAccessToken: !empty(ghToken) ? ghToken : null
      contextPath: ghRepositoryUrl
      dockerFilePath: 'Dockerfile'
      imageNames:[
        fullImageName
      ]
      isPushEnabled: true
    }
    trigger: {
      timerTriggers: isTriggeredByTime ? [
        {
          name: 'adoagent-build-task-timer'
          schedule: cronSchedule
        }
      ] : []
      baseImageTrigger: isTriggeredByBaseImage ? {
        name: 'adoagent-build-task-base-image-trigger'
        baseImageTriggerType: 'All'
        status: 'Enabled'
      } : null
      sourceTriggers: isTriggeredBySource ? [
        {
          name: 'adoagent-build-task-source-trigger'
          sourceTriggerEvents: [
            'pullrequest'
            'commit'
          ]
          sourceRepository: {
            repositoryUrl: ghRepositoryUrl
            sourceControlType: 'Github'
            branch: 'main'
            sourceControlAuthProperties: !empty(ghToken) ? {
              token:  ghToken
              tokenType: 'PAT'
            } : null
          }
        }
      ] : []
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
