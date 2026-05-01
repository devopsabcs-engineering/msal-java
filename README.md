---
title: "MSAL Java Workshop: Entra ID Authentication with Angular SPA + Spring Boot API"
description: Workshop and sample applications demonstrating Microsoft Entra ID authentication with Angular 19 SPA and Spring Boot 3.4 API
ms.date: 2026-04-21
---

## Architecture

The Justice Evidence Portal uses a three-tier architecture with Microsoft Entra ID providing identity and access control across all layers.

```text
                                                          ┌──────────────────────────────┐
                                                          │ Virtual Network 10.20.0.0/16 │
                                                          │                              │
┌──────────────┐     ┌──────────────────┐                 │  ┌──────────────────────┐    │
│  Angular SPA │────►│  Spring Boot API │──── MI OAuth ──►│  │ Private Endpoint     │    │
│  (MSAL.js,   │     │  (JWT v2,        │     (Storage    │  │ snet-pe / dfs        │    │
│   Auth Code  │     │   Resource       │     Blob Data   │  │ privatelink.dfs.<…>  │    │
│   + PKCE)    │     │   Server)        │     Contributor)│  └──────────┬───────────┘    │
└──────┬───────┘     └────────┬─────────┘                 └─────────────┼────────────────┘
       │                      │                                         │
       │   Auth Code + PKCE   │  Bearer JWT v2                          ▼
       ▼                      ▼                              ┌────────────────────────┐
┌─────────────────────────────────────────────────┐          │ ADLS Gen2 (HNS)        │
│                Microsoft Entra ID               │          │ shared keys: disabled  │
│   App Registrations  ·  Roles  ·  Scopes        │          │ public access: denied  │
└─────────────────────────────────────────────────┘          └────────────────────────┘
```

The Angular SPA authenticates users via MSAL with Auth Code + PKCE flow. The Spring Boot API validates JWT v2 tokens and enforces role-based access. Evidence files in Azure Data Lake Storage Gen2 are accessed through the API using Managed Identity over a Private Endpoint, eliminating storage account keys entirely — shared keys are disabled at the storage account.

## Scenario

The workshop centers on a Justice Evidence Portal: a secure application for managing case evidence files. Users authenticate through Entra ID, and the API enforces role-based access (CaseReader, CaseAdmin) before serving evidence documents from Azure Storage. External partners access the system as B2B guest users within the organization's tenant.

## Getting Started

### Prerequisites

| Tool | Version | Purpose |
| --- | --- | --- |
| Node.js | 20 LTS or later | Angular SPA build and development |
| Java JDK | 17 or later | Spring Boot API compilation and runtime |
| Maven | 3.9 or later (auto-installed by start script) | Java dependency management and build |
| Azure CLI | 2.60 or later | Azure resource provisioning and deployment |
| VS Code | Latest | Recommended editor with extensions |

### Quick Start (Run Locally in 2 Minutes)

The sample apps work immediately without any Azure or Entra ID configuration. The `dev` profile serves 5 mock cases and permits all API requests so you can explore the code before setting up authentication.

1. **Clone the repository** (or click "Use this template" on GitHub):

   ```bash
   git clone https://github.com/devopsabcs-engineering/msal-java.git
   cd msal-java
   ```

2. **Start both apps** with a single command:

   **PowerShell (Windows):**

   ```powershell
   .\scripts\start.ps1
   ```

   **Bash (macOS/Linux):**

   ```bash
   ./scripts/start.sh
   ```

   The start script automatically:
   - Downloads and installs Maven if it is not found on your PATH
   - Installs SPA npm dependencies if `node_modules` is missing
   - Kills any previous instances on ports 4200 and 8080
   - Starts the Spring Boot API (`http://localhost:8080`)
   - Starts the Angular SPA (`http://localhost:4200`)

3. **Verify the API** returns mock data:

   ```bash
   curl http://localhost:8080/api/cases
   ```

   You should see 5 JSON case objects.

