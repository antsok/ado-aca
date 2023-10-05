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

@description('Name of the Log Analytics workspace. Default: "ado-agents-la"')
param laWorkspaceName string = 'ado-agents-infra-la-${uniqueString(resourceGroup().id)}'



var dockerFilePath = 'Dockerfile'
var ghRepositoryContextUrl = 'https://github.com/${ghUser}/${ghRepo}.git#${ghBranch}:${ghPath}'
var fullImageName = '${imageName}:${imageVersion}'


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

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
  identity: {
    type: 'SystemAssigned'
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

@description('Output the name of the ACR')
output acrName string = acr.name

@description('Output the login server property for later use')
output acrLoginServer string = acr.properties.loginServer

@description('Output the name of the built image')
output acrImageName string = acrTask.properties.step.imageNames[0]

@description('Output the name of the task run')
output acrTaskRunName string = acrTaskRun.name
