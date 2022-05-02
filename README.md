# ado-aca

Azure DevOps agents in Container Apps

- login to Azure `az login`
- if needed change subscription `az account set -n '<subscription name>'`
- create resource group `az group create -l 'westeurope' -n 'ado-agents-rg'`
- run `az deployment group create --resource-group 'ado-agents-rg' --template-file src/infra/acr.bicep`