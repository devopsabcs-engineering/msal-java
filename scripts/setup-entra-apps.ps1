<#
.SYNOPSIS
    One-stop, idempotent Entra ID setup for the Evidence Portal workshop.

.DESCRIPTION
    Performs every Entra ID configuration step needed to take the workshop
    from zero to a working sign-in:

      1. Verifies az CLI / login.
      2. Acquires a Microsoft Graph token (Invoke-RestMethod).
      3. Creates or reuses the API app registration with api://<appId> URI.
      4. Exposes the Evidence.Read OAuth2 scope on the API.
      5. Defines the CaseReader and CaseAdmin app roles on the API.
      6. Creates or reuses the SPA app registration with SPA redirect URI.
      7. Adds the Evidence.Read delegated permission to the SPA.
      8. Pre-authorizes the SPA on the API for Evidence.Read.
      9. Ensures both apps have service principals.
     10. Grants tenant admin consent for Evidence.Read on the SPA SP
         (requires Global Admin / Privileged Role Admin / Cloud App Admin).
     11. Self-assigns the current signed-in user to the CaseAdmin app role
         on the API service principal.
     12. Patches local environment.ts / environment.prod.ts / application.properties
         placeholders with the real IDs.
     13. Optionally adds a production SPA redirect URI (used by deploy.ps1
         after the App Service URL is known).

    Re-running is safe: every step looks up state first and only mutates
    when the desired state is missing.

.PARAMETER SpaName
    Display name for the SPA app registration.

.PARAMETER ApiName
    Display name for the API app registration.

.PARAMETER RedirectUri
    Local SPA redirect URI. Defaults to http://localhost:4200.

