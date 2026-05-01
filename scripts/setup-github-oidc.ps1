<#
.SYNOPSIS
    Configures GitHub Actions OIDC federated identity to Azure for the
    Evidence Portal workflow, idempotently.

.DESCRIPTION
    Bootstraps everything the .github/workflows/deploy.yml workflow needs to
    authenticate to Azure without storing a client secret in the repository:

      1. Creates (or reuses) an Entra ID app registration + service
         principal that the workflow will sign in as.
      2. Adds Federated Identity Credentials so GitHub's OIDC tokens for
         pushes to a specified branch (default: main) and for the
         "workshop" deployment environment can exchange for an Azure AD
         access token. No secret leaves Azure.
      3. Grants the SP "Website Contributor" on the resource group so it
         can deploy to App Services. Optionally also grants "Storage
         Blob Data Contributor" on the storage account if the CI ever
         needs to touch storage.
      4. Sets the three repo secrets (AZURE_CLIENT_ID, AZURE_TENANT_ID,
         AZURE_SUBSCRIPTION_ID) via the GitHub CLI.

    All steps are idempotent and safe to re-run.

.PARAMETER Repo
    GitHub repository in "owner/name" form. Defaults to
    devopsabcs-engineering/msal-java.

.PARAMETER Branch
    Git branch the workflow runs against. Defaults to main.

.PARAMETER Environment
    GitHub deployment environment name used by the workflow. Defaults to
    workshop. A second federated credential is added for this so
    workflow_dispatch from the environment also works.

.PARAMETER AppDisplayName
    Display name for the SP. Defaults to msal-java-github-actions.

.PARAMETER ResourceGroup
    Azure resource group where the App Services live. Defaults to
    rg-evidence-workshop.

.PARAMETER GrantStorageContributor
    If specified, also grants Storage Blob Data Contributor on the
    workshop storage account discovered in the resource group.

.PARAMETER SkipSecretWrite
    If specified, prints the values that would be written to GitHub
    secrets but does not call `gh`. Useful when running in a directory
    that is not a git working tree, or when secrets are managed by hand.

.EXAMPLE
    ./scripts/setup-github-oidc.ps1

.EXAMPLE
    ./scripts/setup-github-oidc.ps1 -Repo myorg/myfork -Branch dev
#>
[CmdletBinding()]
param(
    [string]$Repo            = 'devopsabcs-engineering/msal-java',
    [string]$Branch          = 'main',
    [string]$Environment     = 'workshop',
    [string]$AppDisplayName  = 'msal-java-github-actions',
    [string]$ResourceGroup   = 'rg-evidence-workshop',
    [switch]$GrantStorageContributor,
    [switch]$SkipSecretWrite
)

$ErrorActionPreference = 'Stop'

function Write-Section($message) {
    Write-Host ''
    Write-Host '------------------------------------------------------------'
    Write-Host " $message"
    Write-Host '------------------------------------------------------------'
}

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

# ---------------------------------------------------------------------------
# Step 0 — Prerequisites
# ---------------------------------------------------------------------------
Write-Section 'Step 0: Verifying prerequisites'

if (-not (Test-Command az)) {
    throw 'Azure CLI (az) is not installed. https://aka.ms/install-azure-cli'
}
if (-not $SkipSecretWrite -and -not (Test-Command gh)) {
    throw 'GitHub CLI (gh) is not installed. Install from https://cli.github.com/ or re-run with -SkipSecretWrite to print secrets manually.'
}

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) { throw "Not logged in to Azure CLI. Run 'az login' first." }
$tenantId       = $account.tenantId
$subscriptionId = $account.id
Write-Host "    Subscription: $($account.name) ($subscriptionId)"
Write-Host "    Tenant:       $tenantId"

if (-not $SkipSecretWrite) {
    & gh auth status 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Not logged in to GitHub CLI. Run 'gh auth login' first."
    }
}

# ---------------------------------------------------------------------------
# Step 1 — Ensure app registration + service principal
# ---------------------------------------------------------------------------
Write-Section "Step 1: Ensuring app registration '$AppDisplayName'"

$appId = az ad app list `
    --display-name $AppDisplayName `
    --query '[0].appId' -o tsv 2>$null
