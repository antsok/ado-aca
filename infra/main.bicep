targetScope = 'subscription'

param location string = 'westeurope'

param rgName string = 'ado-aca-rg'

param ghBranch string = 'main'

@secure()
param azpUrl string
@secure()
param azpToken string
@secure()
param azpPool string

resource rg 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgName
  location: location
}


module acr 'acr.bicep' = {
  scope: rg
  name: 'acr'
  params: {
    location: location
    enableAutoscaling: true
    ghBranch: ghBranch
  }
}

module ace 'aca.bicep' = {
  scope: rg
  name: 'aca'
  params: {
    location: location
    azpPool: azpPool
    azpToken: azpToken
    azpUrl: azpUrl
    acrName: acr.outputs.acrName
  }
}
