# Hosting Azure DevOps agents in Container Apps

## What is it


## Minimum requirements
The solutions requires: Azure, and Azure DevOps. Optionally, you might want to use your own GitHub repo.
## Preparation

You need to make two preparations in your Azure DevOps to enable the build agents that this repo creates

- create PAT (Personal Access Token) as described here https://docs.microsoft.com/en-us/azure/devops/pipelines/agents/v2-linux?view=azure-devops#authenticate-with-a-personal-access-token-pat and **securely** note it down

- note down the URL to your ADO organization (e.g. 'https://dev.azure.com/organization/')

- create new Agent pool (under 'https://dev.azure.com/organization/_settings/agentpools') of 'Self-hosted' type, and note down its name.

If you want to use your own GitHub instead of the original repo (https://github.com/antsok/ado-aca.git), fork the 'ado-aca' repository to your GitHub repo, and make it available to be conected from your Azure environment.

## Initial Deployment

>The instructions below are for Azure CLI and bash shell, with repo root folder as the working folder.

First, initialize AZP_URL, AZP_POOL, and AZP_TOKEN environment variables with the information from the Preparation phase. For example,
```
AZP_URL='https://dev.azure.com/organization/'
AZP_POOL='ado-aca'
AZP_TOKEN='yourverysecretstring'
```

Next, set up subscription name to use with Azure deployments.
```
SUB_NAME='<subscription name>'
```

and initialize your Azure environment context
- login to Azure with, if not already 
- select your subscription 

```
az login
az account set -n $SUB_NAME
```

Now, if you are using the original GitHub repository, deploy the solution with the following command:

```
DEPLOYMENT_LOCATION='westeurope'
DEPLOYMENT_NAME='ado-aca'
GH_BRANCH='2-add-autoscaling'

az deployment sub create -n $DEPLOYMENT_NAME -l $DEPLOYMENT_LOCATION --template-file infra/main.bicep --parameters azpUrl=$AZP_URL azpPool=$AZP_POOL azpToken=$AZP_TOKEN ghBranch=$GH_BRANCH
```

Some parameters are needed if you are not using the original GitHub repo
```
tbd
```

After the solution is deployed into Azure, give it approx 10 minutes to make an initialization of your ADO Pool. Check status of agents in the ADO pool. There shold be 'ado-agent-placeholder' agent in Idle status and Enabled.

### Troubleshooting

Old text to rework:
```

- deploy ACR and build the image by running `ACR_URL=$(az deployment group create --resource-group $RG_NAME --template-file infra/acr.bicep --query "properties.outputs.acrLoginServer.value" -o tsv)` and waiting for it to finish
  - image build logs can be checked with `az acr taskrun logs --name adoagent-taskrun --resource-group $RG_NAME --registry $ACR_URL`
  - image can be checked with `az acr repository show --name $ACR_URL --repository adoagent` and `az acr repository show-tags --name $ACR_URL --repository adoagent`
- run `az deployment group create --resource-group $RG_NAME --template-file infra/aca.bicep --parameters azpUrl=https://dev.azure.com/<YourADOorganization> azpPool=<Agent-Pool-Name> azpToken=<PAT Token> containerCount=<number of agents>`
  - check if containers are provisioned with `az containerapp show -n ado-agents-ca -g $RG_NAME`
  - logs can be viewed with `az containerapp logs show -n ado-agents-ca -g $RG_NAME --follow true`
```





## Update

Updating the agents pool with new image version is done by running the solution deployment again.
