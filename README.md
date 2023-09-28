# Hosting Azure DevOps agents in Container Apps

## Preparation

- create PAT token as described here https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops#authenticate-with-a-personal-access-token-pat and securely note it down

- create Agent Pool in your ADO project and note down its name

## Initial Deployment

- login to Azure `az login` in your shell (Azure shell is the easiest way)
- checkout this/forked repo (e.g. `git clone https://github.com/antsok/ado-aca.git`) and cd to ado-aca dir
- (if needed) change the subscription context with `az account set -n '<subscription name>'`
- set resource group name with `RG_NAME=<resource group name>`
- create resource group `az group create -l 'westeurope' -n $RG_NAME`
- deploy ACR and build the image by running `ACR_URL=$(az deployment group create --resource-group $RG_NAME --template-file infra/acr.bicep --query "properties.outputs.acrLoginServer.value" -o tsv)` and waiting for it to finish
  - image build logs can be checked with `az acr taskrun logs --name adoagent-taskrun --resource-group $RG_NAME --registry $ACR_URL`
  - image can be checked with `az acr repository show --name $ACR_URL --repository adoagent` and `az acr repository show-tags --name $ACR_URL --repository adoagent`
- run `az deployment group create --resource-group $RG_NAME --template-file infra/aca.bicep --parameters azpUrl=https://dev.azure.com/<YourADOorganization> azpPool=<Agent-Pool-Name> azpToken=<PAT Token> containerCount=<number of agents>`
  - check if containers are provisioned with `az containerapp show -n ado-agents-ca -g $RG_NAME`
  - logs can be viewed with `az containerapp logs show -n ado-agents-ca -g $RG_NAME --follow true`
- Check status of agents in a pool of your ADO project (`https://dev.azure.com/<YourADOorganization>/<YourADOproject>/_settings/agentqueues`)


TODO: describe experimental scaling
`az deployment sub create -n ado-aca -l westeurope --template-file infra/main.bicep --parameters azpUrl=<AZP_URL> azpPool=<AZP_POOL> azpToken=<AZP_TOKEN> ghBranch='2-add-autoscaling'`

## Update

An update of ADO agents image is done is two steps:

1. Updating the image in the ACR, which can be triggered with `az acr task run --name adoagent-build-task --registry $ACR_URL` OR by redeploying the ACR (see the command in the "Initial Deployment" section above).

2. Updating the agents pool with new image version is done by redeploying ACA (see command in the section above).
