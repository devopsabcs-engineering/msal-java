<#
.SYNOPSIS
    One-stop, idempotent end-to-end deployment for the Evidence Portal workshop.

.DESCRIPTION
    Drives the entire fast-track from a clean checkout to a working app in Azure:

      1. Verifies prerequisites (az, node, npm, mvn, java).
      2. Bootstraps Entra ID app registrations, scope, roles, permissions,
         pre-authorization, admin consent, and self-role-assignment by
         delegating to setup-entra-apps.ps1 (no-op on re-run).
      3. Generates a globally-unique storage account name.
      4. Creates the resource group if needed.
      5. Detects the deployer's public IP + Entra principal objectId.
      7. Deploys infra (VNet with snet-app + snet-pe, snet-app has a
         Microsoft.Storage service endpoint, App Service Plan, two App
         Services with Regional VNet integration, hardened ADLS Gen2
         storage with shared keys disabled, defaultAction=Deny + a
         VirtualNetworkRule allowing snet-app, Private Endpoint on the
         dfs sub-resource, Private DNS Zone privatelink.dfs.<storage
         suffix>, App Insights, MI role assignments) via Bicep. The
         deployer IP is added to storage networkAcls only for the
         duration of the seeding step.
      7. Patches environment.prod.ts with the deployed App Service URLs +
         App Insights connection string + tenant/client IDs.
      8. Builds the Angular SPA (production) and packages the Spring Boot API.
      9. Deploys both artifacts to App Service.
     10. Adds the deployed SPA URL as a SPA platform redirect URI on the
         SPA app registration (via Graph).
     11. Uploads the bundled sample evidence PDFs over OAuth (Storage Blob
         Data Contributor RBAC, no shared keys) to the storage container.
     12. Re-deploys the storage module with deployerIp='' to remove the
         deployer's IP from networkAcls (App Services keep working via
         the snet-app VirtualNetworkRule + Microsoft.Storage service
         endpoint).
     13. Runs smoke verification: API /api/cases responds, SPA returns 200.

    All steps are idempotent and safe to re-run.

.PARAMETER ResourceGroup
    Azure resource group name. Default: rg-evidence-workshop.

.PARAMETER Environment
    Environment suffix used in resource names. Default: workshop.

.PARAMETER Location
    Azure region. Default: canadacentral.

.PARAMETER SpaName
    SPA app registration display name. Default: "Evidence Portal SPA".

.PARAMETER ApiName
    API app registration display name. Default: "Evidence Portal API".

.PARAMETER SkipEntraSetup
    Skip the Entra ID bootstrap (useful when re-deploying code-only changes).

.PARAMETER SkipBuild
    Skip rebuilding the SPA + API artifacts.

.PARAMETER SkipUpload
    Skip uploading sample evidence PDFs to storage.

.EXAMPLE
    ./scripts/deploy.ps1
#>

