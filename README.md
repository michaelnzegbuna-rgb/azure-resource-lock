# Locking Down Azure Resources: A Governance and Security Walkthrough

This repository pulls together the write-up, deployment scripts, and configuration files from the **Azure Resource Locks** learning exercise. The work puts safety nets in place at both the individual-resource and resource-group level, with the goal of strengthening cloud governance, preventing accidental deletions, and hardening configurations against unwanted changes.

---

## 1. What This Project Sets Out to Do

The aim here is to verify, hands-on, how Azure's two resource lock types — `CanNotDelete` and `ReadOnly` — actually behave across different layers of the resource hierarchy, to see how those locks interact with Azure's Role-Based Access Control (RBAC) system, and to look at how lock deployment can be automated rather than done by hand.

### What Got Deployed
The following were spun up in the **West Europe** region, under the subscription `Azure subscription 1` (ID: `9335a9cd-ae74-439b-94b3-d965ca478c53`):
* **Resource Group**: `rg-locks-learning-prod`
* **Storage Account**: `salearningprod899756` (Standard LRS, StorageV2)
* **Network Security Group**: `nsg-learning-prod`
* **Virtual Machine**: `vm-learning-prod` (Ubuntu 22.04 LTS, Size: `Standard_D2s_v5`)

---

## 2. CanNotDelete vs. ReadOnly, Side by Side

The table captures the practical differences between the two lock types, based on what was actually observed during CLI testing.

| Lock Type | Can Read Resource? | Can Modify Resource? | Can Delete Resource? | Control Plane POST Actions? (e.g., Start/Stop VM) |
| :--- | :---: | :---: | :---: | :---: |
| **CanNotDelete** (Delete) | Yes | **Yes** | **No** | Yes |
| **ReadOnly** | Yes | **No** | **No** | **No** |

---

## 3. Test Results: What the CLI Actually Returned

Every test below was run via the Azure CLI (`az`) while signed in as the **Subscription Owner** — the highest administrative role available. What follows are the genuine outputs captured during each run.

### Test 1: CanNotDelete on the Storage Account
* **Can it still be modified?** Tags were updated on `salearningprod899756`:
  ```powershell
  az storage account update --name salearningprod899756 --resource-group rg-locks-learning-prod --tags Project=AzureLocks
  ```
  **Outcome**: **Worked fine.** The tags updated without any pushback, which confirms `CanNotDelete` doesn't interfere with writes or updates.

* **Can it be deleted?** A deletion was attempted:
  ```powershell
  az storage account delete --name salearningprod899756 --resource-group rg-locks-learning-prod --yes
  ```
  **Outcome**: **Rejected.** Azure responded with:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod/providers/Microsoft.Storage/storageAccounts/salearningprod899756' cannot perform delete operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourcegroups/rg-locks-learning-prod/providers/Microsoft.Storage/storageAccounts/salearningprod899756'. Please remove the lock and try again.
  ```

---

### Test 2: ReadOnly on the Network Security Group
* **Can it still be modified?** An attempt was made to add a new rule (`AllowHTTP`) to `nsg-learning-prod`:
  ```powershell
  az network nsg rule create --resource-group rg-locks-learning-prod --nsg-name nsg-learning-prod --name AllowHTTP --priority 100 --destination-port-ranges 80 --direction Inbound --access Allow --protocol Tcp
  ```
  **Outcome**: **Rejected.** A `ScopeLocked` write failure came back:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-learning-prod/securityRules/AllowHTTP' cannot perform write operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourcegroups/rg-locks-learning-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-learning-prod'. Please remove the lock and try again.
  ```

* **Can it be deleted?** A deletion of the NSG itself was attempted:
  ```powershell
  az network nsg delete --resource-group rg-locks-learning-prod --name nsg-learning-prod
  ```
  **Outcome**: **Rejected.** Azure's response:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-learning-prod' cannot perform delete operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourcegroups/rg-locks-learning-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-learning-prod'. Please remove the lock and try again.
  ```

---

### Test 3: Does a Parent Lock Trickle Down to Its Children?
The resource-specific locks were lifted, and instead a `CanNotDelete` lock was placed on the parent Resource Group (`rg-locks-learning-prod`) itself.
* **The test**: The Storage Account `salearningprod899756` — which by this point had no lock of its own — was targeted for deletion:
  ```powershell
  az storage account delete --name salearningprod899756 --resource-group rg-locks-learning-prod --yes
  ```
  **Outcome**: **Rejected.** The failure pointed straight at the parent group's lock as the source:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod/providers/Microsoft.Storage/storageAccounts/salearningprod899756' cannot perform delete operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod'. Please remove the lock and try again.
  ```
  **Takeaway**: A lock at the resource group level flows downward automatically — every resource inside inherits that protection, whether or not it has its own lock.

---

