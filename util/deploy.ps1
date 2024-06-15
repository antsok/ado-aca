#!/usr/bin/env pwsh

# check if AZP_URL, AZP_POOL and AZP_TOKEN are set
if (-not $env:AZP_URL -or -not $env:AZP_POOL -or -not $env:AZP_TOKEN) {
    Write-Error "AZP_URL, AZP_POOL and AZP_TOKEN environment variables must be set"
    exit 1
}

$DEPLOYMENT_LOCATION='westeurope'
$DEPLOYMENT_NAME='adoaca'
$RG_NAME='ado-aca-rg'

az stack sub create --action-on-unmanage deleteAll --deny-settings-mode None --yes --name $DEPLOYMENT_NAME --location $DEPLOYMENT_LOCATION --template-file infra/main.bicep --parameters location=$DEPLOYMENT_LOCATION rgName=$RG_NAME azpUrl=$env:AZP_URL azpPool=$env:AZP_POOL azpToken=$env:AZP_TOKEN