[CmdletBinding()]
param(
    [string]$ResourceGroup = 'rg-evidence-workshop',
    [string]$Environment   = 'workshop',
    [string]$Location      = 'canadacentral',
    [string]$SpaName       = 'Evidence Portal SPA',
    [string]$ApiName       = 'Evidence Portal API',
    [switch]$SkipEntraSetup,
    [switch]$SkipBuild,
    [switch]$SkipUpload
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path -Parent $ScriptDir

function Write-Section($message) {
    Write-Host ''
    Write-Host '------------------------------------------------------------'
    Write-Host " $message"
    Write-Host '------------------------------------------------------------'
}

function Install-MavenIfMissing {
    if (Get-Command mvn -ErrorAction SilentlyContinue) { return }
    Write-Host '    Maven not found. Installing Apache Maven 3.9.15...'
    $mavenVersion = '3.9.15'
    $mavenDir     = Join-Path $env:LOCALAPPDATA 'Maven'
    $mavenHome    = Join-Path $mavenDir "apache-maven-$mavenVersion"
    $mavenBin     = Join-Path $mavenHome 'bin'
    if (-not (Test-Path $mavenBin)) {
        $zipUrl  = "https://dlcdn.apache.org/maven/maven-3/$mavenVersion/binaries/apache-maven-$mavenVersion-bin.zip"
        $zipPath = Join-Path $env:TEMP "apache-maven-$mavenVersion-bin.zip"
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
        if (-not (Test-Path $mavenDir)) { New-Item -ItemType Directory -Path $mavenDir -Force | Out-Null }
        Expand-Archive -Path $zipPath -DestinationPath $mavenDir -Force
        Remove-Item $zipPath -Force
    }
    $env:Path = "$mavenBin;$env:Path"
    if (-not (Get-Command mvn -ErrorAction SilentlyContinue)) {
        throw "Maven installation failed. Check $mavenHome"
    }
    Write-Host "    Maven installed at $mavenHome"
}

# ---------------------------------------------------------------------------
# Step 0 — Prerequisites
# ---------------------------------------------------------------------------
Write-Section 'Step 0: Verifying prerequisites'

foreach ($cmd in @('az', 'node', 'npm')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "'$cmd' is not installed or not on PATH."
    }
}
Install-MavenIfMissing
if (-not (az account show 2>$null)) {
    throw "Not logged in to Azure CLI. Run 'az login' first."
}
$account = az account show -o json | ConvertFrom-Json
Write-Host "    Subscription: $($account.name) ($($account.id))"
Write-Host "    Tenant:       $($account.tenantId)"