### Test 4: Does Locking a Resource Also Protect the Group It's In?
* **The test**: An attempt was made to wipe out the whole Resource Group `rg-locks-learning-prod`, which still had locked resources sitting inside it:
  ```powershell
  az group delete --name rg-locks-learning-prod --yes
  ```
  **Outcome**: **Rejected.** Azure won't let a group be deleted while it, or anything inside it, is locked:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourcegroups/rg-locks-learning-prod' cannot perform delete operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod'. Please remove the lock and try again.
  ```
  **Takeaway**: This is exactly the kind of safety net that stops a whole environment from being wiped out in one careless command.

---

### Test 5: Do Locks Beat Even the Highest Permission Level?
All of these tests were carried out under full Subscription Owner rights — the top of the RBAC ladder. The fact that every single write or delete attempt still got blocked makes the point on its own: **resource locks override RBAC roles, Owner included.**
* Even an Owner has to go remove the lock first before any of these actions can go through. It's effectively a built-in "confirm twice" step that cuts down on costly accidents.

---

## 4. The VM Won't Start? Here's Why a ReadOnly Lock Stops It

A frequent point of confusion: why does a `ReadOnly` lock stop something as ordinary as starting or stopping a VM? The answer comes down to the split between Azure's **Management Plane (Control Plane)** and its **Data Plane**.

1. **It's a Management Plane Operation**:
   Both starting and stopping a VM go through Azure Resource Manager (ARM) as management-plane actions.
   * **Powering on** means ARM has to reserve physical hypervisor capacity and rewrite the VM's metadata (flipping `powerState` to `VM running`, for example).
   * **Powering off / deallocating** frees that hypervisor capacity back up, rewrites the metadata again (`powerState` becomes `VM deallocated`), and can touch dynamic network pieces too, like a dynamically assigned public IP.
2. **It Comes Down to the HTTP Method**:
   * A `ReadOnly` lock shuts off every write or configuration call against the ARM control plane — concretely, that's `PUT`, `DELETE`, and `POST` requests, all blocked.
   * Power state changes happen via POST calls to endpoints like:
     * Start: `POST https://management.azure.com/.../virtualMachines/vm-learning-prod/start?api-version=...`
     * PowerOff/Deallocate: `POST https://management.azure.com/.../virtualMachines/vm-learning-prod/deallocate?api-version=...`
   * Because those POST calls change the resource's state and shift what it costs to run, ARM won't execute them under a `ReadOnly` lock.
3. **Where the Lock Doesn't Reach**:
   `ReadOnly` has zero effect on data-plane activity. If the VM's already up and running, people can still load a website hosted on it or SSH into the box directly, since that traffic skips ARM entirely and talks straight to the operating system.

---

## 5. Scaling It Up: Letting Azure Policy Apply Locks Automatically

For organizations that want a "locked by default" posture across many resources, **Azure Policy** can apply locks automatically based on tags — say, locking anything tagged `Environment: Production` without anyone having to remember to do it manually.

The policy definition below uses the `deployIfNotExists` effect to automatically attach a `CanNotDelete` lock to any resource carrying the tag `LockStatus: CanNotDelete`.

```json
{
  "properties": {
    "displayName": "Deploy CanNotDelete Resource Lock based on Tag",
    "policyType": "Custom",
    "mode": "Indexed",
    "description": "Deploys a CanNotDelete lock on resources tagged with 'LockStatus: CanNotDelete'.",
    "metadata": {
      "category": "Authorization"
    },
    "parameters": {},
    "policyRule": {
      "if": {
        "allOf": [
          {
            "field": "tags['LockStatus']",
            "equals": "CanNotDelete"
          }
        ]
      },
      "then": {
        "effect": "deployIfNotExists",
        "details": {
          "type": "Microsoft.Authorization/locks",
          "roleDefinitionIds": [
            "/providers/Microsoft.Authorization/roleDefinitions/18d7d88d-d35e-4fb5-a5c3-7773c20a72d9" 
          ],
          "existenceCondition": {
            "field": "Microsoft.Authorization/locks/level",
            "equals": "CanNotDelete"
          },
          "deployment": {
            "properties": {
              "mode": "incremental",
              "template": {
                "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
                "contentVersion": "1.0.0.0",
                "resources": [
                  {
                    "type": "Microsoft.Authorization/locks",
                    "apiVersion": "2016-09-01",
                    "name": "[concat(parameters('resourceName'), '-lock')]",
                    "properties": {
                      "level": "CanNotDelete",
                      "notes": "Automated lock applied by Azure Policy based on LockStatus tag."
                    }
                  }
                ]
              }
            }
          }
        }
      }
    }
  }
}
```

---

## 6. Where to Find the Scripts

Everything script-related lives under the [scripts](scripts) folder:
* **Spinning Up the Infrastructure**: [deploy-infra.ps1](scripts/deploy-infra.ps1)
* **Managing the Locks**: [manage-locks.ps1](scripts/manage-locks.ps1)
* **Saved Infrastructure Config (JSON)**: [infra-config.json](scripts/infra-config.json)

---

## 7. Screenshots to Include With This Submission
Portal screenshots showing the locks in place should be dropped into the [screenshots](screenshots) folder, named as follows:
1. `rg_lock_screenshot.png` (Resource Group level lock)
2. `storage_account_lock_screenshot.png` (Storage Account lock + inherited lock)
3. `nsg_lock_screenshot.png` (NSG ReadOnly lock + inherited lock)
