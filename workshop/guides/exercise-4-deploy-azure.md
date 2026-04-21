---
title: "Exercise 4: Deploy to Azure with Bicep"
description: "Step-by-step guide for deploying the evidence management application to Azure using Bicep and verifying Managed Identity storage access"
ms.date: 2026-04-20
ms.topic: tutorial
estimated_reading_time: 5
---

## Objective

Deploy the complete evidence management solution to Azure using Bicep infrastructure-as-code templates. Verify that the API accesses Azure Blob Storage through Managed Identity (no storage account keys). By the end of this exercise, both applications run in Azure App Service and evidence files download from Blob Storage.

**Duration:** 20 minutes

**Prerequisite:** Exercise 3 completed and Azure CLI authenticated (`az login`).

**Cost note:** The deployed infrastructure uses a B1 App Service Plan and Standard LRS Storage Account, costing approximately $14/month. Delete the resource group after the workshop to avoid ongoing charges.

## Steps

### Step 1: Create a Resource Group

```bash
az group create \
  --name rg-evidence-workshop \
  --location canadacentral
```

### Step 2: Update Bicep Parameters

Open `infra/main.bicepparam` and update the parameter values with the app registration IDs from Exercise 1:

| Parameter | Value |
|-----------|-------|
| `spaClientId` | SPA Application (client) ID |
| `apiClientId` | API Application (client) ID |
| `tenantId` | Directory (tenant) ID |

### Step 3: Deploy the Infrastructure

Run the Bicep deployment. This creates the App Service Plan, two App Services, Storage Account, Application Insights, and role assignments for Managed Identity.

```bash
az deployment group create \
  --resource-group rg-evidence-workshop \
  --template-file infra/main.bicep \
  --parameters infra/main.bicepparam
```

The deployment takes 5-10 minutes. While it runs, proceed to Step 4.

### Step 4: Build the Applications

While the infrastructure deploys, build both applications in separate terminals:

**Build the SPA:**

```bash
cd sample-app/spa
ng build --configuration production
```

**Build the API:**

```bash
cd sample-app/api
mvn clean package -DskipTests
```

### Step 5: Upload Sample Evidence Files to Storage

After the deployment completes, upload the sample evidence PDFs to the storage container:

```bash
STORAGE_ACCOUNT=$(az deployment group show \
  --resource-group rg-evidence-workshop \
  --name main \
  --query properties.outputs.storageAccountName.value -o tsv)

az storage blob upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --destination evidence \
  --source sample-app/api/src/main/resources/data/evidence-files \
  --auth-mode login
```

### Step 6: Deploy the SPA

```bash
SPA_APP=$(az deployment group show \
  --resource-group rg-evidence-workshop \
  --name main \
  --query properties.outputs.spaAppName.value -o tsv)

cd sample-app/spa/dist/evidence-portal/browser
zip -r ../../../spa.zip .
az webapp deploy \
  --resource-group rg-evidence-workshop \
  --name $SPA_APP \
  --src-path ../../../spa.zip \
  --type zip
```

### Step 7: Deploy the API

```bash
API_APP=$(az deployment group show \
  --resource-group rg-evidence-workshop \
  --name main \
  --query properties.outputs.apiAppName.value -o tsv)

az webapp deploy \
  --resource-group rg-evidence-workshop \
  --name $API_APP \
  --src-path sample-app/api/target/evidence-api-0.0.1-SNAPSHOT.jar \
  --type jar
```

### Step 8: Configure App Settings

Run the configuration script to set environment variables on both App Services:

```bash
cd scripts
chmod +x configure-app-settings.sh
./configure-app-settings.sh \
  --resource-group rg-evidence-workshop \
  --spa-app $SPA_APP \
  --api-app $API_APP
```

This sets the Entra ID configuration values, storage account name, and Application Insights connection string on the deployed applications.

### Step 9: Update the SPA Redirect URI

1. Get the SPA URL:

   ```bash
   echo "https://$SPA_APP.azurewebsites.net"
   ```

2. Open the SPA app registration in the Entra Admin Center.
3. Go to **Authentication** and add a new SPA platform redirect URI: `https://<spa-app-name>.azurewebsites.net`.
4. Select **Save**.

### Step 10: Test the Deployed Application

1. Navigate to `https://<spa-app-name>.azurewebsites.net` in your browser.
2. Sign in with your Entra ID account.
3. Browse to `/cases` and verify the case list loads.
4. Open a case and download an evidence file.
5. Confirm the PDF opens correctly. The file now comes from Azure Blob Storage via the API's Managed Identity, with no storage account keys involved.

## Verification

Confirm each of these items works in the deployed environment:

- [ ] Both App Services are running (check the Azure portal or `az webapp show`)
- [ ] Sign-in redirects to Entra ID and returns to the deployed SPA URL
- [ ] Case list loads with data
- [ ] Evidence file downloads as a valid PDF from Azure Blob Storage
- [ ] Application Insights shows telemetry from both applications

## Cleanup

Delete the resource group to remove all deployed resources and stop billing:

```bash
az group delete --name rg-evidence-workshop --yes --no-wait
```

Also remove the production redirect URI from the SPA app registration if you no longer need it.

## Troubleshooting

| Problem | Cause | Fix |
|---------|-------|-----|
| Deployment fails with quota error | Subscription has reached resource limits for the region | Try a different region or request a quota increase |
| SPA returns 404 after deployment | SPA build output not in the correct directory | Verify `ng build` output is in `dist/evidence-portal/browser` and the zip was created from that directory |
| API returns 500 on startup | Missing environment variables | Run `configure-app-settings.sh` and restart the API App Service: `az webapp restart --name $API_APP --resource-group rg-evidence-workshop` |
| Evidence download returns 403 from Storage | Managed Identity role assignment has not propagated | Wait 5 minutes for the Storage Blob Data Reader role to propagate, then retry |
| "redirect_uri mismatch" on sign-in | Production redirect URI not added to app registration | Add `https://<spa-app-name>.azurewebsites.net` as a SPA platform redirect URI in the Entra Admin Center |
| CORS errors in the deployed SPA | API CORS configuration only allows localhost | The API production profile should allow the deployed SPA origin; verify `application.properties` CORS settings |