if (-not $appId) {
    Write-Host '    Creating new app registration...'
    $appId = az ad app create `
        --display-name $AppDisplayName `
        --sign-in-audience AzureADMyOrg `
        --query appId -o tsv
} else {
    Write-Host "    Reusing existing app registration: $appId"
}

$objectId = az ad app show --id $appId --query id -o tsv

$spId = az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv 2>$null
if (-not $spId) {
    Write-Host '    Creating service principal...'
    $spId = az ad sp create --id $appId --query id -o tsv
} else {
    Write-Host "    Reusing existing service principal: $spId"
}

Write-Host "    appId    : $appId"
Write-Host "    objectId : $objectId"
Write-Host "    spId     : $spId"

# ---------------------------------------------------------------------------
# Step 2 — Federated Identity Credentials (branch + environment)
# ---------------------------------------------------------------------------
Write-Section 'Step 2: Ensuring Federated Identity Credentials'

# Each credential maps a GitHub OIDC subject claim to this app reg.
# - Branch credential covers `on: push` and `workflow_dispatch` triggers
#   that don't go through an Environment.
# - Environment credential covers steps inside `environment: workshop`
#   in the workflow (used for the deploy job).
$credentials = @(
    @{
        Name    = "github-$($Repo -replace '/', '-')-branch-$Branch"
        Subject = "repo:${Repo}:ref:refs/heads/$Branch"
    },
    @{
        Name    = "github-$($Repo -replace '/', '-')-env-$Environment"
        Subject = "repo:${Repo}:environment:$Environment"
    }
)

$existing = az ad app federated-credential list --id $appId --output json 2>$null | ConvertFrom-Json
if (-not $existing) { $existing = @() }

foreach ($cred in $credentials) {
    $match = $existing | Where-Object { $_.subject -eq $cred.Subject }
    if ($match) {
        Write-Host "    Reusing federated credential '$($match.name)' for subject $($cred.Subject)"
        continue
    }
    Write-Host "    Adding federated credential for subject $($cred.Subject)"
    $body = @{
        name      = $cred.Name
        issuer    = 'https://token.actions.githubusercontent.com'
        subject   = $cred.Subject
        audiences = @('api://AzureADTokenExchange')
        description = "GitHub Actions OIDC for $($cred.Subject)"
    } | ConvertTo-Json -Compress

    # az reads the JSON from a file or stdin (here-string -> temp file is
    # the cross-platform option).
    $tmp = New-TemporaryFile
    try {
        Set-Content -LiteralPath $tmp.FullName -Value $body -Encoding ASCII
        az ad app federated-credential create --id $appId --parameters "@$($tmp.FullName)" --output none
    } finally {
        Remove-Item -LiteralPath $tmp.FullName -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# Step 3 — Role assignments
# ---------------------------------------------------------------------------
Write-Section "Step 3: Assigning Website Contributor on $ResourceGroup"

$rgScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroup"

az group show --name $ResourceGroup --output none 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Resource group '$ResourceGroup' does not exist in subscription $subscriptionId. Deploy infra first via scripts/deploy.ps1."
}

$existingRole = az role assignment list `
    --assignee $spId `
    --scope $rgScope `
    --role 'Website Contributor' `
    --query '[0].id' -o tsv 2>$null
if ($existingRole) {
    Write-Host '    Website Contributor already assigned.'
} else {
    Write-Host '    Granting Website Contributor (may take a few seconds to propagate)...'
    az role assignment create `
        --assignee-object-id $spId `
        --assignee-principal-type ServicePrincipal `
        --role 'Website Contributor' `
        --scope $rgScope `
        --output none
}

if ($GrantStorageContributor) {
    Write-Host ''
    Write-Host '    -GrantStorageContributor specified; locating storage account in RG...'
    $storageAccount = az storage account list `
        --resource-group $ResourceGroup `
        --query '[0].name' -o tsv 2>$null
    if (-not $storageAccount) {
        Write-Warning '    No storage account found in RG; skipping Storage Blob Data Contributor grant.'
    } else {
        $storageScope = "$rgScope/providers/Microsoft.Storage/storageAccounts/$storageAccount"
        $existingStorageRole = az role assignment list `
            --assignee $spId `
            --scope $storageScope `
            --role 'Storage Blob Data Contributor' `
            --query '[0].id' -o tsv 2>$null
        if ($existingStorageRole) {
            Write-Host "    Storage Blob Data Contributor already assigned on $storageAccount."
        } else {
            Write-Host "    Granting Storage Blob Data Contributor on $storageAccount..."
            az role assignment create `
                --assignee-object-id $spId `
                --assignee-principal-type ServicePrincipal `
                --role 'Storage Blob Data Contributor' `
                --scope $storageScope `
                --output none
        }
    }
}

# ---------------------------------------------------------------------------
# Step 4 — GitHub repository secrets
# ---------------------------------------------------------------------------
Write-Section "Step 4: Setting GitHub repository secrets on $Repo"

$secrets = [ordered]@{
    AZURE_CLIENT_ID       = $appId
    AZURE_TENANT_ID       = $tenantId
    AZURE_SUBSCRIPTION_ID = $subscriptionId
}

if ($SkipSecretWrite) {
    Write-Host '    -SkipSecretWrite specified. Set these manually under'
    Write-Host "    https://github.com/$Repo/settings/secrets/actions :"
    foreach ($k in $secrets.Keys) {
        Write-Host ("      {0,-22} = {1}" -f $k, $secrets[$k])
    }
} else {
    foreach ($k in $secrets.Keys) {
        Write-Host "    Setting $k"
        $value = $secrets[$k]
        # `gh secret set` reads the value from stdin when --body is omitted.
        $value | & gh secret set $k --repo $Repo --body $value | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '============================================================'
Write-Host ' GitHub OIDC setup complete'
Write-Host '============================================================'
Write-Host " Repository           : $Repo"
Write-Host " Branch credential    : repo:${Repo}:ref:refs/heads/$Branch"
Write-Host " Environment credential: repo:${Repo}:environment:$Environment"
Write-Host " App registration     : $AppDisplayName ($appId)"
Write-Host " Service principal    : $spId"
Write-Host " RG scope             : $rgScope"
Write-Host ''
Write-Host ' Next: push to '"$Branch"' (or run the workflow via'
Write-Host '   gh workflow run "Deploy SPA and API"'
Write-Host ' under https://github.com/'"$Repo"'/actions).'
