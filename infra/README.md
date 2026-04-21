---
title: Infrastructure Deployment Guide
description: Bicep infrastructure-as-code for the MSAL Java Workshop Evidence Portal
author: devopsabcs-engineering
ms.date: 2026-04-20
ms.topic: how-to
---

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────┐
│                    Resource Group                        │
│                                                         │
│  ┌──────────────────────────────────────────────┐       │
│  │         App Service Plan (Linux B1)          │       │
│  │  ┌─────────────────┐ ┌────────────────────┐  │       │
│  │  │  SPA App Service │ │  API App Service   │  │       │
│  │  │  (Node 20 LTS)  │ │  (Java 17 SE)      │  │       │
│  │  │  Angular + pm2   │ │  Spring Boot 3.4   │  │       │
│  │  │  Managed Identity│ │  Managed Identity  │  │       │
│  │  └─────────────────┘ └────────┬───────────┘  │       │
│  └──────────────────────────────────────────────┘       │
│                                  │                       │
│                    Storage Blob Data Reader              │
│                                  │                       │
│  ┌───────────────────┐  ┌───────▼───────────┐           │
│  │  App Insights     │  │ Storage Account   │           │
│  │  + Log Analytics  │  │ (evidence container)│          │
│  └───────────────────┘  └───────────────────┘           │
└─────────────────────────────────────────────────────────┘
```

The API App Service accesses Azure Blob Storage through its system-assigned Managed Identity with the Storage Blob Data Reader role. No storage keys or SAS tokens are used.

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
|---|---|---|
| App Service Plan | B1 (Linux) | ~$13 |
| Storage Account | Standard_LRS | ~$0.50 |
| Application Insights | Pay-as-you-go | ~$0.50 |
| **Total** | | **~$14/month** |

> [!TIP]
> Stop or delete the App Service Plan when not running the workshop to avoid ongoing charges.

## Cleanup

Delete the entire resource group to remove all deployed resources:

```bash
az group delete --name rg-evidence-workshop --yes --no-wait
```

## Module Reference

| Module | Purpose |
|---|---|
| `modules/app-service-plan.bicep` | Linux App Service Plan with configurable SKU |
| `modules/app-service-spa.bicep` | Node 20 App Service for Angular SPA with pm2 |
| `modules/app-service-api.bicep` | Java 17 App Service for Spring Boot API |
| `modules/storage-account.bicep` | Storage Account with evidence blob container |
| `modules/monitoring.bicep` | Log Analytics workspace and Application Insights |
| `modules/role-assignments.bicep` | Storage Blob Data Reader role for API Managed Identity |
