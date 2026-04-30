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

> ## Fast-Track: One-Command Deploy
>
> If you would rather see the final state in Azure first and study the steps afterward, run the one-stop deployment script. It is idempotent and chains every step below (resource group, Bicep, builds, app deploys, evidence upload, smoke test) into a single command:
>
> ```powershell
> az login --tenant <tenantId>
> az account set --subscription <subscriptionIdOrName>
> .\scripts\deploy.ps1
> ```
>
> When it finishes, the smoke-test section will print the SPA URL (expecting `200`) and the API `/api/cases` URL (expecting `401`, which proves JWT validation is on). Open the SPA URL, sign in with the same account you ran the script as (it has already been assigned `CaseReader` + `CaseAdmin`), and you should see all five sample cases. The full script reference is in the [README's Fast-Track to Azure section](../../README.md#fast-track-to-azure-one-command).
>
> The manual steps below remain valuable as a learning reference — they show exactly what `deploy.ps1` automates.

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

After the deployment completes, upload the sample evidence PDFs to the storage container. The `--auth-mode login` flag uses your Azure AD credentials (no storage keys), so you first need to grant yourself the **Storage Blob Data Contributor** role on the new account:

```bash
STORAGE_ACCOUNT=$(az deployment group show \
  --resource-group rg-evidence-workshop \
  --name main \
  --query properties.outputs.storageAccountNameOutput.value -o tsv)

# Grant the signed-in user the data plane role (Owner alone is not enough for blob ops)
USER_OID=$(az ad signed-in-user show --query id -o tsv)
SA_ID=$(az storage account show --resource-group rg-evidence-workshop --name $STORAGE_ACCOUNT --query id -o tsv)
az role assignment create \
  --assignee-object-id $USER_OID --assignee-principal-type User \
  --role 'Storage Blob Data Contributor' --scope $SA_ID

# Wait ~30s for the role assignment to propagate, then upload
sleep 30
az storage container create --account-name $STORAGE_ACCOUNT --name evidence --auth-mode login
az storage blob upload-batch \
  --account-name $STORAGE_ACCOUNT \
  --destination evidence \
  --source sample-app/api/src/main/resources/data/sample-evidence \
  --auth-mode login --overwrite
```

### Step 6: Deploy the SPA

```bash
SPA_APP=$(az deployment group show \
  --resource-group rg-evidence-workshop \
  --name main \
  --query properties.outputs.spaAppName.value -o tsv)

cd sample-app/spa/dist/evidence-portal/browser
zip -r ../../../../spa.zip .
az webapp deploy \
  --resource-group rg-evidence-workshop \
  --name $SPA_APP \
  --src-path ../../../../spa.zip \
  --type zip
```

> Some Angular versions emit straight to `dist/evidence-portal/` without a `browser/` sub-folder. Adjust the `cd` accordingly if you don't see the inner directory.

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

The Bicep deployment already populates the necessary app settings on both App Services (`SPRING_PROFILES_ACTIVE=prod`, `JWT_ISSUER_URI`, `JWT_AUDIENCE`, `AZURE_TENANT_ID`, `CORS_ALLOWED_ORIGINS`, `STORAGE_ACCOUNT_NAME`, and `APPLICATIONINSIGHTS_CONNECTION_STRING`). If you ever need to inspect or override them, use:

```bash
az webapp config appsettings list \
  --resource-group rg-evidence-workshop \
  --name $API_APP \
  --output table
```

To force a restart after changing settings:

```bash
az webapp restart --resource-group rg-evidence-workshop --name $API_APP
```

### Step 9: Update the SPA Redirect URI

1. Get the SPA URL:

   ```bash
   echo "https://$SPA_APP.azurewebsites.net"
   ```

2. Open the SPA app registration in the Entra Admin Center.
3. Go to **Authentication** and add a new SPA platform redirect URI: `https://<spa-app-name>.azurewebsites.net`.
4. Select **Save**.

> The fast-track `deploy.ps1` script does this for you by re-invoking `setup-entra-apps.ps1 -ProductionRedirectUri <spaUrl>` after the App Service URLs are known.

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
