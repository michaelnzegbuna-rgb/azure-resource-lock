# lock-controller.ps1
# Handles creating, listing, and removing Azure Resource Locks for the learning environment.

param (
    [Parameter(Mandatory=$true)]
    [ValidateSet("Create", "List", "Remove")]
    [string]$Operation,
    [Parameter(Mandatory=$false)]
    [ValidateSet("ResourceLevel", "GroupLevel")]
    [string]$Scope = "ResourceLevel",
    [Parameter(Mandatory=$false)]
    [string]$LockKind = "CanNotDelete"
)

# Pull in the infrastructure details produced by the provisioning script
$settingsPath = Join-Path $PSScriptRoot "infra-config.json"
if (-not (Test-Path $settingsPath)) {
    Write-Error "Could not find $settingsPath. Run provision-environment.ps1 before this script."
    exit 1
}

$settings        = Get-Content $settingsPath -Raw | ConvertFrom-Json
$resourceGroup   = $settings.ResourceGroupName
$storageAccount  = $settings.StorageAccountName
$networkSecGroup = $settings.NsgName
$virtualMachine  = $settings.VmName

Write-Host "Operation: $Operation" -ForegroundColor Cyan
Write-Host "Target Resource Group: $resourceGroup" -ForegroundColor Cyan

switch ($Operation) {

    "Create" {
        if ($Scope -eq "ResourceLevel") {
            Write-Host "Applying CanNotDelete lock to storage account '$storageAccount'..." -ForegroundColor Cyan
            $storageLockResult = az lock create `
                --name "lock-sa-delete" `
                --lock-type CanNotDelete `
                --resource-group $resourceGroup `
                --resource-name $storageAccount `
                --resource-type "Microsoft.Storage/storageAccounts" | ConvertFrom-Json

            Write-Host "Applying ReadOnly lock to network security group '$networkSecGroup'..." -ForegroundColor Cyan
            $nsgLockResult = az lock create `
                --name "lock-nsg-readonly" `
                --lock-type ReadOnly `
                --resource-group $resourceGroup `
                --resource-name $networkSecGroup `
                --resource-type "Microsoft.Network/networkSecurityGroups" | ConvertFrom-Json

            Write-Host "Resource-level locks applied." -ForegroundColor Green
        }
        else {
            Write-Host "Applying $LockKind lock at the resource group level ('$resourceGroup')..." -ForegroundColor Cyan
            $groupLockResult = az lock create `
                --name "lock-rg-level" `
                --lock-type $LockKind `
                --resource-group $resourceGroup | ConvertFrom-Json

            Write-Host "Group-level lock applied." -ForegroundColor Green
        }
    }

    "List" {
        Write-Host "Fetching locks for resource group '$resourceGroup'..." -ForegroundColor Cyan
        az lock list --resource-group $resourceGroup -o table
    }

    "Remove" {
        $existingLocks = az lock list --resource-group $resourceGroup | ConvertFrom-Json
        $removedCount  = 0

        if ($Scope -eq "ResourceLevel") {
            Write-Host "Removing resource-level locks..." -ForegroundColor Cyan
            $namesToRemove = @("lock-sa-delete", "lock-nsg-readonly")
        }
        else {
            Write-Host "Removing group-level locks..." -ForegroundColor Cyan
            $namesToRemove = @("lock-rg-level")
        }

        foreach ($lockItem in $existingLocks) {
            if ($namesToRemove -contains $lockItem.name) {
                Write-Host "Deleting lock '$($lockItem.name)' ($($lockItem.id))" -ForegroundColor Yellow
                az lock delete --ids $lockItem.id
                $removedCount++
            }
        }

        $scopeLabel = if ($Scope -eq "ResourceLevel") { "resource-level" } else { "group-level" }
        Write-Host "Removed $removedCount $scopeLabel lock(s)." -ForegroundColor Green
    }
}
