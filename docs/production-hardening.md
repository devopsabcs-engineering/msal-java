---
title: Production Hardening Guide
description: Architecture and configuration guidance for securing the MSAL Java Workshop deployment with Private Endpoints, VNet integration, and DNS zones
ms.date: 2026-04-20
ms.topic: how-to
---

## Overview

The workshop deployment uses a simplified infrastructure optimized for learning: a B1 Basic App Service Plan with public endpoints and no network isolation. This keeps costs low (~$14/month) and deployment fast, letting participants focus on authentication concepts rather than infrastructure complexity.

A production deployment requires stronger network isolation, private connectivity, and defense-in-depth security. This guide covers the changes needed to harden the workshop architecture for production use.

## Architecture

The production architecture places all resources behind a Virtual Network with Private Endpoints, eliminating public internet exposure for the API, SPA hosting, and storage.

```text
                        ┌─────────────────────────────────────────────────┐
                        │                   Azure VNet                    │
                        │                  10.0.0.0/16                    │
                        │                                                 │
  Internet ──► Azure    │  ┌─────────────────────┐ ┌──────────────────┐  │
  Traffic      Front    │  │ snet-integration     │ │ snet-private-    │  │
               Door /   │  │ 10.0.1.0/27          │ │ endpoints        │  │
               App GW ──┤  │                      │ │ 10.0.2.0/27      │  │
                        │  │  ┌──────────────┐    │ │                  │  │
                        │  │  │ App Service   │    │ │ ┌──── PE: SPA   │  │
                        │  │  │ VNet          │────┤ │ ├──── PE: API   │  │
                        │  │  │ Integration   │    │ │ └──── PE: Blob  │  │
                        │  │  └──────────────┘    │ │                  │  │
                        │  └─────────────────────┘ └──────────────────┘  │
                        │                                                 │
                        │  Private DNS Zones:                             │
                        │  - privatelink.azurewebsites.net                │
                        │  - privatelink.blob.core.windows.net            │
                        └─────────────────────────────────────────────────┘
```

## VNet Configuration

Create a VNet with two dedicated subnets. Each subnet requires a minimum /27 address space (32 addresses).

| Subnet | Name | Address Range | Purpose |
|---|---|---|---|
| Integration | `snet-integration` | 10.0.1.0/27 | App Service VNet Integration (outbound traffic) |
| Private Endpoints | `snet-private-endpoints` | 10.0.2.0/27 | Private Endpoint NICs for Storage and App Services |

The integration subnet must be delegated to `Microsoft.Web/serverFarms`. The private endpoints subnet requires no delegation but must have `privateEndpointNetworkPolicies` set to `Disabled`.

## Private Endpoints

Private Endpoints assign a private IP address from the VNet to each resource, replacing public DNS resolution. Traffic between resources stays within the Azure backbone.

### Required Private Endpoints

| Resource | Sub-resource | Private DNS Zone |
|---|---|---|
| Storage Account | `blob` | `privatelink.blob.core.windows.net` |
| App Service (SPA) | `sites` | `privatelink.azurewebsites.net` |
| App Service (API) | `sites` | `privatelink.azurewebsites.net` |

### App Service VNet Routing

Enable `vnetRouteAllEnabled: true` on both App Services. Without this setting, only RFC 1918 traffic routes through the VNet, and calls to Azure services (including Storage) continue over public endpoints.

```bicep
resource apiAppSettings 'Microsoft.Web/sites/config@2023-12-01' = {
  name: 'web'
  parent: apiApp
  properties: {
    vnetRouteAllEnabled: true
  }
}
```

## Private DNS Zones

Private DNS Zones override public DNS resolution so that resource FQDNs resolve to private IP addresses within the VNet.

### Required Zones

| DNS Zone | Records | Linked To |
|---|---|---|
| `privatelink.azurewebsites.net` | A records for SPA and API App Services | VNet |
| `privatelink.blob.core.windows.net` | A record for Storage Account blob endpoint | VNet |

Each Private Endpoint automatically creates an A record in its associated Private DNS Zone. Link each zone to the VNet to enable name resolution from resources within the network.

## App Service Plan Upgrade

VNet Integration with Private Endpoints requires a PremiumV3 plan or higher. The workshop's B1 Basic plan does not support these features.

| Plan | SKU | VNet Integration | Private Endpoints | Estimated Monthly Cost |
|---|---|---|---|---|
| Basic B1 (workshop) | B1 | No | No | ~$14 |
| PremiumV3 | P1V3 | Yes | Yes | ~$125 |

The cost increase is significant. Evaluate whether your workload justifies the network isolation, or consider alternative architectures (Azure Container Apps, AKS) if you need cost-effective VNet support.

## Additional Security Measures

### Disable Public Network Access on Storage

After configuring Private Endpoints, disable public network access on the Storage Account:

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  // ...existing properties
  properties: {
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
    }
  }
}
```

### IP Restrictions on App Services

Restrict inbound traffic to the VNet and any required management IPs:

- Deny all public traffic by default
- Allow traffic from the VNet integration subnet
- Allow Azure Front Door or Application Gateway health probes if using a WAF

### Web Application Firewall

Place Azure Front Door (recommended) or Application Gateway with WAF v2 in front of the App Services for:

- OWASP rule set protection against common web attacks
- DDoS protection at the edge
- SSL/TLS termination with managed certificates
- Geographic filtering and rate limiting

## CI/CD Considerations

When App Service SCM sites are behind Private Endpoints, standard deployment commands (`az webapp deploy`, GitHub Actions `azure/webapps-deploy`) fail because the deployment endpoint is not publicly reachable.

### Deployment Options

| Option | Complexity | Description |
|---|---|---|
| Self-hosted runners in VNet | Medium | Deploy a GitHub Actions runner (or Azure DevOps agent) inside the VNet. The runner can reach PE-protected SCM endpoints directly. |
| Deployment slots with VNet swap | Medium | Deploy to a staging slot with temporary public access, then swap into the PE-protected production slot. |
| Azure Deployment Center | Low | Use App Service Deployment Center with a connected repository for pull-based deployments. |
| Hybrid Connections | Low | Use Azure Relay Hybrid Connections for connectivity without full VNet deployment infrastructure. |

Self-hosted runners provide the most control and align with enterprise CI/CD patterns. For the workshop context, Deployment Center offers the lowest friction.

## Cost Comparison

| Component | Workshop | Production |
|---|---|---|
| App Service Plan | B1 (~$14/mo) | P1V3 (~$125/mo) |
| Private Endpoints | None | 3 PEs (~$7.50/mo each) |
| Private DNS Zones | None | 2 zones (~$0.50/mo each) |
| Azure Front Door | None | Standard (~$35/mo) |
| **Total Estimate** | **~$14/mo** | **~$183/mo** |

Costs are approximate and vary by region. Canada Central pricing used as reference.
