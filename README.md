---
title: "MSAL Java Workshop: Entra ID Authentication with Angular SPA + Spring Boot API"
description: Workshop and sample applications demonstrating Microsoft Entra ID authentication with Angular 19 SPA and Spring Boot 3.4 API
ms.date: 2026-04-21
---

## Architecture

The Justice Evidence Portal uses a three-tier architecture with Microsoft Entra ID providing identity and access control across all layers.

```text
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│  Angular SPA │────►│  Spring Boot API  │────►│  Azure Blob      │
│  (MSAL Auth) │     │  (JWT Validation) │     │  Storage         │
│              │     │                   │     │  (Evidence Files) │
└──────┬───────┘     └────────┬──────────┘     └──────────────────┘
       │                      │                         ▲
       │   Auth Code + PKCE   │  Managed Identity       │
       ▼                      ▼                         │
┌─────────────────────────────────────────────────────────────────┐
│                    Microsoft Entra ID                            │
│         App Registrations  ·  Roles  ·  Scopes                  │
└─────────────────────────────────────────────────────────────────┘
```

The Angular SPA authenticates users via MSAL with Auth Code + PKCE flow. The Spring Boot API validates JWT tokens and enforces role-based access. Evidence files in Azure Blob Storage are accessed through the API using Managed Identity, eliminating storage account keys entirely.

## Scenario

The workshop centers on a Justice Evidence Portal: a secure application for managing case evidence files. Users authenticate through Entra ID, and the API enforces role-based access (CaseReader, CaseAdmin) before serving evidence documents from Azure Storage. External partners access the system as B2B guest users within the organization's tenant.

## Getting Started

### Prerequisites

| Tool | Version | Purpose |
|---|---|---|
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

[scripts/setup-entra-apps.ps1](scripts/setup-entra-apps.ps1) is an idempotent PowerShell helper that creates the SPA and API app registrations against the tenant you are currently logged in to with the Azure CLI. It is the fastest path through Exercise 1 if you prefer scripting over the Azure Portal.

What it does today (Phase 1):

- Verifies `az` is installed and you are signed in (`az login`).
- Acquires a Microsoft Graph access token and calls Graph directly via `Invoke-RestMethod` (no `az rest` quoting issues on Windows).
- Creates the **API app** and sets its Application ID URI to `api://<appId>`.
- Creates the **SPA app** and configures its SPA platform redirect URI (default `http://localhost:4200`).
- On re-run, looks each app up by `displayName` and reuses it instead of creating duplicates. Every step is a no-op if already configured.

Usage:

```powershell
# Sign in to the tenant where the apps should live
az login --tenant <tenantId>

# Bootstrap both app registrations
.\scripts\setup-entra-apps.ps1 `
    -SpaName "Evidence Portal SPA" `
    -ApiName "Evidence Portal API"

# Optional: capture the resulting IDs for downstream automation (e.g. deploy.ps1)
.\scripts\setup-entra-apps.ps1 `
    -SpaName "Evidence Portal SPA" `
    -ApiName "Evidence Portal API" `
    -RedirectUri "https://my-spa.azurewebsites.net" `
    -OutputFile ".\.entra-apps.json"
```

The script returns and prints `tenantId`, `apiAppId`, `apiObjectId`, `identifierUri`, `spaAppId`, `spaObjectId`, and `redirectUri`. Plug `tenantId`, `apiAppId`, and `spaAppId` into [`environment.ts`](sample-app/spa/src/environments/environment.ts) and [`application.properties`](sample-app/api/src/main/resources/application.properties) (or pass them to [scripts/deploy.ps1](scripts/deploy.ps1)).

> **Phase 2 (planned):** the same script will be extended via Microsoft Graph to expose the `Evidence.Read` scope, define `CaseReader` / `CaseAdmin` app roles, add the SPA's delegated permission on the API, pre-authorize the SPA, and grant tenant admin consent. Until then, complete those steps in the Azure Portal as described in [Exercise 1](workshop/guides/exercise-1-app-registrations.md).

### Workshop Exercises

Follow these exercises in order for the full 3-hour workshop experience:

| Exercise | Duration | Description |
|---|---|---|
| [Exercise 1: Configure App Registrations](workshop/guides/exercise-1-app-registrations.md) | 30 min | Create Entra ID app registrations for the SPA and API, configure scopes, roles, and update the SPA environment |
| [Exercise 2: Run SPA + API Locally](workshop/guides/exercise-2-run-locally.md) | 30 min | Sign in through the SPA, browse cases, download evidence, and inspect JWT tokens |
| [Exercise 3: Add Role-Protected Endpoint](workshop/guides/exercise-3-add-endpoint.md) | 20 min | Experience the RBAC cycle: 403 Forbidden, assign CaseAdmin role, re-authenticate, 201 Created |
| [Exercise 4: Deploy to Azure](workshop/guides/exercise-4-deploy-azure.md) | 20 min | Deploy both apps and infrastructure to Azure using Bicep, verify Managed Identity storage access |

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
|---|---|---|---|
| Frontend | Angular | 19.2 | Single Page Application framework |
| Frontend Auth | MSAL Angular | 5.2 | Entra ID authentication (Auth Code + PKCE) |
| Backend | Spring Boot | 3.4.4 | REST API framework |
| Backend Auth | Spring Security OAuth2 Resource Server | 6.2 | JWT validation with scope and role enforcement |
| Storage | Azure Blob Storage | 12.33.3 SDK | Evidence file storage via Managed Identity |
| Identity | Azure Identity | 1.18.2 SDK | DefaultAzureCredential for Managed Identity |
| Monitoring | Application Insights | 3.7.8 Agent | Telemetry for SPA (JS SDK) and API (runtime-attach) |
| Infrastructure | Bicep | Latest | Azure resource provisioning (App Service, Storage, monitoring) |

## Key Design Decisions

- **Dev profile is open**: No authentication required to explore the API locally. JWT validation and `@PreAuthorize` enforcement activate in non-dev profiles.
- **Dual-mode storage**: `LocalStorageService` serves embedded PDFs in dev; `AzureBlobStorageService` uses Managed Identity in prod.
- **No storage keys or SAS tokens**: All Azure Blob access uses Managed Identity with Storage Blob Data Reader role.
- **Simplified workshop infrastructure**: B1 Basic App Service Plan (~$14/month) without Private Endpoints. Production hardening is documented separately.

## Production Hardening

The workshop deployment uses simplified infrastructure to keep costs low and focus on authentication concepts. For production deployments requiring network isolation with Private Endpoints, VNet integration, and Private DNS Zones, see the [Production Hardening Guide](docs/production-hardening.md).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
