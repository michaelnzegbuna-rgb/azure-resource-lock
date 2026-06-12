# Azure Resource Locks Learning Program: Governance and Security Report

This repository contains the report, deployment scripts, and configuration files for the **Azure Resource Locks** learning project. This project implements safety guardrails at the resource and resource group levels to enforce cloud governance, prevent accidental deletions, and establish defensive configurations.

---

## 1. Project Overview & Goals

The objective of this assignment is to understand and verify the behavior of Azure Resource Locks (`CanNotDelete` and `ReadOnly`) across different resource tiers, analyze how locks interact with Azure Role-Based Access Control (RBAC), and explore lock automation.

### Resource Inventory
The following resources were provisioned in the **West Europe** region under the subscription `Azure subscription 1` (ID: `9335a9cd-ae74-439b-94b3-d965ca478c53`):
* **Resource Group**: `rg-locks-learning-prod`
* **Storage Account**: `salearningprod899756` (Standard LRS, StorageV2)
* **Network Security Group**: `nsg-learning-prod`
* **Virtual Machine**: `vm-learning-prod` (Ubuntu 22.04 LTS, Size: `Standard_D2s_v5`)

---

## 2. Lock Type Comparison Matrix

The table below summarizes the key behavioral differences between `CanNotDelete` and `ReadOnly` locks, verified through automated CLI testing.

| Lock Type | Can Read Resource? | Can Modify Resource? | Can Delete Resource? | Control Plane POST Actions? (e.g., Start/Stop VM) |
| :--- | :---: | :---: | :---: | :---: |
| **CanNotDelete** (Delete) | Yes | **Yes** | **No** | Yes |
| **ReadOnly** | Yes | **No** | **No** | **No** |

---

## 3. Observed CLI Errors & Validation Logs

We performed testing using the Azure CLI (`az`) logged in as the **Subscription Owner** (highest administrative tier). The logs below capture the real outputs of our test cases.

### Case 1: CanNotDelete Lock (Storage Account)
* **Modification Test**: We updated the tags of the Storage Account `salearningprod899756` using the command:
  ```powershell
  az storage account update --name salearningprod899756 --resource-group rg-locks-learning-prod --tags Project=AzureLocks
  ```
  **Result**: **Success**. The tags were updated successfully. This proves that `CanNotDelete` allows write/update actions.

* **Deletion Test**: We attempted to delete the Storage Account:
  ```powershell
  az storage account delete --name salearningprod899756 --resource-group rg-locks-learning-prod --yes
  ```
  **Result**: **Blocked**. Azure returned the following error:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod/providers/Microsoft.Storage/storageAccounts/salearningprod899756' cannot perform delete operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourcegroups/rg-locks-learning-prod/providers/Microsoft.Storage/storageAccounts/salearningprod899756'. Please remove the lock and try again.
  ```

---

### Case 2: ReadOnly Lock (Network Security Group)
* **Modification Test**: We attempted to add a new security rule (`AllowHTTP`) to the NSG `nsg-learning-prod`:
  ```powershell
  az network nsg rule create --resource-group rg-locks-learning-prod --nsg-name nsg-learning-prod --name AllowHTTP --priority 100 --destination-port-ranges 80 --direction Inbound --access Allow --protocol Tcp
  ```
  **Result**: **Blocked**. Azure returned a `ScopeLocked` write failure:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-learning-prod/securityRules/AllowHTTP' cannot perform write operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourcegroups/rg-locks-learning-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-learning-prod'. Please remove the lock and try again.
  ```

* **Deletion Test**: We attempted to delete the NSG:
  ```powershell
  az network nsg delete --resource-group rg-locks-learning-prod --name nsg-learning-prod
  ```
  **Result**: **Blocked**. Azure returned the following error:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-learning-prod' cannot perform delete operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourcegroups/rg-locks-learning-prod/providers/Microsoft.Network/networkSecurityGroups/nsg-learning-prod'. Please remove the lock and try again.
  ```

---

### Case 3: Resource Group Lock Inheritance
We removed the resource-specific locks and applied a `CanNotDelete` lock at the parent Resource Group level (`rg-locks-learning-prod`).
* **Inheritance Test**: We attempted to delete the Storage Account `salearningprod899756` (which had no resource-level lock):
  ```powershell
  az storage account delete --name salearningprod899756 --resource-group rg-locks-learning-prod --yes
  ```
  **Result**: **Blocked**. The delete request failed, and Azure pointed directly to the parent Resource Group lock:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod/providers/Microsoft.Storage/storageAccounts/salearningprod899756' cannot perform delete operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod'. Please remove the lock and try again.
  ```
  **Observation**: This confirms that locks are inherited by all child resources from their parent resource group scope.

