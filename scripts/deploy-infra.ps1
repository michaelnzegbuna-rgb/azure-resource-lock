# deploy-infra.ps1
# Script to provision the infrastructure for Azure Resource Lock Learning Program

$subscriptionId = "9335a9cd-ae74-439b-94b3-d965ca478c53"
$rgName = "rg-locks-learning-prod"
$location = "westeurope"
$nsgName = "nsg-learning-prod"
$saName = "salearningprod" + (Get-Random -Minimum 100000 -Maximum 999999)
$vmName = "vm-learning-prod"

Write-Host "Setting subscription context to $subscriptionId..." -ForegroundColor Cyan
az account set --subscription $subscriptionId

Write-Host "Creating Resource Group: $rgName in $location..." -ForegroundColor Cyan
$rgResult = az group create --name $rgName --location $location | ConvertFrom-Json
if (-not $rgResult) {
    Write-Error "Failed to create Resource Group."
    exit 1
}

Write-Host "Creating Network Security Group: $nsgName..." -ForegroundColor Cyan
$nsgResult = az network nsg create --resource-group $rgName --name $nsgName --location $location | ConvertFrom-Json

Write-Host "Creating Storage Account: $saName..." -ForegroundColor Cyan
$saResult = az storage account create --name $saName --resource-group $rgName --location $location --sku Standard_LRS --kind StorageV2 | ConvertFrom-Json

Write-Host "Attempting to create Virtual Machine: $vmName (Standard_D2s_v5)..." -ForegroundColor Cyan
$vmDeployed = $false
try {
    # Run az vm create. Redirecting error stream or letting it throw to catch block.
    # Note: az CLI outputs errors to stderr, which PowerShell treats as exceptions or standard error strings depending on configuration.
    $vmOutput = az vm create --resource-group $rgName --name $vmName --image Ubuntu2204 --size Standard_D2s_v5 --admin-username azureuser --generate-ssh-keys --location $location 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Virtual Machine deployed successfully." -ForegroundColor Green
        $vmDeployed = $true
    } else {
        Write-Warning "Virtual Machine deployment failed with CLI exit code $LASTEXITCODE. Error details:"
        Write-Warning $vmOutput
    }
} catch {
    Write-Warning "Virtual Machine deployment threw a PowerShell exception. Error details:"
    Write-Warning $_.Exception.Message
}

# Output results to a file for subsequent scripts to read
$config = @{
    SubscriptionId = $subscriptionId
    ResourceGroupName = $rgName
    Location = $location
    StorageAccountName = $saName
    NsgName = $nsgName
    VmName = if ($vmDeployed) { $vmName } else { $null }
}

$configPath = Join-Path $PSScriptRoot "infra-config.json"
$config | ConvertTo-Json | Out-File $configPath -Force
Write-Host "Infrastructure config saved to $configPath" -ForegroundColor Green
