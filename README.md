---
title: "MSAL Java Workshop: Entra ID Authentication with Angular SPA + Spring Boot API"
description: Workshop and sample applications demonstrating Microsoft Entra ID authentication with Angular 19 SPA and Spring Boot 3.4 API
ms.date: 2026-04-20
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

## Quickstart

1. **Clone the repository**

   ```bash
   git clone https://github.com/devopsabcs-engineering/msal-java.git
   cd msal-java
   ```

2. **Configure app registrations** in Microsoft Entra ID. Follow [Exercise 1](workshop/exercises/exercise-01-app-registration.md) for step-by-step instructions.

3. **Run locally** with the Angular dev server and Spring Boot API. Follow [Exercise 2](workshop/exercises/exercise-02-run-locally.md) for local setup.

4. **Deploy to Azure** using Bicep templates and the Azure CLI. Follow [Exercise 4](workshop/exercises/exercise-04-deploy-to-azure.md) for deployment steps.

## Prerequisites

| Tool | Version | Purpose |
|---|---|---|
| Node.js | 20 LTS or later | Angular SPA build and development |
| Java JDK | 17 or later | Spring Boot API compilation and runtime |
| Maven | 3.9 or later | Java dependency management and build |
| Azure CLI | 2.60 or later | Azure resource provisioning and deployment |
| VS Code | Latest | Recommended editor with extensions |

## Repository Structure

```text
msal-java/
├── sample-app/
│   ├── api/              # Spring Boot 3.4 REST API (Java 17)
│   └── spa/              # Angular 19 Single Page Application
├── workshop/             # Workshop materials and exercises
│   ├── exercises/        # Hands-on exercise guides
│   └── slides/           # Presentation content
├── infra/                # Bicep templates for Azure deployment
├── scripts/              # Automation and helper scripts
├── docs/                 # Additional documentation
│   └── production-hardening.md
└── README.md
```

## Technology Stack

| Layer | Technology | Version | Purpose |
|---|---|---|---|
| Frontend | Angular | 19.2 | Single Page Application framework |
| Frontend Auth | MSAL Angular | 5.2 | Entra ID authentication for Angular |
| Backend | Spring Boot | 3.4.4 | REST API framework |
| Backend Auth | Spring Cloud Azure | 7.2.0 | Azure integration and JWT validation |
| Storage | Azure Blob Storage | 12.33.3 SDK | Evidence file storage |
| Identity | Azure Identity | 1.18.2 SDK | Managed Identity credential provider |
| Monitoring | Application Insights | 3.7.8 Agent | Telemetry for SPA and API |

## Workshop

The full workshop includes presentations, exercises, and instructor notes covering Entra ID app registrations, local development, role-based access, and Azure deployment.

See [workshop/README.md](workshop/README.md) for the complete workshop guide and schedule.

## Production Hardening

The workshop deployment uses simplified infrastructure (B1 Basic plan, public endpoints) to keep costs low and focus on authentication concepts. For production deployments requiring network isolation with Private Endpoints, VNet integration, and Private DNS Zones, see the [Production Hardening Guide](docs/production-hardening.md).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