---

### Case 4: Cascading Protection
* **Resource Group Deletion Test**: We attempted to delete the entire Resource Group `rg-locks-learning-prod` containing the locked resources:
  ```powershell
  az group delete --name rg-locks-learning-prod --yes
  ```
  **Result**: **Blocked**. Azure prevents deletion of a container group if it or any resources inside it are locked:
  ```json
  ERROR: (ScopeLocked) The scope '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourcegroups/rg-locks-learning-prod' cannot perform delete operation because following scope(s) are locked: '/subscriptions/9335a9cd-ae74-439b-94b3-d965ca478c53/resourceGroups/rg-locks-learning-prod'. Please remove the lock and try again.
  ```
  **Observation**: This prevents accidental cascading deletion of an entire environment.

---

### Case 5: RBAC Interaction
Our tests were conducted with full Subscription Owner privileges. The fact that every deletion and modification attempt was rejected shows that **Azure Resource Locks override high-level RBAC roles (Owner/Contributor)**. 
* To perform these operations, even a Subscription Owner must explicitly remove the resource lock first, adding a deliberate "two-step verification" behavior that reduces operational mistakes.

---

## 4. Why a ReadOnly Lock Blocks VM Start and Stop Operations

A common point of confusion is why a `ReadOnly` lock prevents basic runtime actions like starting or stopping a Virtual Machine. The explanation lies in the distinction between the **Management Plane (Control Plane)** and the **Data Plane**.

1. **Management Plane Actions**:
   Starting and stopping a VM are management plane operations handled by Azure Resource Manager (ARM).
   * **Starting a VM** requires Azure to allocate physical hypervisor resources and update the VM's metadata properties (such as setting the `powerState` status to `VM running`).
   * **Stopping (Deallocating) a VM** releases the physical hypervisor resources, updates the VM metadata (`powerState` to `VM deallocated`), and might release or update associated dynamic network components (like dynamic public IP addresses).
2. **REST API Method Restrictions**:
   * A `ReadOnly` lock restricts all write and configuration operations in the ARM control plane. In REST terms, it blocks all HTTP `PUT`, `DELETE`, and `POST` requests.
   * Power state changes are triggered via POST requests to the ARM API endpoints:
     * Start: `POST https://management.azure.com/.../virtualMachines/vm-learning-prod/start?api-version=...`
     * PowerOff/Deallocate: `POST https://management.azure.com/.../virtualMachines/vm-learning-prod/deallocate?api-version=...`
   * Because these POST requests alter the state of the resource and its billing configuration (transitioning compute costs), ARM rejects these operations under a `ReadOnly` lock.
3. **Data Plane Exception**:
   A `ReadOnly` lock does *not* affect data plane traffic. For example, if the VM is already running, users can still access websites hosted on the VM or SSH into the OS, because those operations bypass Azure Resource Manager and run directly on the VM's operating system (data plane).

---

## 5. Advanced Governance: Automating Locks with Azure Policy

To enforce a "security-first" posture at scale, organizations use **Azure Policy** to automatically apply resource locks based on tags (e.g. locking any resource marked with `Environment: Production`).

Below is an Azure Policy definition that enforces a `CanNotDelete` lock on any resource tagged with `LockStatus: CanNotDelete` using the `deployIfNotExists` effect.

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

## 6. Project Scripts

The scripts used in this project are located in the [scripts](scripts) directory:
* **Infrastructure Provisioning**: [deploy-infra.ps1](scripts/deploy-infra.ps1)
* **Resource Lock Management**: [manage-locks.ps1](scripts/manage-locks.ps1)
* **Infrastructure Config (JSON)**: [infra-config.json](scripts/infra-config.json)

---

## 7. Submission Screenshots
The screenshots demonstrating the locks in the Azure portal should be saved in the [screenshots](screenshots) directory as:
1. `rg_lock_screenshot.png` (Resource Group level lock)
2. `storage_account_lock_screenshot.png` (Storage Account lock + inherited lock)
3. `nsg_lock_screenshot.png` (NSG ReadOnly lock + inherited lock)
