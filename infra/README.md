---
title: Infrastructure Deployment Guide
description: Bicep infrastructure-as-code for the MSAL Java Workshop Evidence Portal
author: devopsabcs-engineering
ms.date: 2026-04-20
ms.topic: how-to
---

## Architecture Overview

```text
Resource Group
│
├── Virtual Network (vnet-evidence-<env>, 10.20.0.0/16)
│   ├── snet-app  10.20.1.0/24  (delegated to Microsoft.Web/serverFarms)
│   │      ├── SPA App Service (Node 20)   ─┐
│   │      └── API App Service (Java 17)   ─┤  Regional VNet integration
│   │                                       │  WEBSITE_VNET_ROUTE_ALL=1
│   └── snet-pe   10.20.2.0/24  (PE network policies disabled)
│          └── Private Endpoint (groupId=dfs) ──► ADLS Gen2
│
├── Private DNS Zone: privatelink.dfs.<storage-suffix>  (linked to VNet)
│
├── App Service Plan (S1 Linux)
│
├── Storage Account (ADLS Gen2)
│      isHnsEnabled = true
│      allowSharedKeyAccess = false      (OAuth + RBAC only)
│      publicNetworkAccess = Disabled
│      networkAcls.defaultAction = Deny
│      → API Managed Identity has "Storage Blob Data Contributor"
│
└── Application Insights + Log Analytics
```

The API App Service accesses ADLS Gen2 through its system-assigned Managed Identity with the `Storage Blob Data Contributor` role, over a Private Endpoint (groupId `dfs`). Shared keys are disabled at the storage account, so OAuth + RBAC is the only authentication path.

## Prerequisites

* Azure CLI with Bicep support (`az bicep version` to verify)
* An active Azure subscription
* A resource group created in your target region
* Two Entra ID app registrations (SPA and API) completed per workshop Module 2

## Deployment

### 1. Create a resource group

```bash
az group create \
  --name rg-evidence-workshop \
  --location canadacentral
```

### 2. Deploy the infrastructure

```bash
az deployment group create \
  --resource-group rg-evidence-workshop \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam \
  --parameters \
    storageAccountName='stevidencews' \
    spaClientId='<your-spa-client-id>' \
    apiClientId='<your-api-client-id>' \
    tenantId='<your-tenant-id>'
```

Replace the placeholder values with your Entra ID app registration details. The `storageAccountName` must be globally unique (3-24 lowercase alphanumeric characters).

### 3. Verify the deployment

```bash
az deployment group show \
  --resource-group rg-evidence-workshop \
  --name main \
  --query properties.outputs
```

This command returns the SPA URL, API URL, and storage account name.

## Post-Deployment Configuration

After deploying infrastructure, complete these steps:

1. Update your SPA app registration redirect URIs to include the deployed SPA URL (`https://app-evidence-spa-workshop.azurewebsites.net`).
2. Update your API app registration with the correct Application ID URI if different from the default `api://<apiClientId>`.
3. Deploy application code using `az webapp deploy`:

   ```bash
   # Deploy the API JAR
   az webapp deploy \
     --resource-group rg-evidence-workshop \
     --name app-evidence-api-workshop \
     --src-path sample-app/api/target/evidence-api-0.0.1-SNAPSHOT.jar \
     --type jar

   # Deploy the SPA (zip of dist output)
   cd sample-app/spa
   ng build --configuration production
   cd dist/evidence-spa/browser
   zip -r ../../../spa.zip .
   az webapp deploy \
     --resource-group rg-evidence-workshop \
     --name app-evidence-spa-workshop \
     --src-path ../../../spa.zip \
     --type zip
   ```

4. Upload sample evidence files to the `evidence` blob container using Azure Portal or CLI.

## Cost Estimate

| Resource | SKU | Estimated Monthly Cost |
| --- | --- | --- |
| App Service Plan | S1 (Linux) | ~$70 |
| Storage Account | Standard_LRS, HNS | ~$2 |
| Virtual Network | n/a | Free |
| Private Endpoint | 1 PE × ~$7.50 | ~$7.50 |
| Private DNS Zone | 1 zone × ~$0.50 | ~$0.50 |
| Application Insights | Pay-as-you-go | ~$2 |
| **Total** | | **~$82/month** |

> [!TIP]
> Stop or delete the App Service Plan when not running the workshop to avoid ongoing charges. The storage account, Private Endpoint, and DNS zone continue to bill while they exist.

## Cleanup

Delete the entire resource group to remove all deployed resources:

```bash
az group delete --name rg-evidence-workshop --yes --no-wait
```

## Module Reference

| Module | Purpose |
| --- | --- |
| `modules/vnet.bicep` | Virtual Network with `snet-app` (delegated to `Microsoft.Web/serverFarms`) and `snet-pe` (Private Endpoints, network policies disabled) |
| `modules/app-service-plan.bicep` | Linux App Service Plan, S1 minimum (required for VNet integration) |
| `modules/app-service-spa.bicep` | Node 20 App Service for Angular SPA with pm2, Regional VNet integration, `WEBSITE_VNET_ROUTE_ALL=1` |
| `modules/app-service-api.bicep` | Java 17 App Service for Spring Boot API, Regional VNet integration, `WEBSITE_VNET_ROUTE_ALL=1` |
| `modules/storage-account.bicep` | Hardened ADLS Gen2 (`isHnsEnabled=true`, `allowSharedKeyAccess=false`, `publicNetworkAccess=Enabled` with `networkAcls.defaultAction=Deny` and a `VirtualNetworkRule` for `snet-app`) with optional deployer-IP allow-list for the seed step. The `Enabled` flag is intentional — `virtualNetworkRules` are only honoured when public access is `Enabled`; the `Deny` default action still rejects every public caller that does not match a rule. |
| `modules/private-endpoint-storage.bicep` | Private Endpoint on the storage `dfs` sub-resource + Private DNS Zone `privatelink.dfs.<storage-suffix>` + VNet link |
| `modules/monitoring.bicep` | Log Analytics workspace and Application Insights |
| `modules/role-assignments.bicep` | `Storage Blob Data Contributor` for the API Managed Identity (and optionally for the deployer principal during seeding) |
