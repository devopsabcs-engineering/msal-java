---
title: "MSAL Java Workshop: Instructor Delivery Guide"
description: "Instructor guide for the 3-hour Entra ID authentication workshop covering Angular SPA + Spring Boot API with MSAL"
ms.date: 2026-04-20
ms.topic: tutorial
author: devopsabcs-engineering
---

## Overview

This workshop teaches engineers how to design and implement secure authentication and authorization for an Angular SPA + Java Spring Boot API using Microsoft Entra ID. Participants build and deploy an evidence management application that demonstrates OAuth 2.0 Authorization Code Flow with PKCE, JWT validation, app roles, and Azure Blob Storage access via Managed Identity.

| Detail | Value |
|--------|-------|
| Duration | 3 hours 10 minutes |
| Audience | 5-6 engineers with Java and Angular basics |
| Format | Presentations, code tours, and hands-on exercises |
| Delivery | In-person or virtual with screen sharing |

## Prerequisites

Ensure all participant machines have the following tools installed before the session begins.

| Tool | Minimum Version | Verification Command |
|------|-----------------|---------------------|
| Node.js | 20.x LTS | `node --version` |
| Java JDK | 17 | `java --version` |
| Maven | 3.9+ | `mvn --version` |
| Azure CLI | 2.60+ | `az --version` |
| VS Code | Latest | `code --version` |
| Git | 2.40+ | `git --version` |
| Angular CLI | 19.x | `ng version` |

Each participant also needs:

- An Entra ID account in the workshop tenant with permission to create app registrations
- An Azure subscription with Contributor access to a resource group
- The workshop repository cloned locally

## Schedule

| Time | Duration | Module | Type |
|------|----------|--------|------|
| 0:00 | 15 min | M1: Architecture Overview | Presentation |
| 0:15 | 15 min | M2: Entra ID Deep-Dive | Presentation + Demo |
| 0:30 | 30 min | M3: Exercise 1, Configure App Registrations | Hands-on |
| 1:00 | 10 min | Break 1 | — |
| 1:10 | 15 min | M4: MSAL Angular SPA Walkthrough | Code Tour |
| 1:25 | 30 min | M5: Exercise 2, Run SPA + API Locally | Hands-on |
| 1:55 | 15 min | M6: API Security and Authorization | Code Tour |
| 2:10 | 20 min | M7: Exercise 3, Add Role-Protected Endpoint | Hands-on |
| 2:30 | 5 min | Break 2 | — |
| 2:35 | 20 min | M8: Exercise 4, Deploy to Azure with Bicep | Hands-on |
| 2:55 | 15 min | M9: Wrap-Up, Pitfalls, and Q&A | Discussion |

## Module Delivery Notes

### M1: Architecture Overview (15 min, Presentation)

Open with the architecture diagram showing the Angular SPA in App Service 1, Spring Boot API in App Service 2, and Azure Blob Storage for evidence files. Walk through the OAuth 2.0 Authorization Code Flow with PKCE sequence: user clicks sign-in, browser redirects to Entra ID, authorization code returns, MSAL redeems code for tokens, SPA calls API with Bearer token, API validates JWT and returns data.

Key points to emphasize:

- Two App Services share a single App Service Plan
- The SPA is a public client with no client secret
- Evidence files in Blob Storage are accessed through the API, never directly from the browser
- Managed Identity eliminates storage account keys in production

### M2: Entra ID Deep-Dive (15 min, Presentation + Demo)

Open the Entra Admin Center and show a pre-configured app registration. Explain the distinction between delegated permissions (scopes) and application permissions (app roles). Demonstrate how the `Evidence.Read` scope grants the SPA permission to call the API on behalf of the user, while app roles like `CaseReader` and `CaseAdmin` control what the user can do within the API.

Key points to emphasize:

- Single-tenant configuration restricts sign-in to the organization's directory (including B2B guests)
- Pre-authorization eliminates consent prompts for first-party apps
- The `roles` claim appears in the access token only after role assignment and a fresh sign-in
- The `scp` claim carries delegated permission scopes

### M3: Exercise 1, Configure App Registrations (30 min, Hands-on)

Direct participants to `workshop/guides/exercise-1-app-registrations.md`. Walk through the first two steps together, then let participants complete the remaining steps independently. Circulate to help with common issues.

Instructor tips:

- Pre-create one complete registration set to use as a reference if participants get stuck
- Verify tenant permissions before the workshop; participants need the Application Developer role at minimum
- The scripted path (`scripts/setup-entra-apps.sh`) serves as a fallback for time-constrained groups

### Break 1 (10 min)

Use this time to verify all participants have valid client IDs and tenant IDs configured. Check that `environment.ts` and `application-dev.properties` contain real values, not placeholders.

### M4: MSAL Angular SPA Walkthrough (15 min, Code Tour)

Open the SPA source code and walk through the MSAL configuration. Highlight:

