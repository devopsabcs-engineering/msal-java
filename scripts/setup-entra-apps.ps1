<#
.SYNOPSIS
    Creates (or updates) Entra ID app registrations for the Evidence Portal workshop.

.DESCRIPTION
    Idempotent one-stop bootstrap. Creates two app registrations:
      1. API app (resource server) with Application ID URI api://<appId>
      2. SPA app (public client) with the SPA platform redirect URI configured

    Re-running the script with the same names will reuse the existing apps
    instead of creating duplicates.

    All Microsoft Graph calls go through Invoke-RestMethod using a token
    obtained from the Azure CLI. This is the foundation for upcoming Graph
    API extensions (scopes, app roles, pre-authorization, admin consent).

.PARAMETER SpaName
    Display name for the SPA app registration.

.PARAMETER ApiName
    Display name for the API app registration.

.PARAMETER RedirectUri
    SPA redirect URI. Defaults to http://localhost:4200.

.PARAMETER OutputFile
    Optional path to write a JSON file containing the resulting IDs.

.EXAMPLE
    ./scripts/setup-entra-apps.ps1 -SpaName "Evidence Portal SPA" -ApiName "Evidence Portal API"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SpaName,

    [Parameter(Mandatory = $true)]
    [string]$ApiName,

    [string]$RedirectUri = 'http://localhost:4200',

    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'

$script:GraphRoot = 'https://graph.microsoft.com/v1.0'
$script:GraphHeaders = $null

# ---------------------------------------------------------------------------
# Auth / prerequisites
# ---------------------------------------------------------------------------

function Test-Prerequisites {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        throw 'Azure CLI (az) is not installed. Install from https://aka.ms/install-azure-cli'
    }

    $accountJson = az account show 2>$null
    if (-not $accountJson) {
        throw "Not logged in to Azure CLI. Run 'az login' first."
    }

    return ($accountJson | ConvertFrom-Json)
}

function Initialize-GraphHeaders {
    Write-Host '==> Acquiring Microsoft Graph access token...'
    $token = az account get-access-token `
        --resource 'https://graph.microsoft.com' `
        --query accessToken -o tsv

    if (-not $token) {
        throw 'Failed to acquire Microsoft Graph access token.'
    }

    $script:GraphHeaders = @{
        Authorization  = "Bearer $token"
        'Content-Type' = 'application/json'
    }
}

function Invoke-Graph {
    param(
        [Parameter(Mandatory = $true)] [string]$Method,
        [Parameter(Mandatory = $true)] [string]$Path,
        [object]$Body
    )

    $uri = if ($Path -like 'http*') { $Path } else { "$script:GraphRoot$Path" }
    $params = @{
        Method  = $Method
        Uri     = $uri
        Headers = $script:GraphHeaders
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }

    return Invoke-RestMethod @params
}

# ---------------------------------------------------------------------------
# App registration helpers
# ---------------------------------------------------------------------------

function Get-AppByDisplayName {
    param([Parameter(Mandatory = $true)] [string]$DisplayName)

    $escaped = $DisplayName.Replace("'", "''")
    $encoded = [System.Uri]::EscapeDataString("displayName eq '$escaped'")
    $resp = Invoke-Graph -Method GET -Path "/applications?`$filter=$encoded&`$select=id,appId,displayName,identifierUris,spa"

    $found = @($resp.value)
    if ($found.Count -gt 1) {
        throw "Found $($found.Count) app registrations named '$DisplayName'. Resolve the duplicate before re-running."
    }

    return $found | Select-Object -First 1
}

function New-OrGetAppRegistration {
    param(
        [Parameter(Mandatory = $true)] [string]$DisplayName
    )

    $existing = Get-AppByDisplayName -DisplayName $DisplayName
    if ($existing) {
        Write-Host "==> Reusing existing app registration: $DisplayName"
        Write-Host "    objectId: $($existing.id)"
        Write-Host "    appId:    $($existing.appId)"
        return $existing
    }

    Write-Host "==> Creating app registration: $DisplayName"
    $body = @{
        displayName    = $DisplayName
        signInAudience = 'AzureADMyOrg'
    }
    $created = Invoke-Graph -Method POST -Path '/applications' -Body $body
    Write-Host "    objectId: $($created.id)"
    Write-Host "    appId:    $($created.appId)"
    return $created
}

