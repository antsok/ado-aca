# ado-aca

Azure DevOps agents in Container Apps

Preparation:

- create PAT token as described here https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops#authenticate-with-a-personal-access-token-pat

- create Agent Pool in your ADO project

Deployment:

- login to Azure `az login`
- if needed change subscription `az account set -n '<subscription name>'`
- create resource group `az group create -l 'westeurope' -n 'ado-agents-rg'`
- run `az deployment group create --resource-group 'ado-agents-rg' --template-file src/infra/acr.bicep`
- run `az deployment group create --resource-group 'ado-agents-rg' --template-file src/infra/aca.bicep --parameters azpUrl=https://dev.azure.com/<YourADOproject> azpPool=<Agent-Pool-Name> azpToken=<PAT Token> containerCount=<number of agents>`
