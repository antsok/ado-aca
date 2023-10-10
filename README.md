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
AZP_URL='https://dev.azure.com/<organization>'
AZP_POOL='<agent-pool-name>'
AZP_TOKEN='<yourverysecretstring>'
```
Note, the AZP_URL parameter value should not end with a forward slash '/'.

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
DEPLOYMENT_NAME='adoaca'
RG_NAME='ado-aca-rg'

az deployment sub create -n $DEPLOYMENT_NAME -l $DEPLOYMENT_LOCATION --template-file infra/main.bicep --parameters location=$DEPLOYMENT_LOCATION rgName=$RG_NAME azpUrl=$AZP_URL azpPool=$AZP_POOL azpToken=$AZP_TOKEN
```
Or
```
az stack sub create --dm None --delete-all --yes --name $DEPLOYMENT_NAME -l $DEPLOYMENT_LOCATION --template-file infra/main.bicep --parameters location=$DEPLOYMENT_LOCATION rgName=$RG_NAME azpUrl=$AZP_URL azpPool=$AZP_POOL azpToken=$AZP_TOKEN

```

Some parameters are needed if you are not using the original GitHub repo:

```
GITHUB_USER='antsok'
GITHUB_REPO='ado-aca'
GITHUB_BRANCH='2-add-autoscaling'
GITHUB_TOKEN=''

az deployment sub create -n $DEPLOYMENT_NAME -l $DEPLOYMENT_LOCATION --template-file infra/main.bicep --parameters location=$DEPLOYMENT_LOCATION rgName=$RG_NAME azpUrl=$AZP_URL azpPool=$AZP_POOL azpToken=$AZP_TOKEN ghUser=$GITHUB_USER ghRepo=$GITHUB_REPO ghBranch=$GITHUB_BRANCH ghToken=$GITHUB_TOKEN

```

Other available parameters for further customizations are: imageName, imageVersion.

After the solution is deployed into Azure, give it approx 10 minutes to make an initialization of your ADO Pool. Check status of agents in the ADO pool. There shold be 'ado-agent-placeholder' agent in Idle status and Enabled.

### Troubleshooting

- image build logs can be checked with `az acr taskrun logs --name adoagent-taskrun --resource-group $RG_NAME --registry <Registry URL>`
- image can be checked with `az acr repository show --name <Registry URL> --repository adoagent` and `az acr repository show-tags --name <Registry URL> --repository adoagent`

## Update

Updating the agents pool with new image version is done by running the solution deployment and providing the new image version in 'imageVersion' parameter.