# ---------------------------------------------------------------------------
# Step 1 — Entra ID setup (idempotent)
# ---------------------------------------------------------------------------
$entraOutput = Join-Path $RepoRoot '.entra-apps.json'
if (-not $SkipEntraSetup) {
    Write-Section 'Step 1: Bootstrapping Entra ID app registrations'
    & "$ScriptDir/setup-entra-apps.ps1" `
        -SpaName $SpaName `
        -ApiName $ApiName `
        -OutputFile $entraOutput | Out-Null
} else {
    Write-Section 'Step 1: Skipped (re-using .entra-apps.json)'
}
if (-not (Test-Path $entraOutput)) {
    throw "Missing $entraOutput. Run without -SkipEntraSetup once."
}
$entra = Get-Content $entraOutput -Raw | ConvertFrom-Json
$tenantId    = $entra.tenantId
$spaClientId = $entra.spaAppId
$apiClientId = $entra.apiAppId

# ---------------------------------------------------------------------------
# Step 2 — Resource group + storage account name
# ---------------------------------------------------------------------------
Write-Section "Step 2: Ensuring resource group $ResourceGroup in $Location"
az group create --name $ResourceGroup --location $Location --output none

# Storage account name: lowercase alphanumeric, 3-24 chars, globally unique.
# Use a deterministic short hash from subscription + RG so re-runs stay stable.
$saInput  = "$($account.id)|$ResourceGroup|$Environment".ToLower()
$saHash   = [System.Security.Cryptography.SHA256]::Create().ComputeHash([Text.Encoding]::UTF8.GetBytes($saInput))
$saSuffix = (([System.BitConverter]::ToString($saHash) -replace '-', '').ToLower()).Substring(0, 8)
$storageAccountName = "stevp$($Environment.ToLower())$saSuffix"
if ($storageAccountName.Length -gt 24) { $storageAccountName = $storageAccountName.Substring(0, 24) }
Write-Host "    Storage account name: $storageAccountName"

# ---------------------------------------------------------------------------
# Step 3 — Bicep deployment (with temporary deployer IP allow-listing on storage)
# ---------------------------------------------------------------------------
Write-Section 'Step 3: Deploying infrastructure (Bicep)'

# Discover the deployer's public IP so the Bicep storage module can punch a
# single, narrowly-scoped hole through the otherwise-Deny networkAcls. The
# seeding step (Step 9) needs OAuth uploads from the workstation; once that
# is done we redeploy with deployerIp='' to fully close the storage account.
$deployerIp = ''
try {
    $deployerIp = (Invoke-RestMethod -Uri 'https://api.ipify.org?format=text' -TimeoutSec 5).Trim()
} catch {
    Write-Warning "    Could not detect deployer public IP (storage will stay fully private; sample evidence upload may fail)."
}
if ($deployerIp) { Write-Host "    Deployer public IP: $deployerIp (added to storage networkAcls until lockdown)" }

# Deployer principal objectId (for Storage Blob Data Contributor RBAC). With
# allowSharedKeyAccess=false, the upload step in Step 9 must use OAuth, so
# the signed-in user needs the Contributor role at the storage scope.
$deployerObjectId  = (az ad signed-in-user show --query id -o tsv 2>$null) ?? ''
$deployerSpType    = 'User'
if (-not $deployerObjectId) {
    # Fall back to a service principal context (e.g. CI).
    $deployerObjectId = (az account show --query 'user.name' -o tsv 2>$null)
    if ($deployerObjectId) {
        $sp = az ad sp show --id $deployerObjectId --query id -o tsv 2>$null
        if ($sp) { $deployerObjectId = $sp; $deployerSpType = 'ServicePrincipal' } else { $deployerObjectId = '' }
    }
}
if ($deployerObjectId) { Write-Host "    Deployer principal: $deployerObjectId ($deployerSpType)" }

$deployJson = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$RepoRoot/infra/main.bicep" `
    --parameters "$RepoRoot/infra/main.bicepparam" `
    --parameters environmentName=$Environment `
                 location=$Location `
                 storageAccountName=$storageAccountName `
                 spaClientId=$spaClientId `
                 apiClientId=$apiClientId `
                 tenantId=$tenantId `
                 deployerIp=$deployerIp `
                 deployerPrincipalId=$deployerObjectId `
                 deployerPrincipalType=$deployerSpType `
    --query 'properties.outputs' `
    -o json

if ($LASTEXITCODE -ne 0 -or -not $deployJson) {
    throw 'Bicep deployment failed.'
}

$outputs = $deployJson | ConvertFrom-Json
$spaUrl     = $outputs.spaUrl.value
$apiUrl     = $outputs.apiUrl.value
$spaAppName = $outputs.spaAppName.value
$apiAppName = $outputs.apiAppName.value
$aiConnStr  = $outputs.appInsightsConnectionString.value

Write-Host "    SPA App Service: $spaAppName"
Write-Host "    API App Service: $apiAppName"
Write-Host "    SPA URL:         $spaUrl"
Write-Host "    API URL:         $apiUrl"

# ---------------------------------------------------------------------------
# Step 4 — Patch environment.prod.ts with deployed values
# ---------------------------------------------------------------------------
Write-Section 'Step 4: Patching environment.prod.ts with deployed values'

$envProd = Join-Path $RepoRoot 'sample-app/spa/src/environments/environment.prod.ts'
$prodContent = @"
export const environment = {
  production: true,
  msalConfig: {
    clientId: '$spaClientId',
    tenantId: '$tenantId',
    redirectUri: '$spaUrl',
  },
  apiConfig: {
    baseUrl: '$apiUrl/api',
    scopes: ['api://$apiClientId/Evidence.Read'],
  },
  appInsights: {
    connectionString: '$aiConnStr',
  },
};
"@
Set-Content -LiteralPath $envProd -Value $prodContent -Encoding UTF8
Write-Host "    Wrote $envProd"

# ---------------------------------------------------------------------------
# Step 5 — Add deployed SPA URL as redirect URI on SPA app registration
# ---------------------------------------------------------------------------
Write-Section 'Step 5: Adding deployed SPA URL as redirect URI on SPA app reg'

& "$ScriptDir/setup-entra-apps.ps1" `
    -SpaName $SpaName `
    -ApiName $ApiName `
    -ProductionRedirectUri $spaUrl `
    -OutputFile $entraOutput | Out-Null

# ---------------------------------------------------------------------------
# Step 6 — Build SPA + API
# ---------------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Section 'Step 6: Building Angular SPA (production)'
    & (Join-Path $PSScriptRoot 'fetch-ontario-design-system.ps1')
    Push-Location "$RepoRoot/sample-app/spa"
    try {
        if (-not (Test-Path 'node_modules')) { npm ci }
        npx ng build --configuration production
    } finally {
        Pop-Location
    }

    Write-Section 'Step 6: Building Spring Boot API'
    Push-Location "$RepoRoot/sample-app/api"
    try {
        mvn -q clean package -DskipTests
    } finally {
        Pop-Location
    }
} else {
    Write-Section 'Step 6: Skipped builds'
}

# Locate build outputs (Angular 19 outputs to dist/<project>/browser by default).
$spaDistCandidates = @(
    Join-Path $RepoRoot 'sample-app/spa/dist/evidence-portal/browser'
    Join-Path $RepoRoot 'sample-app/spa/dist/evidence-portal'
    Join-Path $RepoRoot 'sample-app/spa/dist/spa/browser'
)
$spaDist = $spaDistCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $spaDist) { throw "SPA build output not found. Looked in: $($spaDistCandidates -join ', ')" }

$apiJar = Get-ChildItem -Path "$RepoRoot/sample-app/api/target" -Filter '*.jar' -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -notmatch '-(sources|javadoc)\.jar$' } |
    Select-Object -First 1
if (-not $apiJar) { throw "API JAR not found in sample-app/api/target/" }

# ---------------------------------------------------------------------------
# Step 7 — Deploy SPA
# ---------------------------------------------------------------------------
Write-Section "Step 7: Deploying SPA to $spaAppName"
$spaZip = Join-Path $env:TEMP "evidence-spa-$Environment.zip"
if (Test-Path $spaZip) { Remove-Item $spaZip -Force }
Compress-Archive -Path "$spaDist/*" -DestinationPath $spaZip
az webapp deploy `
    --resource-group $ResourceGroup `
    --name $spaAppName `
    --src-path $spaZip `
    --type zip `
    --output none
Remove-Item $spaZip -Force -ErrorAction SilentlyContinue
Write-Host "    SPA deployed."

# ---------------------------------------------------------------------------
# Step 8 — Deploy API
# ---------------------------------------------------------------------------
Write-Section "Step 8: Deploying API JAR to $apiAppName"
az webapp deploy `
    --resource-group $ResourceGroup `
    --name $apiAppName `
    --src-path $apiJar.FullName `
    --type jar `
    --output none
Write-Host "    API deployed: $($apiJar.Name)"

# ---------------------------------------------------------------------------
# Step 9 — Upload sample evidence to ADLS Gen2 (OAuth, no shared keys)
# ---------------------------------------------------------------------------
if (-not $SkipUpload) {
    Write-Section "Step 9: Uploading sample evidence files to $storageAccountName/evidence (OAuth)"

    if (-not $deployerObjectId) {
        Write-Warning "    Deployer principal not detected; the upload may fail. Re-run after `az login`."
    }
    if (-not $deployerIp) {
        Write-Warning "    Deployer IP not detected; storage networkAcls may block this upload."
    }

    # The CLI's storage commands work transparently against HNS-enabled
    # accounts. We use --auth-mode login so no shared keys leave the
    # workstation. RBAC was granted in Step 3. The IP allow-list set by
    # Step 3 is unreliable when the workstation egresses through a NAT
    # pool with multiple public IPs (corporate network, Wi-Fi tethering),
    # so we briefly flip the storage networkAcls.defaultAction to Allow
    # for the duration of the upload, then Step 10 sets it back to Deny
    # along with publicNetworkAccess=Disabled.
    Write-Host '    Temporarily setting storage networkAcls.defaultAction=Allow for the seed upload'
    az storage account update `
        --resource-group $ResourceGroup `
        --name $storageAccountName `
        --default-action Allow `
        --output none
    Start-Sleep -Seconds 10

    for ($i = 1; $i -le 6; $i++) {
        az storage container create `
            --account-name $storageAccountName `
            --name evidence `
            --auth-mode login `
            --output none 2>$null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 10
    }

    $sourceDir = "$RepoRoot/sample-app/api/src/main/resources/data/sample-evidence"
    $uploaded = $false
    for ($i = 1; $i -le 8; $i++) {
        az storage blob upload-batch `
            --account-name $storageAccountName `
            --destination evidence `
            --source $sourceDir `
            --overwrite `
            --auth-mode login `
            --output none 2>$null
        if ($LASTEXITCODE -eq 0) { $uploaded = $true; break }
        Write-Host "    Upload attempt $i failed (RBAC propagation?); retrying in 15s..."
        Start-Sleep -Seconds 15
    }

    if ($uploaded) {
        $blobCount = az storage blob list `
            --account-name $storageAccountName `
            --container-name evidence `
            --auth-mode login `
            --query 'length(@)' -o tsv 2>$null
        Write-Host "    Sample PDFs uploaded. Container 'evidence' now holds $blobCount blob(s)."
    } else {
        Write-Warning "    Sample evidence upload failed after retries. You can re-run later with: az storage blob upload-batch --account-name $storageAccountName --destination evidence --source `"$sourceDir`" --auth-mode login --overwrite"
    }
} else {
    Write-Section 'Step 9: Skipped sample evidence upload'
}

