# manage-locks.ps1
# Script to automate creation, listing, and deletion of Azure Resource Locks.

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "List", "Remove")]
    [string]$Action,

    [Parameter(Mandatory=$false)]
    [ValidateSet("ResourceLevel", "GroupLevel")]
    [string]$Level = "ResourceLevel",

    [Parameter(Mandatory=$false)]
    [string]$LockType = "CanNotDelete"
)

# Load configuration
$configPath = Join-Path $PSScriptRoot "infra-config.json"
if (-not (Test-Path $configPath)) {
    Write-Error "Infrastructure configuration file not found at $configPath. Please run deploy-infra.ps1 first."
    exit 1
}
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$rgName = $config.ResourceGroupName
$saName = $config.StorageAccountName
$nsgName = $config.NsgName
$vmName = $config.VmName

Write-Host "Action: $Action" -ForegroundColor Cyan
Write-Host "Resource Group: $rgName" -ForegroundColor Cyan

if ($Action -eq "Create") {
    if ($Level -eq "ResourceLevel") {
        Write-Host "Creating CanNotDelete lock on Storage Account: $saName..." -ForegroundColor Cyan
        $saLock = az lock create --name "lock-sa-delete" --lock-type CanNotDelete --resource-group $rgName --resource-name $saName --resource-type "Microsoft.Storage/storageAccounts" | ConvertFrom-Json
        
        Write-Host "Creating ReadOnly lock on Network Security Group: $nsgName..." -ForegroundColor Cyan
        $nsgLock = az lock create --name "lock-nsg-readonly" --lock-type ReadOnly --resource-group $rgName --resource-name $nsgName --resource-type "Microsoft.Network/networkSecurityGroups" | ConvertFrom-Json
        
        Write-Host "Locks successfully applied." -ForegroundColor Green
    } else {
        Write-Host "Creating $LockType lock at Resource Group level: $rgName..." -ForegroundColor Cyan
        $rgLock = az lock create --name "lock-rg-level" --lock-type $LockType --resource-group $rgName | ConvertFrom-Json
        Write-Host "Resource Group lock successfully applied." -ForegroundColor Green
    }
}
elseif ($Action -eq "List") {
    Write-Host "Listing locks in Resource Group $rgName..." -ForegroundColor Cyan
    az lock list --resource-group $rgName -o table
}
elseif ($Action -eq "Remove") {
    if ($Level -eq "ResourceLevel") {
        Write-Host "Removing resource-level locks..." -ForegroundColor Cyan
        $locks = az lock list --resource-group $rgName | ConvertFrom-Json
        $count = 0
        foreach ($lock in $locks) {
            if ($lock.name -eq "lock-sa-delete" -or $lock.name -eq "lock-nsg-readonly") {
                Write-Host "Deleting lock: $($lock.name) ($($lock.id))" -ForegroundColor Yellow
                az lock delete --ids $lock.id
                $count++
            }
        }
        Write-Host "Removed $count resource-level locks." -ForegroundColor Green
    } else {
        Write-Host "Removing group-level locks..." -ForegroundColor Cyan
        $locks = az lock list --resource-group $rgName | ConvertFrom-Json
        $count = 0
        foreach ($lock in $locks) {
            if ($lock.name -eq "lock-rg-level") {
                Write-Host "Deleting lock: $($lock.name) ($($lock.id))" -ForegroundColor Yellow
                az lock delete --ids $lock.id
                $count++
            }
        }
        Write-Host "Removed $count group-level locks." -ForegroundColor Green
    }
}
