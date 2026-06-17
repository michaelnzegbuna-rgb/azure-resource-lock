# provision-environment.ps1
# Provisions Azure infrastructure for the Resource Lock Learning Program

$targetSubscription = "9335a9cd-ae74-439b-94b3-d965ca478c53"
$resourceGroup      = "rg-locks-learning-prod"
$region             = "westeurope"
$networkSecGroup    = "nsg-learning-prod"
$storageAccount     = "salearningprod" + (Get-Random -Minimum 100000 -Maximum 999999)
$virtualMachine     = "vm-learning-prod"

function Stop-OnFailure {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

Write-Host "Switching to subscription $targetSubscription..." -ForegroundColor Cyan
az account set --subscription $targetSubscription
if ($LASTEXITCODE -ne 0) {
    Stop-OnFailure "Could not switch to the target subscription."
}

Write-Host "Provisioning resource group '$resourceGroup' in $region..." -ForegroundColor Cyan
$rgOutcome = az group create --name $resourceGroup --location $region | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $rgOutcome) {
    Stop-OnFailure "Resource group provisioning did not succeed."
}

Write-Host "Provisioning network security group '$networkSecGroup'..." -ForegroundColor Cyan
$nsgOutcome = az network nsg create --resource-group $resourceGroup --name $networkSecGroup --location $region | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $nsgOutcome) {
    Stop-OnFailure "Network security group provisioning did not succeed."
}

Write-Host "Provisioning storage account '$storageAccount'..." -ForegroundColor Cyan
$storageOutcome = az storage account create --name $storageAccount --resource-group $resourceGroup --location $region --sku Standard_LRS --kind StorageV2 | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or -not $storageOutcome) {
    Stop-OnFailure "Storage account provisioning did not succeed."
}

Write-Host "Attempting to provision virtual machine '$virtualMachine' (Standard_D2s_v5)..." -ForegroundColor Cyan
$vmProvisioned = $false
try {
    # Capture both stdout and stderr since the CLI may report failures on either stream.
    $vmLog = az vm create `
        --resource-group $resourceGroup `
        --name $virtualMachine `
        --image Ubuntu2204 `
        --size Standard_D2s_v5 `
        --admin-username azureuser `
        --generate-ssh-keys `
        --location $region 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "Virtual machine came online successfully." -ForegroundColor Green
        $vmProvisioned = $true
    } else {
        Write-Warning "VM creation returned a non-zero exit code ($LASTEXITCODE). Details below:"
        Write-Warning $vmLog
    }
} catch {
    Write-Warning "VM creation raised a PowerShell exception. Details below:"
    Write-Warning $_.Exception.Message
}

# Persist a summary so later scripts know what exists
$summary = @{
    SubscriptionId     = $targetSubscription
    ResourceGroupName  = $resourceGroup
    Location           = $region
    StorageAccountName = $storageAccount
    NsgName            = $networkSecGroup
    VmName             = if ($vmProvisioned) { $virtualMachine } else { $null }
}

$outputPath = Join-Path $PSScriptRoot "infra-config.json"
$summary | ConvertTo-Json | Out-File $outputPath -Force
Write-Host "Saved infrastructure summary to $outputPath" -ForegroundColor Green