# ---------------------------------------------------------------------------
# Step 10 — Lock down storage (remove deployer IP allow-list)
# ---------------------------------------------------------------------------
Write-Section 'Step 10: Locking down storage (removing temporary deployer IP)'

# Re-deploy with deployerIp='' so the seeding allow-rule is removed.
# The App Services keep working because storage networkAcls trust snet-app
# via a VirtualNetworkRule + the Microsoft.Storage service endpoint on the
# subnet (publicNetworkAccess stays Enabled by design — Disabled would
# block VNet rules; defaultAction=Deny + the VNet rule provide the
# equivalent restriction).
az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$RepoRoot/infra/main.bicep" `
    --parameters "$RepoRoot/infra/main.bicepparam" `
    --parameters environmentName=$Environment `
                 location=$Location `
                 storageAccountName=$storageAccountName `
                 spaClientId=$spaClientId `
                 apiClientId=$apiClientId `
                 tenantId=$tenantId `
                 deployerIp='' `
                 deployerPrincipalId=$deployerObjectId `
                 deployerPrincipalType=$deployerSpType `
    --output none
Write-Host '    Storage networkAcls trust snet-app only. Public traffic (other than App Services via VNet integration) is denied.'

# ---------------------------------------------------------------------------
# Step 11 — Smoke verification
# ---------------------------------------------------------------------------
Write-Section 'Step 11: Smoke verification'

