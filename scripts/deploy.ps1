<#
.SYNOPSIS
    End-to-end deployment script for the Evidence Portal workshop.

.DESCRIPTION
    Builds both apps, deploys infrastructure via Bicep, deploys artifacts
    to Azure App Service, and configures app settings.

.PARAMETER ResourceGroup
    Azure resource group name.

.PARAMETER Environment
    Environment name (e.g., dev, staging, prod).

.PARAMETER SpaClientId
    SPA application (client) ID from Entra ID.

.PARAMETER ApiClientId
    API application (client) ID from Entra ID.

.PARAMETER TenantId
    Azure AD tenant ID.

.PARAMETER Location
    Azure region. Defaults to canadacentral.

.EXAMPLE
    ./scripts/deploy.ps1 `
        -ResourceGroup "rg-evidence-dev" `
        -Environment "dev" `
        -SpaClientId "00000000-..." `
        -ApiClientId "00000000-..." `
        -TenantId "00000000-..."
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $true)]
    [string]$SpaClientId,

    [Parameter(Mandatory = $true)]
    [string]$ApiClientId,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [string]$Location = "canadacentral"
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir

# ---------------------------------------------------------------------------
# Verify prerequisites
# ---------------------------------------------------------------------------
Write-Host "==> Checking prerequisites..."

foreach ($cmd in @('az', 'node', 'npm', 'mvn')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Error "'$cmd' is not installed or not on PATH."
        exit 1
    }
}

$account = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error "Not logged in to Azure CLI. Run 'az login' first."
    exit 1
}

Write-Host "    All prerequisites satisfied"

# ---------------------------------------------------------------------------
# Step 1 — Build Angular SPA
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Step 1: Building Angular SPA..."

Push-Location "$RepoRoot/sample-app/spa"
try {
    npm ci
    npx ng build --configuration production
}
finally {
    Pop-Location
}

$SpaDistDir = Join-Path $RepoRoot "sample-app/spa/dist/spa/browser"
if (-not (Test-Path $SpaDistDir)) {
    $SpaDistDir = Join-Path $RepoRoot "sample-app/spa/dist/spa"
}

Write-Host "    SPA build complete: $SpaDistDir"

# ---------------------------------------------------------------------------
# Step 2 — Build Spring Boot API
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Step 2: Building Spring Boot API..."

Push-Location "$RepoRoot/sample-app/api"
try {
    mvn clean package -DskipTests
}
finally {
    Pop-Location
}

$ApiJar = Get-ChildItem -Path "$RepoRoot/sample-app/api/target" -Filter "*.jar" |
    Where-Object { $_.Name -notmatch '-(sources|javadoc)\.jar$' } |
    Select-Object -First 1

if (-not $ApiJar) {
    Write-Error "No JAR file found in sample-app/api/target/"
    exit 1
}

Write-Host "    API build complete: $($ApiJar.FullName)"

# ---------------------------------------------------------------------------
# Step 3 — Create resource group (if not exists)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Step 3: Ensuring resource group exists..."

az group create `
    --name $ResourceGroup `
    --location $Location `
    --output none

Write-Host "    Resource group '$ResourceGroup' ready in $Location"

# ---------------------------------------------------------------------------
# Step 4 — Deploy infrastructure via Bicep
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Step 4: Deploying infrastructure via Bicep..."

$DeploymentOutput = az deployment group create `
    --resource-group $ResourceGroup `
    --template-file "$RepoRoot/infra/main.bicep" `
    --parameters "$RepoRoot/infra/main.bicepparam" `
    --parameters environmentName=$Environment `
    --query "properties.outputs" `
    -o json | ConvertFrom-Json

$SpaAppName = if ($DeploymentOutput.spaAppName) { $DeploymentOutput.spaAppName.value } else { "app-evidence-spa-$Environment" }
$ApiAppName = if ($DeploymentOutput.apiAppName) { $DeploymentOutput.apiAppName.value } else { "app-evidence-api-$Environment" }
$StorageAccountName = if ($DeploymentOutput.storageAccountName) { $DeploymentOutput.storageAccountName.value } else { "stevidence$Environment" }

Write-Host "    Infrastructure deployed"
Write-Host "    SPA App Service:    $SpaAppName"
Write-Host "    API App Service:    $ApiAppName"
Write-Host "    Storage Account:    $StorageAccountName"

# ---------------------------------------------------------------------------
# Step 5 — Deploy SPA to App Service
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Step 5: Deploying SPA to App Service..."

$SpaZip = Join-Path $env:TEMP "evidence-spa-$Environment.zip"

if (Test-Path $SpaZip) { Remove-Item $SpaZip -Force }
Compress-Archive -Path "$SpaDistDir/*" -DestinationPath $SpaZip

az webapp deploy `
    --resource-group $ResourceGroup `
    --name $SpaAppName `
    --src-path $SpaZip `
    --type zip `
    --output none

Remove-Item $SpaZip -Force -ErrorAction SilentlyContinue
Write-Host "    SPA deployed to $SpaAppName"

# ---------------------------------------------------------------------------
# Step 6 — Deploy API to App Service
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Step 6: Deploying API JAR to App Service..."

az webapp deploy `
    --resource-group $ResourceGroup `
    --name $ApiAppName `
    --src-path $ApiJar.FullName `
    --type jar `
    --output none

Write-Host "    API deployed to $ApiAppName"

# ---------------------------------------------------------------------------
# Step 7 — Configure app settings
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "==> Step 7: Configuring app settings..."

$ApiBaseUrl = "https://$ApiAppName.azurewebsites.net"

& "$ScriptDir/configure-app-settings.sh" `
    --resource-group $ResourceGroup `
    --spa-app-name $SpaAppName `
    --api-app-name $ApiAppName `
    --spa-client-id $SpaClientId `
    --api-client-id $ApiClientId `
    --tenant-id $TenantId `
    --storage-account-name $StorageAccountName `
    --api-base-url $ApiBaseUrl

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "============================================================"
Write-Host " Deployment Complete"
Write-Host "============================================================"
Write-Host ""
Write-Host " Resource Group:  $ResourceGroup"
Write-Host " Environment:     $Environment"
Write-Host " SPA URL:         https://$SpaAppName.azurewebsites.net"
Write-Host " API URL:         $ApiBaseUrl"
Write-Host ""
Write-Host " Next steps:"
Write-Host "   1. Assign CaseReader / CaseAdmin roles to users"
Write-Host "   2. Upload sample evidence PDFs to storage container 'evidence'"
Write-Host "   3. Browse to the SPA URL and sign in"
Write-Host "============================================================"