.PARAMETER ProductionRedirectUri
    Optional additional SPA redirect URI for the deployed App Service
    (e.g. https://app-evidence-spa-workshop.azurewebsites.net).

.PARAMETER ApiScopeName
    Name of the OAuth2 scope to expose on the API. Default: Evidence.Read.

.PARAMETER GrantAdminConsent
    Grant tenant admin consent for the API scope on the SPA service principal.
    Requires elevated tenant rights. Default: true.

.PARAMETER AssignCurrentUserToRoles
    Assign the currently signed-in user to the CaseAdmin and CaseReader
    app roles on the API service principal. Default: true.

.PARAMETER UpdateLocalConfig
    Patch local environment.ts, environment.prod.ts, and application.properties
    with the real client IDs / tenant ID. Default: true.

.PARAMETER OutputFile
    Optional path to write the resulting IDs as JSON.

.EXAMPLE
    ./scripts/setup-entra-apps.ps1 -SpaName "Evidence Portal SPA" -ApiName "Evidence Portal API"

.EXAMPLE
    # After deploy.ps1 has provisioned the App Service, register its URL too.
    ./scripts/setup-entra-apps.ps1 `
        -SpaName "Evidence Portal SPA" `
        -ApiName "Evidence Portal API" `
        -ProductionRedirectUri "https://app-evidence-spa-workshop.azurewebsites.net"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string]$SpaName,
    [Parameter(Mandatory = $true)] [string]$ApiName,

    [string]$RedirectUri = 'http://localhost:4200',
    [string]$ProductionRedirectUri,
    [string]$ApiScopeName = 'Evidence.Read',

    [bool]$GrantAdminConsent        = $true,
    [bool]$AssignCurrentUserToRoles = $true,
    [bool]$UpdateLocalConfig        = $true,

    [string]$OutputFile
)

$ErrorActionPreference = 'Stop'

$script:GraphRoot    = 'https://graph.microsoft.com/v1.0'
$script:GraphHeaders = $null
$script:RepoRoot     = Split-Path -Parent $PSScriptRoot

# Stable role/scope value strings so we can find the existing entries
# regardless of GUID assignment from a previous run.
$script:RoleReaderValue = 'CaseReader'
$script:RoleAdminValue  = 'CaseAdmin'

# ---------------------------------------------------------------------------
# Auth / Graph helpers
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
    if (-not $token) { throw 'Failed to acquire Microsoft Graph access token.' }
    $script:GraphHeaders = @{
        Authorization  = "Bearer $token"
        'Content-Type' = 'application/json'
    }
}

function Invoke-Graph {
    param(
        [Parameter(Mandatory = $true)] [string]$Method,
        [Parameter(Mandatory = $true)] [string]$Path,
        [object]$Body,
        [switch]$IgnoreNotFound
    )
    $uri = if ($Path -like 'http*') { $Path } else { "$script:GraphRoot$Path" }
    $params = @{ Method = $Method; Uri = $uri; Headers = $script:GraphHeaders }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10 -Compress)
    }
    try {
        return Invoke-RestMethod @params
    } catch {
        if ($IgnoreNotFound -and $_.Exception.Response.StatusCode.value__ -eq 404) {
            return $null
        }
        throw
    }
}

function Get-GraphSelf {
    return Invoke-Graph -Method GET -Path '/me?$select=id,userPrincipalName,displayName'
}

# ---------------------------------------------------------------------------
# App registration discovery / creation
# ---------------------------------------------------------------------------

function Get-AppByDisplayName {
    param([Parameter(Mandatory = $true)] [string]$DisplayName)
    $escaped = $DisplayName.Replace("'", "''")
    $encoded = [System.Uri]::EscapeDataString("displayName eq '$escaped'")
    $select  = 'id,appId,displayName,identifierUris,spa,api,appRoles,requiredResourceAccess'
    $resp = Invoke-Graph -Method GET -Path "/applications?`$filter=$encoded&`$select=$select"
    $found = @($resp.value)
    if ($found.Count -gt 1) {
        throw "Found $($found.Count) app registrations named '$DisplayName'. Resolve the duplicate before re-running."
    }
    return $found | Select-Object -First 1
}

function Get-AppById {
    param([Parameter(Mandatory = $true)] [string]$ObjectId)
    return Invoke-Graph -Method GET -Path "/applications/$ObjectId"
}

function New-OrGetAppRegistration {
    param([Parameter(Mandatory = $true)] [string]$DisplayName)
    $existing = Get-AppByDisplayName -DisplayName $DisplayName
    if ($existing) {
        Write-Host "==> Reusing app registration: $DisplayName"
        Write-Host "    objectId: $($existing.id)"
        Write-Host "    appId:    $($existing.appId)"
        return $existing
    }
    Write-Host "==> Creating app registration: $DisplayName"
    $created = Invoke-Graph -Method POST -Path '/applications' -Body @{
        displayName    = $DisplayName
        signInAudience = 'AzureADMyOrg'
    }
    Write-Host "    objectId: $($created.id)"
    Write-Host "    appId:    $($created.appId)"
    return $created
}

# ---------------------------------------------------------------------------
# API: identifier URI / scope / roles
# ---------------------------------------------------------------------------

function Set-ApiIdentifierUri {
    param(
        [Parameter(Mandatory = $true)] [string]$ObjectId,
        [Parameter(Mandatory = $true)] [string]$AppId,
        [object[]]$CurrentIdentifierUris
    )
    $uri = "api://$AppId"
    if ($CurrentIdentifierUris -and ($CurrentIdentifierUris -contains $uri)) {
        Write-Host "    Identifier URI already set: $uri"
        return $uri
    }
    Write-Host "==> Setting API Identifier URI: $uri"
    Invoke-Graph -Method PATCH -Path "/applications/$ObjectId" -Body @{
        identifierUris = @($uri)
    } | Out-Null
    return $uri
}

function Set-ApiOAuth2Scope {
    param(
        [Parameter(Mandatory = $true)] [string]$ObjectId,
        [Parameter(Mandatory = $true)] [string]$ScopeName
    )
    $app = Get-AppById -ObjectId $ObjectId
    $existing = @()
    if ($app.api -and $app.api.oauth2PermissionScopes) {
        $existing = @($app.api.oauth2PermissionScopes)
    }
    $match = $existing | Where-Object { $_.value -eq $ScopeName } | Select-Object -First 1
    if ($match) {
        Write-Host "    OAuth2 scope already exists: $ScopeName ($($match.id))"
        return $match.id
    }
    $scopeId = [guid]::NewGuid().ToString()
    $scope = @{
        id                      = $scopeId
        adminConsentDescription = "Allow the application to read evidence data on behalf of the signed-in user"
        adminConsentDisplayName = "Read evidence data"
        isEnabled               = $true
        type                    = 'User'
        userConsentDescription  = "Allow the application to read evidence data on your behalf"
        userConsentDisplayName  = "Read evidence data"
        value                   = $ScopeName
    }
    $merged = @($existing + $scope)
    Write-Host "==> Exposing OAuth2 scope on API: $ScopeName"
    Invoke-Graph -Method PATCH -Path "/applications/$ObjectId" -Body @{
        api = @{ oauth2PermissionScopes = $merged }
    } | Out-Null
    return $scopeId
}

function Set-ApiAccessTokenVersion2 {
    <#
        Forces the API app registration to issue v2.0 access tokens. Without this,
        the default value (1) means MSAL.js (which is v2-only) requests a v2 token
        but receives a v1-format token whose 'iss' is https://sts.windows.net/<tid>/
        rather than https://login.microsoftonline.com/<tid>/v2.0 — causing Spring
        Security's JWT issuer-uri validation to reject every request with 401.
    #>
    param([Parameter(Mandatory = $true)] [string]$ObjectId)
    $app = Get-AppById -ObjectId $ObjectId
    $current = $null
    if ($app.api) { $current = $app.api.requestedAccessTokenVersion }
    if ($current -eq 2) {
        Write-Host '    requestedAccessTokenVersion already set to 2'
        return
    }
    Write-Host "==> Setting API requestedAccessTokenVersion to 2 (current: $current)"
    $api = @{}
    if ($app.api) {
        $api.oauth2PermissionScopes = $app.api.oauth2PermissionScopes
        $api.knownClientApplications = $app.api.knownClientApplications
        $api.preAuthorizedApplications = $app.api.preAuthorizedApplications
    }
    $api.requestedAccessTokenVersion = 2
    Invoke-Graph -Method PATCH -Path "/applications/$ObjectId" -Body @{ api = $api } | Out-Null
}

function Set-ApiAppRoles {
    param([Parameter(Mandatory = $true)] [string]$ObjectId)

    $app = Get-AppById -ObjectId $ObjectId
    $existing = @()
    if ($app.appRoles) { $existing = @($app.appRoles) }

    $reader = $existing | Where-Object { $_.value -eq $script:RoleReaderValue } | Select-Object -First 1
    $admin  = $existing | Where-Object { $_.value -eq $script:RoleAdminValue }  | Select-Object -First 1

    $changed = $false
    if (-not $reader) {
        $reader = @{
            id                 = [guid]::NewGuid().ToString()
            allowedMemberTypes = @('User')
            description        = 'Can read cases and download evidence files'
            displayName        = 'Case Reader'
            isEnabled          = $true
            value              = $script:RoleReaderValue
        }
        $existing += $reader
        $changed = $true
    }
    if (-not $admin) {
        $admin = @{
            id                 = [guid]::NewGuid().ToString()
            allowedMemberTypes = @('User')
            description        = 'Can read, create, and manage cases and evidence files'
            displayName        = 'Case Admin'
            isEnabled          = $true
            value              = $script:RoleAdminValue
        }
        $existing += $admin
        $changed = $true
    }

    if ($changed) {
        Write-Host "==> Defining app roles on API: $($script:RoleReaderValue), $($script:RoleAdminValue)"
        Invoke-Graph -Method PATCH -Path "/applications/$ObjectId" -Body @{
            appRoles = $existing
        } | Out-Null
    } else {
        Write-Host "    App roles already defined: $($script:RoleReaderValue), $($script:RoleAdminValue)"
    }

    return [pscustomobject]@{
        ReaderId = $reader.id
        AdminId  = $admin.id
    }
}

# ---------------------------------------------------------------------------
# SPA: redirect URI / required resource access
# ---------------------------------------------------------------------------

function Set-SpaRedirectUris {
    param(
        [Parameter(Mandatory = $true)] [string]$ObjectId,
        [Parameter(Mandatory = $true)] [string[]]$DesiredRedirectUris,
        [object]$CurrentSpa
    )
    $current = @()
    if ($CurrentSpa -and $CurrentSpa.redirectUris) { $current = @($CurrentSpa.redirectUris) }
    $missing = $DesiredRedirectUris | Where-Object { $_ -and ($current -notcontains $_) }
    if (-not $missing) {
        Write-Host "    SPA redirect URIs already configured: $($DesiredRedirectUris -join ', ')"
        return
    }
    $merged = @($current + $missing | Select-Object -Unique)
    Write-Host "==> Configuring SPA redirect URIs: $($merged -join ', ')"
    Invoke-Graph -Method PATCH -Path "/applications/$ObjectId" -Body @{
        spa = @{ redirectUris = $merged }
    } | Out-Null
}

function Set-SpaRequiredResourceAccess {
    param(
        [Parameter(Mandatory = $true)] [string]$SpaObjectId,
        [Parameter(Mandatory = $true)] [string]$ApiAppId,
        [Parameter(Mandatory = $true)] [string]$ScopeId
    )
    $spa = Get-AppById -ObjectId $SpaObjectId
    $rra = @()
    if ($spa.requiredResourceAccess) { $rra = @($spa.requiredResourceAccess) }

    $entry = $rra | Where-Object { $_.resourceAppId -eq $ApiAppId } | Select-Object -First 1
    $hasScope = $false
    if ($entry -and $entry.resourceAccess) {
        $hasScope = ($entry.resourceAccess | Where-Object { $_.id -eq $ScopeId -and $_.type -eq 'Scope' }).Count -gt 0
    }

    if ($entry -and $hasScope) {
        Write-Host "    SPA already has delegated permission for scope $ScopeId on $ApiAppId"
        return
    }

    if (-not $entry) {
        $entry = @{
            resourceAppId  = $ApiAppId
            resourceAccess = @(@{ id = $ScopeId; type = 'Scope' })
        }
        $rra += $entry
    } else {
        $entry.resourceAccess = @($entry.resourceAccess + @{ id = $ScopeId; type = 'Scope' })
    }

    Write-Host "==> Adding delegated API permission to SPA"
    Invoke-Graph -Method PATCH -Path "/applications/$SpaObjectId" -Body @{
        requiredResourceAccess = $rra
    } | Out-Null
}

# ---------------------------------------------------------------------------
# API: pre-authorize SPA
# ---------------------------------------------------------------------------

function Set-ApiPreAuthorizedSpa {
    param(
        [Parameter(Mandatory = $true)] [string]$ApiObjectId,
        [Parameter(Mandatory = $true)] [string]$SpaAppId,
        [Parameter(Mandatory = $true)] [string]$ScopeId
    )
    $api = Get-AppById -ObjectId $ApiObjectId
    $preAuth = @()
    if ($api.api -and $api.api.preAuthorizedApplications) {
        $preAuth = @($api.api.preAuthorizedApplications)
    }
    $entry = $preAuth | Where-Object { $_.appId -eq $SpaAppId } | Select-Object -First 1
    $hasScope = $false
    if ($entry) {
        $hasScope = $entry.delegatedPermissionIds -and ($entry.delegatedPermissionIds -contains $ScopeId)
    }
    if ($entry -and $hasScope) {
        Write-Host "    SPA already pre-authorized on API for scope $ScopeId"
        return
    }
    if (-not $entry) {
        $preAuth += @{ appId = $SpaAppId; delegatedPermissionIds = @($ScopeId) }
    } else {
        $entry.delegatedPermissionIds = @($entry.delegatedPermissionIds + $ScopeId | Select-Object -Unique)
    }

    # Build full api object preserving scopes.
    $apiBlock = @{
        oauth2PermissionScopes        = @($api.api.oauth2PermissionScopes)
        preAuthorizedApplications     = $preAuth
        requestedAccessTokenVersion   = $api.api.requestedAccessTokenVersion
        acceptMappedClaims            = $api.api.acceptMappedClaims
        knownClientApplications       = $api.api.knownClientApplications
    }
    # Remove null fields Graph rejects.
    $clean = @{}
    foreach ($k in $apiBlock.Keys) { if ($null -ne $apiBlock[$k]) { $clean[$k] = $apiBlock[$k] } }

    Write-Host "==> Pre-authorizing SPA on API for scope $ScopeId"
    Invoke-Graph -Method PATCH -Path "/applications/$ApiObjectId" -Body @{ api = $clean } | Out-Null
}

# ---------------------------------------------------------------------------
# Service principals / consent / role assignment
# ---------------------------------------------------------------------------

function New-OrGetServicePrincipal {
    param([Parameter(Mandatory = $true)] [string]$AppId)
    $encoded = [System.Uri]::EscapeDataString("appId eq '$AppId'")
    $resp = Invoke-Graph -Method GET -Path "/servicePrincipals?`$filter=$encoded&`$select=id,appId,displayName"
    $sp = @($resp.value) | Select-Object -First 1
    if ($sp) { return $sp }
    Write-Host "==> Creating service principal for appId $AppId"
    return Invoke-Graph -Method POST -Path '/servicePrincipals' -Body @{ appId = $AppId }
}

function Grant-OAuth2AdminConsent {
    param(
        [Parameter(Mandatory = $true)] [string]$ClientSpId,    # SPA service principal
        [Parameter(Mandatory = $true)] [string]$ResourceSpId,  # API service principal
        [Parameter(Mandatory = $true)] [string]$ScopeName
    )
    $resp = Invoke-Graph -Method GET `
        -Path "/oauth2PermissionGrants?`$filter=clientId eq '$ClientSpId' and resourceId eq '$ResourceSpId' and consentType eq 'AllPrincipals'"
    $existing = @($resp.value) | Select-Object -First 1
    if ($existing) {
        $scopes = ($existing.scope -split ' ')
        if ($scopes -contains $ScopeName) {
            Write-Host "    Admin consent already granted for $ScopeName"
            return
        }
        Write-Host "==> Updating existing admin consent grant to include $ScopeName"
        $newScopes = (($scopes + $ScopeName) | Where-Object { $_ } | Sort-Object -Unique) -join ' '
        Invoke-Graph -Method PATCH -Path "/oauth2PermissionGrants/$($existing.id)" -Body @{ scope = $newScopes } | Out-Null
        return
    }
    Write-Host "==> Granting tenant admin consent for $ScopeName"
    Invoke-Graph -Method POST -Path '/oauth2PermissionGrants' -Body @{
        clientId    = $ClientSpId
        consentType = 'AllPrincipals'
        principalId = $null
        resourceId  = $ResourceSpId
        scope       = $ScopeName
    } | Out-Null
}

