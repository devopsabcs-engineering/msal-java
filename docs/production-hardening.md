---
title: Production Hardening Guide
description: Architecture, security posture, and remaining hardening considerations for the MSAL Java Workshop
ms.date: 2026-04-30
ms.topic: how-to
---

## Overview

The workshop deployment ships with a hardened-by-default network and identity posture. There is no public storage, no shared keys, no anonymous blob access, and all evidence I/O flows over a Private Endpoint inside a Virtual Network with Managed Identity + RBAC. This guide explains what the deployment already does and what is still optional for a production rollout (WAF, IP restrictions, multi-region, geo-replication, etc.).

> The previous release of this guide described these controls as future work. They are now part of the default `infra/main.bicep` template.

## Default architecture (what `deploy.ps1` provisions)

```text
                                  ┌────────────────────────────────────────────┐
                                  │  vnet-evidence-workshop (10.20.0.0/16)     │
                                  │                                            │
                                  │  ┌──────────────────────┐                  │
  Internet ─► App Service Front   │  │ snet-app             │                  │
  Door (public hostnames; you ──► │  │ 10.20.1.0/24         │                  │
  can replace with Front Door /   │  │ delegated to         │                  │
  Application Gateway in prod)    │  │ Microsoft.Web/       │                  │
                                  │  │ serverFarms          │                  │
                                  │  │                      │                  │
                                  │  │  ┌──────────────┐    │                  │
                                  │  │  │ App Service  │    │                  │
                                  │  │  │ SPA + API    │    │                  │
                                  │  │  │ (Reg.VNet    │    │                  │
                                  │  │  │  Integration,│    │                  │
                                  │  │  │  WEBSITE_VNET│    │                  │
                                  │  │  │  _ROUTE_ALL=1│    │                  │
                                  │  │  └──────┬───────┘    │                  │
                                  │  └─────────┼────────────┘                  │
                                  │            │                                │
                                  │  ┌─────────▼──────────┐                    │
                                  │  │ snet-pe            │                    │
                                  │  │ 10.20.2.0/24       │                    │
                                  │  │ privateEndpoint    │                    │
                                  │  │ NetworkPolicies =  │                    │
                                  │  │ Disabled           │                    │
                                  │  │                    │                    │
                                  │  │  PE: storage (dfs) │──┐                 │
                                  │  └────────────────────┘  │                 │
                                  │                          │                 │
                                  │  Private DNS zone:       │                 │
                                  │  privatelink.dfs.        │                 │
                                  │  core.windows.net  ◄─────┘                 │
                                  └────────────────────────────────────────────┘
                                                  │
                                                  ▼
                                       ┌────────────────────────┐
                                       │ Storage (HNS-enabled,  │
                                       │ ADLS Gen2)             │
                                       │ allowSharedKeyAccess=  │
                                       │   false                │
                                       │ publicNetworkAccess=   │
                                       │   Disabled             │
                                       │ networkAcls.default=   │
                                       │   Deny                 │
                                       │ allowBlobPublicAccess= │
                                       │   false                │
                                       └────────────────────────┘
```

## Identity & data-plane posture

| Control | Default in `infra/main.bicep` |
| --- | --- |
| Storage authentication | Microsoft Entra ID OAuth (`DefaultAzureCredential` → System-Assigned Managed Identity in App Service). Shared keys are **disabled** at the storage account. |
| Data-lake authorization | `Storage Blob Data Contributor` granted to the API App Service Managed Identity at the storage scope. |
| Storage hierarchical namespace | Enabled (`isHnsEnabled = true`) — full ADLS Gen2 features, `dfs` data-plane endpoint. |
| Storage public endpoint | Disabled (`publicNetworkAccess = Disabled`, `networkAcls.defaultAction = Deny`). |
| Anonymous blob access | Disabled (`allowBlobPublicAccess = false`). |
| Storage data-plane reach | Only via the Private Endpoint NIC in `snet-pe`, resolved through the `privatelink.dfs.<storage-suffix>` Private DNS Zone. |
| API → storage transport | DataLake SDK (`azure-storage-file-datalake`) over HTTPS, target `https://<account>.dfs.<storage-suffix>`. |
| Token version | API app registration patched to `requestedAccessTokenVersion = 2`. JWT issuer = `https://login.microsoftonline.com/<tenant>/v2.0`, audiences = `api://<guid>` and `<guid>`. |
| Identity flow | SPA (auth code + PKCE, MSAL.js v3) → API (Bearer JWT, Spring Security OAuth2 Resource Server) → ADLS Gen2 (MI). |

## App Service VNet integration

Both App Services (SPA + API) are integrated into `snet-app`:

```bicep
properties: {
  virtualNetworkSubnetId: vnet.outputs.appSubnetId
  siteConfig: {
    vnetRouteAllEnabled: true   // route ALL outbound through the VNet
  }
}
appSettings: [
  { name: 'WEBSITE_VNET_ROUTE_ALL', value: '1' }
  { name: 'WEBSITE_DNS_SERVER',     value: '168.63.129.16' }
]
```