function Set-ApiIdentifierUri {
    param(
        [Parameter(Mandatory = $true)] [string]$ObjectId,
        [Parameter(Mandatory = $true)] [string]$AppId,
        [object[]]$CurrentIdentifierUris
    )

    $identifierUri = "api://$AppId"
    if ($CurrentIdentifierUris -and ($CurrentIdentifierUris -contains $identifierUri)) {
        Write-Host "    Identifier URI already set: $identifierUri"
        return $identifierUri
    }

    Write-Host "==> Setting API Identifier URI: $identifierUri"
    Invoke-Graph -Method PATCH -Path "/applications/$ObjectId" -Body @{
        identifierUris = @($identifierUri)
    } | Out-Null

    return $identifierUri
}

function Set-SpaRedirectUri {
    param(
        [Parameter(Mandatory = $true)] [string]$ObjectId,
        [Parameter(Mandatory = $true)] [string]$RedirectUri,
        [object]$CurrentSpa
    )

    $current = @()
    if ($CurrentSpa -and $CurrentSpa.redirectUris) {
        $current = @($CurrentSpa.redirectUris)
    }

    if ($current -contains $RedirectUri) {
        Write-Host "    SPA redirect URI already configured: $RedirectUri"
        return
    }

    $merged = @($current + $RedirectUri | Select-Object -Unique)
    Write-Host "==> Configuring SPA platform redirect URI: $RedirectUri"
    Invoke-Graph -Method PATCH -Path "/applications/$ObjectId" -Body @{
        spa = @{ redirectUris = $merged }
    } | Out-Null
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host '==> Checking prerequisites...'
$account = Test-Prerequisites
$tenantId = $account.tenantId
Write-Host "    Tenant ID: $tenantId"

Initialize-GraphHeaders

# --- API app ---
$apiApp = New-OrGetAppRegistration -DisplayName $ApiName
$identifierUri = Set-ApiIdentifierUri `
    -ObjectId $apiApp.id `
    -AppId $apiApp.appId `
    -CurrentIdentifierUris $apiApp.identifierUris

# --- SPA app ---
$spaApp = New-OrGetAppRegistration -DisplayName $SpaName
Set-SpaRedirectUri `
    -ObjectId $spaApp.id `
    -RedirectUri $RedirectUri `
    -CurrentSpa $spaApp.spa

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$result = [ordered]@{
    tenantId      = $tenantId
    apiAppId      = $apiApp.appId
    apiObjectId   = $apiApp.id
    apiName       = $ApiName
    identifierUri = $identifierUri
    spaAppId      = $spaApp.appId
    spaObjectId   = $spaApp.id
    spaName       = $SpaName
    redirectUri   = $RedirectUri
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' Entra ID App Registrations Ready'
Write-Host '============================================================'
$result.GetEnumerator() | ForEach-Object {
    Write-Host (' {0,-15} {1}' -f "$($_.Key):", $_.Value)
}
Write-Host '============================================================'
Write-Host ''
Write-Host ' Next steps (to be implemented via Graph API):'
Write-Host '   - Expose API scope (e.g. Evidence.Read)'
Write-Host '   - Define app roles (e.g. CaseReader, CaseAdmin)'
Write-Host '   - Add delegated permission on SPA for the API scope'
Write-Host '   - Pre-authorize the SPA on the API'
Write-Host '   - Grant admin consent'
Write-Host ''

if ($OutputFile) {
    $result | ConvertTo-Json | Set-Content -Path $OutputFile -Encoding UTF8
    Write-Host "Wrote results to $OutputFile"
}

return [pscustomobject]$result