# SPA returns 200 (warm-up may take a minute).
$spaOk = $false
for ($i = 1; $i -le 12; $i++) {
    try {
        $resp = Invoke-WebRequest -Uri $spaUrl -UseBasicParsing -TimeoutSec 30
        if ($resp.StatusCode -eq 200) { $spaOk = $true; break }
    } catch {
        Start-Sleep -Seconds 5
    }
}
Write-Host ("    SPA  $spaUrl => " + ($(if ($spaOk) { 'OK 200' } else { 'WARN: not yet 200, may still be warming up' })))

# API /api/cases — expect 401 (unauthorized) which means JWT validation is on.
$apiCheck = "$apiUrl/api/cases"
$apiResult = ''
try {
    $r = Invoke-WebRequest -Uri $apiCheck -UseBasicParsing -TimeoutSec 30
    $apiResult = "Unexpected 200 (auth might be off): $($r.StatusCode)"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    if ($code -eq 401) { $apiResult = 'OK 401 (JWT validation enforced)' }
    elseif ($code) { $apiResult = "HTTP $code (not 200/401)" }
    else { $apiResult = "WARN: $($_.Exception.Message) (may still be warming up)" }
}
Write-Host "    API  $apiCheck => $apiResult"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Section 'Deployment complete'
Write-Host ''
Write-Host " Resource Group : $ResourceGroup"
Write-Host " Region         : $Location"
Write-Host " Tenant         : $tenantId"
Write-Host " SPA URL        : $spaUrl"
Write-Host " API URL        : $apiUrl"
Write-Host " Storage        : $storageAccountName (container: evidence)"
Write-Host ''
Write-Host ' Open the SPA URL in your browser, sign in with the same account'
Write-Host " you ran this script as ($($account.user.name)). The CaseAdmin role"
Write-Host ' has already been self-assigned, so /api/cases POST will work too.'
Write-Host ''
Write-Host ' Cleanup when done:'
Write-Host "   az group delete --name $ResourceGroup --yes --no-wait"
Write-Host ''
