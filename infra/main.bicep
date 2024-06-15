targetScope = 'subscription'

// Azure deployment parameters
@description('The location of all resources. Default: deployment location')
param location string = deployment().location

@description('The name of the resource group')
param rgName string = 'adoaca-rg'

@description('Whether to use a private network for the solution. Default: true')
param usePrivateNetwork bool = true

@description('The address prefix for the virtual network. Default: 10.0.0.0/24')
param vnetAddressPrefix string = '10.0.0.0/24'

@description('In addition to AAD, should it also be possible to use local auth. Default: false')
param useLocalAuthenticationOptions bool = false

// Container Apps parameters
@description('Whether to enable autoscaling for the container apps. Default: true')
param enableAutoscaling bool = true

// ADO agent image parameters

@description('Name of the image to build. Default: "adoagent"')
param imageName string = 'adoagent'

@description('Version of the image to build. Default: "1.0.0"')
param imageVersion string = '1.0.0'

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
@description('Azure DevOps project URL')
@secure()
param azpUrl string

@description('Azure DevOps personal access token')
@secure()
param azpToken string

@description('Azure DevOps agent pool name')
@secure()
param azpPool string

// Create resource group
resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: location
}

module shared 'shared.bicep' = {
  scope: rg
  name: '${deployment().name}-shared'
  params: {
    location: location
    usePrivateNetwork: usePrivateNetwork
    vnetAddressPrefix: vnetAddressPrefix
    useLocalAuthenticationOptions: useLocalAuthenticationOptions
  }
}

// Deploy Azure Container Registry that builds the ADO agent image
module acr 'acr.bicep' = {
  scope: rg
  name: '${deployment().name}-acr'
  params: {
    location: location
    laWorkspaceName: shared.outputs.laWorkspaceName
    useLocalAuthenticationOptions: useLocalAuthenticationOptions
    usePrivateNetwork: usePrivateNetwork
    vnetName: shared.outputs.vnetName
    subnetName: shared.outputs.subnets.endpoints.name
    ghUser: ghUser
    ghRepo: ghRepo
    ghBranch: ghBranch
    ghToken: ghToken
    imageName: imageName
    imageVersion: imageVersion
  }
}

// Deploy Azure Container Jobs (or Apps) that run the ADO agent
module aca 'aca.bicep' = {
  scope: rg
  name: '${deployment().name}-aca'
  params: {
    location: location
    enableAutoscaling: enableAutoscaling
    laWorkspaceName: shared.outputs.laWorkspaceName
    useLocalAuthenticationOptions: useLocalAuthenticationOptions
    usePrivateNetwork: usePrivateNetwork
    vnetName: shared.outputs.vnetName
    subnetName: shared.outputs.subnets.containers.name
    azpUrl: azpUrl
    azpPool: azpPool
    azpToken: azpToken
    acrName: acr.outputs.name
    imageName: imageName
    imageVersion: imageVersion
  }
}
