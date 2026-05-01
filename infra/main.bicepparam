// ---------------------------------------------------------------------------
// main.bicepparam — Default parameters for the Evidence Portal infrastructure.
//
// IMPORTANT: deploy.ps1 overrides storageAccountName, spaClientId, apiClientId,
// tenantId, deployerIp, and deployerPrincipalId via --parameters key=value.
// The placeholder values below are only used when running
// `az deployment group create --parameters main.bicepparam` directly.
// Replace them or pass overrides on the command line.
// ---------------------------------------------------------------------------

using './main.bicep'

param environmentName  = 'workshop'
param location         = 'canadacentral'
// S1 (Standard) is the cheapest SKU that supports Regional VNet integration.
param appServicePlanSku = 'S1'

// Override these on the CLI: --parameters storageAccountName=... spaClientId=... etc.
param storageAccountName = 'REPLACEME'
param spaClientId        = '00000000-0000-0000-0000-000000000000'
param apiClientId        = '00000000-0000-0000-0000-000000000000'
param tenantId           = '00000000-0000-0000-0000-000000000000'

// Optional — only set during initial seeding to allow a single deployer IP
// through the storage networkAcls (the account otherwise has
// publicNetworkAccess = Disabled). Leave empty in steady state.
param deployerIp           = ''
param deployerPrincipalId  = ''
param deployerPrincipalType = 'User'