function Add-AppRoleAssignmentToUser {
    param(
        [Parameter(Mandatory = $true)] [string]$UserObjectId,
        [Parameter(Mandatory = $true)] [string]$ResourceSpId,
        [Parameter(Mandatory = $true)] [string]$AppRoleId,
        [Parameter(Mandatory = $true)] [string]$RoleValueLabel
    )
    $resp = Invoke-Graph -Method GET -Path "/users/$UserObjectId/appRoleAssignments"
    $existing = @($resp.value) | Where-Object {
        $_.resourceId -eq $ResourceSpId -and $_.appRoleId -eq $AppRoleId
    }
    if ($existing) {
        Write-Host "    User already assigned to role: $RoleValueLabel"
        return
    }
    Write-Host "==> Assigning current user to role: $RoleValueLabel"
    Invoke-Graph -Method POST -Path "/users/$UserObjectId/appRoleAssignments" -Body @{
        principalId = $UserObjectId
        resourceId  = $ResourceSpId
        appRoleId   = $AppRoleId
    } | Out-Null
}

# ---------------------------------------------------------------------------
# Local config patching
# ---------------------------------------------------------------------------

function Update-LocalConfigFiles {
    param(
        [Parameter(Mandatory = $true)] [string]$TenantId,
        [Parameter(Mandatory = $true)] [string]$SpaClientId,
        [Parameter(Mandatory = $true)] [string]$ApiClientId
    )

    $envDev  = Join-Path $script:RepoRoot 'sample-app/spa/src/environments/environment.ts'
    $envProd = Join-Path $script:RepoRoot 'sample-app/spa/src/environments/environment.prod.ts'
    $appProp = Join-Path $script:RepoRoot 'sample-app/api/src/main/resources/application.properties'

    foreach ($file in @($envDev, $envProd)) {
        if (-not (Test-Path $file)) { continue }
        Write-Host "==> Patching $($file -replace [regex]::Escape($script:RepoRoot + [IO.Path]::DirectorySeparatorChar), '')"
        $content = Get-Content -LiteralPath $file -Raw
        $orig = $content
        $content = $content -replace 'YOUR_SPA_CLIENT_ID', $SpaClientId
        $content = $content -replace 'YOUR_TENANT_ID',     $TenantId
        $content = $content -replace 'YOUR_API_CLIENT_ID', $ApiClientId
        if ($content -ne $orig) {
            Set-Content -LiteralPath $file -Value $content -Encoding UTF8 -NoNewline
            Write-Host '    Updated client/tenant placeholders'
        } else {
            Write-Host '    Already populated (no placeholders found)'
        }
    }

    if (Test-Path $appProp) {
        Write-Host "==> Patching sample-app/api/src/main/resources/application.properties"
        $content = Get-Content -LiteralPath $appProp -Raw
        $orig = $content
        $content = $content -replace 'YOUR_API_CLIENT_ID', $ApiClientId
        if ($content -ne $orig) {
            Set-Content -LiteralPath $appProp -Value $content -Encoding UTF8 -NoNewline
            Write-Host '    Updated API client ID placeholder'
        } else {
            Write-Host '    Already populated (no placeholders found)'
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

Write-Host '==> Checking prerequisites...'
$account  = Test-Prerequisites
$tenantId = $account.tenantId
Write-Host "    Tenant ID: $tenantId"

Initialize-GraphHeaders

# --- API app + scope + roles -----------------------------------------------
$apiApp        = New-OrGetAppRegistration -DisplayName $ApiName
$identifierUri = Set-ApiIdentifierUri -ObjectId $apiApp.id -AppId $apiApp.appId -CurrentIdentifierUris $apiApp.identifierUris
$scopeId       = Set-ApiOAuth2Scope    -ObjectId $apiApp.id -ScopeName $ApiScopeName
Set-ApiAccessTokenVersion2 -ObjectId $apiApp.id
$roleIds       = Set-ApiAppRoles       -ObjectId $apiApp.id

# --- SPA app + redirect URI(s) ---------------------------------------------
$spaApp = New-OrGetAppRegistration -DisplayName $SpaName
$desiredRedirects = @($RedirectUri)
if ($ProductionRedirectUri) { $desiredRedirects += $ProductionRedirectUri }
Set-SpaRedirectUris -ObjectId $spaApp.id -DesiredRedirectUris $desiredRedirects -CurrentSpa $spaApp.spa

# --- Wire SPA -> API -------------------------------------------------------
Set-SpaRequiredResourceAccess -SpaObjectId $spaApp.id -ApiAppId $apiApp.appId -ScopeId $scopeId
Set-ApiPreAuthorizedSpa       -ApiObjectId $apiApp.id -SpaAppId $spaApp.appId -ScopeId $scopeId

# --- Service principals (needed for consent + role assignment) -------------
$apiSp = New-OrGetServicePrincipal -AppId $apiApp.appId
$spaSp = New-OrGetServicePrincipal -AppId $spaApp.appId

# --- Admin consent ---------------------------------------------------------
$consentGranted = $false
if ($GrantAdminConsent) {
    try {
        Grant-OAuth2AdminConsent -ClientSpId $spaSp.id -ResourceSpId $apiSp.id -ScopeName $ApiScopeName
        $consentGranted = $true
    } catch {
        Write-Warning "Admin consent failed: $($_.Exception.Message)"
        Write-Warning "Grant manually at: https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/CallAnAPI/appId/$($spaApp.appId)"
    }
}

# --- Role assignment for current user --------------------------------------
$rolesAssigned = $false
if ($AssignCurrentUserToRoles) {
    try {
        $me = Get-GraphSelf
        Write-Host "==> Assigning current user ($($me.userPrincipalName)) to API app roles"
        Add-AppRoleAssignmentToUser -UserObjectId $me.id -ResourceSpId $apiSp.id -AppRoleId $roleIds.AdminId  -RoleValueLabel $script:RoleAdminValue
        Add-AppRoleAssignmentToUser -UserObjectId $me.id -ResourceSpId $apiSp.id -AppRoleId $roleIds.ReaderId -RoleValueLabel $script:RoleReaderValue
        $rolesAssigned = $true
    } catch {
        Write-Warning "Role assignment failed: $($_.Exception.Message)"
        Write-Warning "Assign manually at: https://entra.microsoft.com/#view/Microsoft_AAD_IAM/StartboardApplicationsMenuBlade/~/AppAppsPreview"
    }
}

# --- Local config files ----------------------------------------------------
if ($UpdateLocalConfig) {
    Update-LocalConfigFiles -TenantId $tenantId -SpaClientId $spaApp.appId -ApiClientId $apiApp.appId
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$result = [ordered]@{
    tenantId             = $tenantId
    apiAppId             = $apiApp.appId
    apiObjectId          = $apiApp.id
    apiServicePrincipalId = $apiSp.id
    apiName              = $ApiName
    identifierUri        = $identifierUri
    apiScopeName         = $ApiScopeName
    apiScopeId           = $scopeId
    apiScopeUri          = "$identifierUri/$ApiScopeName"
    roleReaderId         = $roleIds.ReaderId
    roleAdminId          = $roleIds.AdminId
    spaAppId             = $spaApp.appId
    spaObjectId          = $spaApp.id
    spaServicePrincipalId = $spaSp.id
    spaName              = $SpaName
    redirectUri          = $RedirectUri
    productionRedirectUri = $ProductionRedirectUri
    adminConsentGranted  = $consentGranted
    currentUserRoleAssignments = $rolesAssigned
}

Write-Host ''
Write-Host '============================================================'
Write-Host ' Entra ID Setup Complete'
Write-Host '============================================================'
$result.GetEnumerator() | ForEach-Object {
    Write-Host (' {0,-26} {1}' -f "$($_.Key):", $_.Value)
}
Write-Host '============================================================'
Write-Host ''
Write-Host ' Next steps:'
Write-Host '   - Run .\scripts\start.ps1 to launch SPA + API locally'
Write-Host '   - Run .\scripts\deploy.ps1 to deploy to Azure'
Write-Host ''

if ($OutputFile) {
    $result | ConvertTo-Json | Set-Content -Path $OutputFile -Encoding UTF8
    Write-Host "Wrote results to $OutputFile"
}

return [pscustomobject]$result
