targetScope = 'subscription'

// Azure deployment parameters
@description('The location of all resources')
param location string = 'westeurope'

@description('The name of the resource group')
param rgName string = 'adoaca-rg'

@description('Name of the image to build. Default: "adoagent"')
param imageName string = 'adoagent'

@description('Version of the image to build. Default: "v1.0.0"')
param imageVersion string = 'v1.0.0'

// Dockerfile source repository parameters
@secure()
@description('GitHub personal access token with repo access. Default: ""')
param ghToken string = ''

@description('Github user or organization. Default: "antsok"')
@minLength(1)
param ghUser string = 'antsok'

@description('GitHub repository name. Default: "ado-aca"')
@minLength(1)
param ghRepo string = 'ado-aca'

@description('The name of the GitHub branch to use')
param ghBranch string = 'main'

// Azure DevOps parameters
@secure()
param azpUrl string
@secure()
param azpToken string
@secure()
param azpPool string

// Create resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: location
}

// Deploy Azure Container Registry that builds the ADO agent image
module acr 'acr.bicep' = {
  scope: rg
  name: '${deployment().name}-acr'
  params: {
    location: location
    ghUser: ghUser
    ghRepo: ghRepo
    ghBranch: ghBranch
    ghToken: ghToken
    imageName: imageName
    imageVersion: imageVersion
  }
}

// Deploy Azure Container Jobs (or Apps) that run the ADO agent
module ace 'aca.bicep' = {
  scope: rg
  name: '${deployment().name}-aca'
  params: {
    location: location
    enableAutoscaling: true
    azpUrl: azpUrl
    azpPool: azpPool
    azpToken: azpToken
    acrName: acr.outputs.acrName
    imageName: imageName
    imageVersion: imageVersion
  }
}