- `app.config.ts`: `PublicClientApplication` setup with `clientId`, `authority`, and `redirectUri`
- `protectedResourceMap`: URL-to-scope mapping with wildcard pattern (`/api/*` maps to `Evidence.Read`)
- `MsalGuard` on routes that require authentication
- `MsalInterceptor` that attaches Bearer tokens to outgoing HTTP requests automatically
- Login and logout methods using `loginRedirect()` and `logoutRedirect()`

Call attention to the MSAL Angular v5 breaking change: bare base URLs no longer match sub-paths. The `/*` wildcard suffix is required.

### M5: Exercise 2, Run SPA + API Locally (30 min, Hands-on)

Direct participants to `workshop/guides/exercise-2-run-locally.md`. Start the API together in a terminal, verify the 401 response, then let participants complete the SPA steps independently.

Instructor tips:

- If `mvn spring-boot:run` fails, check that Java 17 is on the PATH and `JAVA_HOME` is set correctly
- CORS errors usually mean the SPA origin (`http://localhost:4200`) is missing from the API's allowed origins
- Redirect URI mismatch errors mean the Entra app registration SPA platform URI does not match the actual URL

### M6: API Security and Authorization (15 min, Code Tour)

Open the API source code and walk through the security configuration. Highlight:

- `SecurityConfig.java`: `SecurityFilterChain` bean with JWT resource server configuration
- `requestMatchers()` mapping endpoints to required authorities (`SCOPE_Evidence.Read`, `ROLE_CaseAdmin`)
- `@EnableMethodSecurity` enabling `@PreAuthorize` annotations on controller methods
- JWT audience validation via `spring.security.oauth2.resourceserver.jwt.audiences`
- How Spring Security converts the `roles` claim to `ROLE_` prefixed authorities

### M7: Exercise 3, Add Role-Protected Endpoint (20 min, Hands-on)

Direct participants to `workshop/guides/exercise-3-add-endpoint.md`. This exercise delivers the key RBAC learning moment. Emphasize that the 403-to-201 cycle demonstrates how Entra ID roles propagate through tokens.

Instructor tips:

- Participants will encounter 403 Forbidden and may think something is broken. Reassure them this is expected.
- The most common mistake is forgetting to sign out and sign back in after role assignment. Tokens are cached.
- Solution files are available in `workshop/solutions/exercise-3-solution/` for participants who fall behind.

### Break 2 (5 min)

### M8: Exercise 4, Deploy to Azure with Bicep (20 min, Hands-on)

Direct participants to `workshop/guides/exercise-4-deploy-azure.md`. The Bicep deployment takes 5-10 minutes, so start the deployment early and configure app settings while infrastructure provisions.

Instructor tips:

- Verify participants have Contributor access to their Azure subscription before starting
- The deployment uses B1 App Service Plan (~$14/month); remind participants to delete the resource group after the workshop
- Managed Identity role assignment takes up to 5 minutes to propagate; if evidence download fails immediately after deployment, wait and retry

### M9: Wrap-Up, Pitfalls, and Q&A (15 min, Discussion)

Review what participants built and the security principles demonstrated. Cover common pitfalls and open the floor for questions.

## Common Pitfalls

These issues appear frequently in Entra ID + SPA + API projects. Address them during M9 or when participants encounter them during exercises.

| Pitfall | Symptom | Resolution |
|---------|---------|------------|
| Stale tokens after role change | User assigned a role but still gets 403 | Sign out and sign back in to obtain a fresh token with the updated `roles` claim |
| `protectedResourceMap` mismatch | API calls return 401 even after sign-in | Ensure URLs in the map use `/*` wildcard suffix to match sub-paths (MSAL Angular v5 breaking change) |
| Wrong JWT audience | API rejects valid tokens with "invalid audience" | Verify `spring.security.oauth2.resourceserver.jwt.audiences` matches the API app registration's Application ID URI |
| CORS rejection | Browser console shows CORS errors on API calls | Add `http://localhost:4200` to the API's allowed origins in `SecurityConfig.java` |
| Redirect URI mismatch | Entra ID returns "redirect URI mismatch" error | Ensure the SPA app registration platform URI matches the actual app URL exactly (including port and path) |
| Missing pre-authorization | Users see consent prompt or get 403 on first API call | Pre-authorize the SPA client ID in the API's "Expose an API" settings |
| `JAVA_HOME` not set | Maven build fails with "no compiler" | Set `JAVA_HOME` to the JDK 17 installation directory |
| Managed Identity propagation delay | Evidence download returns 403 from Azure Storage after deployment | Role assignments take up to 5 minutes to propagate; wait and retry |

## Post-Workshop Resources

- [Microsoft identity platform documentation](https://learn.microsoft.com/en-us/entra/identity-platform/)
- [MSAL Angular v5 migration guide](https://github.com/AzureAD/microsoft-authentication-library-for-js/blob/dev/lib/msal-angular/docs/v5-migration.md)
- [Spring Cloud Azure Starter Active Directory documentation](https://learn.microsoft.com/en-us/azure/developer/java/spring-framework/spring-boot-starter-for-azure-active-directory-developer-guide)
- [Azure App Service authentication best practices](https://learn.microsoft.com/en-us/azure/app-service/overview-authentication-authorization)
- [Production hardening guide](../docs/production-hardening.md) in this repository
