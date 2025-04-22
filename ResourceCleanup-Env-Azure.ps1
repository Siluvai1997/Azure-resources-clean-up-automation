<#
Cleans up all resource locks, tags and resource groups in Azure subscriptions whose names contain a given environment keyword.
A string to match against subscription names (e.g. "Test" to target all "*Test*" subscriptions).
#>

Write-Output "Running PowerShell Script..."
# Get the Environment name
$EnvironmentName = $env:Environment

param(
    [string]$EnvironmentName
)

# Ensure Az module is loaded
if (-not (Get-Module -ListAvailable -Name Az)) {
    Write-OutPut "Az module not found. Please install Az.Accounts and related modules."
    exit 1
}

# Get all subscriptions matching the keyword
$subs = Get-AzSubscription | Where-Object { $_.Name -like "*$EnvironmentName*" }
if (-not $subs) {
    Write-Output "No subscriptions found matching '*$EnvironmentName*'."
    exit 0
}

foreach ($sub in $subs) {
    Write-Output "Processing subscription: $($sub.Name) ($($sub.Id))"
    Set-AzContext -SubscriptionId $sub.Id

    #Remove any subscription‑level locks
    $subLocks = Get-AzResourceLock -Scope "/subscriptions/$($sub.Id)" -ErrorAction SilentlyContinue
    foreach ($lock in $subLocks) {
        Write-Output "  – Removing subscription lock: $($lock.Name)"
        Remove-AzResourceLock -LockId $lock.LockId -Force
    }

    #Remove subscription‑level tags (if any)
    try {
        $subDetails = Get-AzSubscription -SubscriptionId $sub.Id -ErrorAction Stop
        if ($subDetails.Tags) {
            Write-Output "  – Removing subscription tags: $($subDetails.Tags.Keys -join ', ')"
            Remove-AzTag -ResourceId "/subscriptions/$($sub.Id)" -TagName $subDetails.Tags.Keys -Force
        }
    } catch {
        Write-Verbose "Unable to retrieve tags for subscription."
    }

    #Iterate all resource groups
    $rgs = Get-AzResourceGroup
    foreach ($rg in $rgs) {
        Write-Output "  → Cleaning resource group: $($rg.ResourceGroupName)"

        #Remove any locks on the RG
        $rgLocks = Get-AzResourceLock -ResourceGroupName $rg.ResourceGroupName -ErrorAction SilentlyContinue
        foreach ($lock in $rgLocks) {
            Write-Output "      • Removing RG lock: $($lock.Name)"
            Remove-AzResourceLock -LockId $lock.LockId -Force
        }

        #Remove any tags on the RG
        if ($rg.Tags) {
            Write-Output "Removing RG tags: $($rg.Tags.Keys -join ', ')"
            Remove-AzTag -ResourceId $rg.ResourceId -TagName $rg.Tags.Keys -Force
        }

        #Delete the resource group (and all its resources)
        Write-Output "Deleting RG and contained resources..."
        Remove-AzResourceGroup -Name $rg.ResourceGroupName -Force -ErrorAction Stop
    }
}

Write-Output "Cleanup complete...."
Write-Output "End of PowerShell script...."