This forces the API container's outbound traffic — including `*.dfs.core.windows.net` — through the VNet, where Azure Private DNS resolves the hostname to the Private Endpoint NIC IP. The same path is used by the seed step's CLI uploads only when running from inside the VNet. From the workstation, the deploy script temporarily allow-lists a single IP (see "Seeding pattern" below) and then revokes it.

> The minimum App Service Plan SKU that supports Regional VNet integration is **Standard (S1)**. The workshop default is now `S1` (the plan no longer accepts `B*` SKUs).

## Seeding pattern (no shared keys)

The deploy script handles a chicken-and-egg problem: the storage account is locked down before any data is in it, but sample evidence PDFs need to be uploaded once. It does this safely without ever using a shared key:

1. Detect the deployer's public IP (`api.ipify.org`) and Entra principal objectId (`az ad signed-in-user show`).
2. Deploy Bicep with `deployerIp=<ip>` and `deployerPrincipalId=<oid>`. This:
   * Adds the IP to `networkAcls.ipRules` and flips `publicNetworkAccess = Enabled` (still gated by Deny + a single allow rule).
   * Grants the deployer `Storage Blob Data Contributor` at the storage scope.
3. The seed step uploads sample PDFs with `az storage blob upload-batch --auth-mode login` (OAuth, no keys).
4. The script re-deploys Bicep with `deployerIp=''`. `publicNetworkAccess` flips back to `Disabled`. The IP rule is removed. From here on, only the App Services (via Private Endpoint) can reach storage data.

In a production CI/CD pipeline, replace step 1 with a self-hosted runner inside `snet-app` and skip the IP allow-list entirely.

## Remaining production work (optional)

The defaults are sufficient for an internal pre-prod or a hardened public-facing workload. The following are still left as deliberate choices:

### Web Application Firewall in front of the SPA / API

Both App Services keep their public hostnames so that out-of-VNet developers and end users can reach them. To remove public exposure entirely, add:

* **Azure Front Door (Premium)** with WAF v2 and the OWASP Core Rule Set, plus rate-limit rules.
* **Private Link to App Service** (groupId `sites`) so the App Service is reachable only from the Front Door private origin.
* App Service `publicNetworkAccess = Disabled` and `ipSecurityRestrictionsDefaultAction = Deny` with an allow rule for the Front Door service tag and `x-azure-fdid` header check.

### Outbound IP restrictions

Add `ipSecurityRestrictions` with `defaultAction = Deny` to the SPA App Service if you only want users coming through Front Door / a corporate proxy.

### Multi-region failover

Stand up a second resource group in another region with paired storage (RA-GZRS or paired App Service Plan). Front Door provides the priority/weighted routing and health probes.

### Customer-Managed Keys (CMK)

Replace storage Microsoft-Managed Keys with a key in Azure Key Vault, granted to a User-Assigned Managed Identity that both the storage account and Key Vault trust.

### Defender for Storage

Enable Microsoft Defender for Storage (per-account) for malware scanning and anomalous-access alerts on the evidence container.

### Soft-delete and immutability

For evidence retention, enable container-level immutability policies and blob soft-delete with a 30-day retention.

## Cost comparison

| Component | Workshop default (this template) | Production-plus example |
| --- | --- | --- |
| App Service Plan | S1 Linux (~$70/mo) | P1v3 Linux (~$125/mo) |
| Storage Account (HNS) | Standard_LRS, no egress (~$2/mo) | Standard_GRS + Defender (~$15/mo) |
| Virtual Network | Free | Free |
| Private Endpoint | 1 PE × ~$7.50/mo | 3+ PEs (~$22.50/mo) |
| Private DNS Zone | 1 zone × ~$0.50/mo | 3 zones (~$1.50/mo) |
| Application Insights | Pay-as-you-go (~$2/mo) | Same (~$2/mo) |
| Azure Front Door + WAF | Not deployed | Standard (~$35/mo) + WAF policy (~$5/mo) |
| **Total estimate** | **~$80/mo** | **~$205/mo** |

Costs are approximate and vary by region; Canada Central pricing was used as reference.

## CI/CD considerations

When the App Service SCM endpoint is also placed behind a Private Endpoint (groupId `sites`), the deploy commands here (`az webapp deploy`) cannot reach it from the public internet. Options:

| Option | Complexity | Notes |
| --- | --- | --- |
| Self-hosted runner in `snet-app` | Medium | Deploy a GitHub Actions runner or Azure DevOps agent inside the VNet. The runner reaches PE-protected SCM endpoints directly. |
| Deployment slots + slot swap | Medium | Deploy to a staging slot with temporary public access, then swap into the PE-protected production slot. |
| Azure Deployment Center | Low | Pull-based; the App Service polls a connected repo. |
| Hybrid Connections | Low | Azure Relay tunnel between an on-prem agent and App Service. |

The workshop's `deploy.ps1` keeps the SCM endpoint public so it works from a developer workstation; harden this last in the production migration.