4. **Open the SPA** at [http://localhost:4200](http://localhost:4200) to see the Justice Evidence Portal landing page.

> **Note:** The "Sign In" button will fail until you complete Exercise 1 (Entra ID app registration). The API endpoints are fully functional without authentication in dev mode.

### Bootstrap Entra ID App Registrations (PowerShell)

[scripts/setup-entra-apps.ps1](scripts/setup-entra-apps.ps1) is an idempotent PowerShell helper that creates and fully configures the SPA and API app registrations against the tenant you are currently logged in to with the Azure CLI. It is the fastest path through Exercise 1 if you prefer scripting over the Azure Portal.

What it does (every call is a no-op if the resource is already configured the right way):

- Verifies `az` is installed and you are signed in (`az login`).
- Acquires a Microsoft Graph access token and calls Graph directly via `Invoke-RestMethod` (no `az rest` quoting issues on Windows).
- Creates the **API app**, sets its Application ID URI to `api://<appId>`, exposes the `Evidence.Read` OAuth2 scope, and defines the `CaseReader` and `CaseAdmin` app roles.
- Creates the **SPA app**, configures its SPA platform redirect URI(s), grants the delegated `Evidence.Read` permission, and pre-authorizes the SPA on the API.
- Creates service principals for both apps if they don't exist yet.
- (Optional, default on) Grants tenant admin consent for the SPA's delegated permission and self-assigns the signed-in user to both `CaseReader` and `CaseAdmin` so you can sign in immediately.
- (Optional, default on) Patches the local `environment.ts`, `environment.prod.ts`, and `application.properties` files with the resulting client/tenant IDs and scope URI.

Usage:

```powershell
# Sign in to the tenant where the apps should live
az login --tenant <tenantId>

# Bootstrap both app registrations and patch local config
.\scripts\setup-entra-apps.ps1 `
    -SpaName "Evidence Portal SPA" `
    -ApiName "Evidence Portal API"

# Re-run later with a production redirect URI (idempotent)
.\scripts\setup-entra-apps.ps1 `
    -SpaName "Evidence Portal SPA" `
    -ApiName "Evidence Portal API" `
    -ProductionRedirectUri "https://my-spa.azurewebsites.net" `
    -OutputFile ".\.entra-apps.json"
```

The script returns and prints `tenantId`, `apiAppId`, `apiObjectId`, `apiServicePrincipalId`, `apiScopeId`, `apiScopeUri`, `roleReaderId`, `roleAdminId`, `spaAppId`, `spaObjectId`, `spaServicePrincipalId`, plus the redirect URIs and consent/role-assignment status. With `-OutputFile` it also writes a JSON state file that [scripts/deploy.ps1](scripts/deploy.ps1) consumes on its next run, so you don't need to re-run setup before every deployment.

> Skip the patching or admin consent with `-UpdateLocalConfig:$false`, `-GrantAdminConsent:$false`, or `-AssignCurrentUserToRoles:$false` if you would rather wire those up by hand.

### Fast-Track to Azure (One Command)

If you want to see the deployed end-state in Azure as quickly as possible — without going through the four guided exercises — run the one-stop deployment script. It chains every step of Exercises 1 and 4 into a single idempotent run.

```powershell
# Sign in once to the tenant where the apps and Azure resources should live
az login --tenant <tenantId>
az account set --subscription <subscriptionIdOrName>

# Deploy everything (Entra ID + Bicep + SPA + API + evidence files)
.\scripts\deploy.ps1
```

What `deploy.ps1` does end-to-end:

1. Verifies `az`, `node`, `mvn` (auto-installs Maven into `%LOCALAPPDATA%\Maven` if missing).
2. Calls `setup-entra-apps.ps1` to create/reuse both app registrations, expose the scope and roles, force the API token version to v2, grant admin consent, and assign your user to `CaseReader` + `CaseAdmin`.
3. Creates the resource group `rg-evidence-workshop` in `canadacentral` and a deterministic globally-unique storage account name.
4. Detects your public IP and Entra principal objectId so the seed step can run over OAuth without ever using a shared key.
5. Deploys the Bicep stack: VNet (`snet-app` delegated to `Microsoft.Web/serverFarms`, `snet-pe` for endpoints), App Service Plan (S1 Linux — minimum SKU for VNet integration), two App Services with system-assigned Managed Identity and Regional VNet integration, hardened ADLS Gen2 storage (`isHnsEnabled=true`, `allowSharedKeyAccess=false`, `publicNetworkAccess=Disabled`, `networkAcls.defaultAction=Deny`), Private Endpoint on the storage `dfs` sub-resource, Private DNS Zone `privatelink.dfs.<storage suffix>`, Application Insights, and `Storage Blob Data Contributor` role assignment for the API Managed Identity.
6. Patches `environment.prod.ts` with the deployed SPA/API URLs and App Insights connection string.
7. Re-runs `setup-entra-apps.ps1` to add the production SPA URL as a SPA-platform redirect URI on the SPA app registration.
8. Builds the Angular SPA in production mode (with the Ontario Design System assets fetched into `public/vendor/`) and the Spring Boot API as an executable JAR.
9. Deploys the SPA zip and the API JAR with `az webapp deploy`.
10. Uploads the five sample PDFs over OAuth (`--auth-mode login`, no shared keys) using the temporary deployer-IP allow-list and `Storage Blob Data Contributor` RBAC.
11. Re-deploys storage with `deployerIp=''` so `publicNetworkAccess` flips back to `Disabled`. App Services keep working via the Private Endpoint.
12. Smoke-tests the result: SPA URL must return `200`, API `/api/cases` must return `401` (proving JWT validation is enforced).

When it finishes you'll see something like:

```text
Deployment complete

 Resource Group : rg-evidence-workshop
 Region         : canadacentral
 SPA URL        : https://app-evidence-spa-workshop.azurewebsites.net
 API URL        : https://app-evidence-api-workshop.azurewebsites.net
 Storage        : stevpworkshopXXXXXXXX (container: evidence)
```

Open the SPA URL, sign in with the same account you ran the script as, and you should land on the case list with all five sample cases — files served from Blob Storage through the API's Managed Identity.

Common flags:

| Flag | Default | Purpose |
| --- | --- | --- |
| `-ResourceGroup` | `rg-evidence-workshop` | Target resource group (created if missing). |
| `-Location` | `canadacentral` | Azure region. |
| `-Environment` | `workshop` | Suffix used for App Service names (`app-evidence-spa-<env>`, `app-evidence-api-<env>`). |
| `-SkipEntraSetup` | off | Reuse a previous `.entra-apps.json` and skip the Graph calls. |
| `-SkipBuild` | off | Reuse the existing `dist/` and `target/` artifacts. |
| `-SkipUpload` | off | Skip the sample-evidence blob upload. |

When you're done with the workshop, remove everything with:

```powershell
az group delete --name rg-evidence-workshop --yes --no-wait
```


### Workshop Exercises

Follow these exercises in order for the full 3-hour workshop experience. Already saw the Fast-Track land everything in Azure? You can still use these guides as a tear-down of what `deploy.ps1` automated.

| Exercise | Duration | Description |
| --- | --- | --- |
| [Exercise 1: Configure App Registrations](workshop/guides/exercise-1-app-registrations.md) | 30 min | Create Entra ID app registrations for the SPA and API, configure scopes, roles, and update the SPA environment. (Automated end-to-end by `setup-entra-apps.ps1`.) |
| [Exercise 2: Run SPA + API Locally](workshop/guides/exercise-2-run-locally.md) | 30 min | Sign in through the SPA, browse cases, download evidence, and inspect JWT tokens. |
| [Exercise 3: Add Role-Protected Endpoint](workshop/guides/exercise-3-add-endpoint.md) | 20 min | Experience the RBAC cycle: 403 Forbidden, assign CaseAdmin role, re-authenticate, 201 Created. |
| [Exercise 4: Deploy to Azure](workshop/guides/exercise-4-deploy-azure.md) | 20 min | Deploy both apps and infrastructure to Azure using Bicep, verify Managed Identity storage access. (Automated end-to-end by `deploy.ps1`.) |

For the full instructor delivery guide with 9-module schedule and presentation notes, see [workshop/README.md](workshop/README.md).

## Repository Structure

```text
msal-java/
├── sample-app/
│   ├── api/                # Spring Boot 3.4 REST API (Java 17)
│   │   ├── src/main/java/  # Controllers, services, security config
│   │   ├── src/main/resources/  # Properties, sample data, evidence PDFs
│   │   ├── Dockerfile
│   │   └── pom.xml
│   └── spa/                # Angular 19 Single Page Application
│       ├── src/app/        # Components, services, MSAL config
│       ├── src/environments/  # Dev and prod environment configs
│       └── package.json
├── workshop/
│   ├── guides/             # 4 hands-on exercise guides
│   ├── solutions/          # Exercise 3 solution files
│   └── README.md           # Instructor delivery guide
├── infra/                  # Bicep IaC (App Service, Storage, monitoring)
│   ├── main.bicep
│   ├── main.bicepparam
│   └── modules/            # 6 Bicep modules
├── scripts/
│   ├── start.ps1           # Start both apps locally (Windows)
│   ├── start.sh            # Start both apps locally (macOS/Linux)
│   ├── deploy.ps1          # Full Azure deployment (PowerShell)
│   ├── deploy.sh           # Full Azure deployment (Bash)
│   ├── setup-entra-apps.ps1  # Idempotent app registration bootstrap (PowerShell, Graph API)
│   ├── setup-entra-apps.sh   # Automate app registrations (Bash, az CLI)
│   └── configure-app-settings.sh  # Post-deploy configuration
├── docs/
│   └── production-hardening.md  # PE, VNet, DNS for production
└── README.md
```

## Technology Stack

| Layer | Technology | Version | Purpose |
| --- | --- | --- | --- |
| Frontend | Angular | 19.2 | Single Page Application framework |
| Frontend Auth | MSAL Angular | 5.2 | Entra ID authentication (Auth Code + PKCE) |
| Backend | Spring Boot | 3.4.4 | REST API framework |
| Backend Auth | Spring Security OAuth2 Resource Server | 6.2 | JWT validation with scope and role enforcement |
| Storage | Azure Data Lake Storage Gen2 | `azure-storage-file-datalake` 12.23.0 | Evidence file storage via Managed Identity over Private Endpoint |
| Identity | Azure Identity | 1.18.2 SDK | DefaultAzureCredential for Managed Identity |
| Monitoring | Application Insights | 3.7.8 Agent | Telemetry for SPA (JS SDK) and API (runtime-attach) |
| Infrastructure | Bicep | Latest | Azure resource provisioning (App Service, Storage, monitoring) |

## Key Design Decisions

- **Dev profile is open**: No authentication required to explore the API locally. JWT validation and `@PreAuthorize` enforcement activate in non-dev profiles.
- **Dual-mode storage**: `LocalStorageService` serves embedded PDFs in dev; `AzureBlobStorageService` (the production bean) uses the ADLS Gen2 DataLake SDK + Managed Identity over the Private Endpoint in prod.
- **No storage keys, no SAS tokens, no anonymous access**: Shared keys are disabled at the storage account; all data-plane access is Entra ID OAuth + RBAC (`Storage Blob Data Contributor` on the API Managed Identity). The seed step uploads sample PDFs the same way (`az storage blob upload-batch --auth-mode login`) under a temporary deployer-IP allow-list that is removed at the end of the deployment.
- **Hardened-by-default network**: `publicNetworkAccess=Disabled`, `networkAcls.defaultAction=Deny`, App Services run with `WEBSITE_VNET_ROUTE_ALL=1` so storage traffic resolves through the `privatelink.dfs.<storage-suffix>` zone to the Private Endpoint NIC IP.

## Production Hardening

The workshop already ships with a hardened-by-default network and identity posture: ADLS Gen2 with shared keys disabled and `publicNetworkAccess=Disabled`, App Service Regional VNet integration, a Private Endpoint on the storage `dfs` sub-resource, and Managed Identity + RBAC end-to-end. For the optional next-step controls (Front Door + WAF, App Service Private Endpoints, customer-managed keys, multi-region failover), see the [Production Hardening Guide](docs/production-hardening.md).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
