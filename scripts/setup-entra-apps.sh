#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# setup-entra-apps.sh
#
# Creates Entra ID (Azure AD) app registrations for the Evidence Portal
# workshop: one API app and one SPA app, with proper scopes, roles, and
# pre-authorization.
#
# Usage:
#   ./scripts/setup-entra-apps.sh \
#       --spa-name "Evidence Portal SPA" \
#       --api-name "Evidence Portal API" \
#       --redirect-uri "http://localhost:4200"
###############################################################################

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SPA_NAME=""
API_NAME=""
REDIRECT_URI="http://localhost:4200"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Creates Entra ID app registrations for the Evidence Portal workshop.

Required:
  --spa-name       Display name for the SPA app registration
  --api-name       Display name for the API app registration

Optional:
  --redirect-uri   SPA redirect URI (default: http://localhost:4200)
  -h, --help       Show this help message

Examples:
  $(basename "$0") --spa-name "Evidence SPA" --api-name "Evidence API"
  $(basename "$0") --spa-name "Evidence SPA" --api-name "Evidence API" --redirect-uri "https://myapp.azurewebsites.net"
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --spa-name)   SPA_NAME="$2"; shift 2 ;;
        --api-name)   API_NAME="$2"; shift 2 ;;
        --redirect-uri) REDIRECT_URI="$2"; shift 2 ;;
        -h|--help)    usage ;;
        *) echo "ERROR: Unknown option $1"; usage ;;
    esac
done

if [[ -z "$SPA_NAME" || -z "$API_NAME" ]]; then
    echo "ERROR: --spa-name and --api-name are required."
    usage
fi

# ---------------------------------------------------------------------------
# Verify prerequisites
# ---------------------------------------------------------------------------
echo "==> Checking prerequisites..."
if ! command -v az &>/dev/null; then
    echo "ERROR: Azure CLI (az) is not installed. Install from https://aka.ms/install-azure-cli"
    exit 1
fi

if ! az account show &>/dev/null; then
    echo "ERROR: Not logged in to Azure CLI. Run 'az login' first."
    exit 1
fi

TENANT_ID=$(az account show --query tenantId -o tsv)
echo "    Tenant ID: ${TENANT_ID}"

# ---------------------------------------------------------------------------
# Step 1 — Create API app registration
# ---------------------------------------------------------------------------
echo ""
echo "==> Creating API app registration: ${API_NAME}..."

API_APP_ID=$(az ad app create \
    --display-name "${API_NAME}" \
    --sign-in-audience AzureADMyOrg \
    --query appId -o tsv)

echo "    API Application (client) ID: ${API_APP_ID}"

# Set the Identifier URI
IDENTIFIER_URI="api://${API_APP_ID}"

az ad app update \
    --id "${API_APP_ID}" \
    --identifier-uris "${IDENTIFIER_URI}"

echo "    Identifier URI: ${IDENTIFIER_URI}"

# ---------------------------------------------------------------------------
# Step 2 — Expose API scope: Evidence.Read
# ---------------------------------------------------------------------------
echo ""
echo "==> Exposing API scope: Evidence.Read..."

# Generate a UUID for the scope
SCOPE_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
           python  -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
           cat /proc/sys/kernel/random/uuid 2>/dev/null || \
           uuidgen 2>/dev/null || \
           powershell.exe -Command "[guid]::NewGuid().ToString()" 2>/dev/null)

SCOPE_JSON=$(cat <<EOF
[
    {
        "adminConsentDescription": "Allow the application to read evidence data on behalf of the signed-in user",
        "adminConsentDisplayName": "Read evidence data",
        "id": "${SCOPE_ID}",
        "isEnabled": true,
        "type": "User",
        "userConsentDescription": "Allow the application to read evidence data on your behalf",
        "userConsentDisplayName": "Read evidence data",
        "value": "Evidence.Read"
    }
]
EOF
)

az ad app update \
    --id "${API_APP_ID}" \
    --set "api.oauth2PermissionScopes=${SCOPE_JSON}"

echo "    Scope Evidence.Read created (ID: ${SCOPE_ID})"

# ---------------------------------------------------------------------------
# Step 3 — Define App Roles: CaseReader, CaseAdmin
# ---------------------------------------------------------------------------
echo ""
echo "==> Defining app roles: CaseReader, CaseAdmin..."

ROLE_READER_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                 python  -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                 cat /proc/sys/kernel/random/uuid 2>/dev/null || \
                 uuidgen 2>/dev/null || \
                 powershell.exe -Command "[guid]::NewGuid().ToString()" 2>/dev/null)

ROLE_ADMIN_ID=$(python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                python  -c "import uuid; print(uuid.uuid4())" 2>/dev/null || \
                cat /proc/sys/kernel/random/uuid 2>/dev/null || \
                uuidgen 2>/dev/null || \
                powershell.exe -Command "[guid]::NewGuid().ToString()" 2>/dev/null)

ROLES_JSON=$(cat <<EOF
[
    {
        "allowedMemberTypes": ["User"],
        "description": "Can read cases and download evidence files",
        "displayName": "Case Reader",
        "id": "${ROLE_READER_ID}",
        "isEnabled": true,
        "value": "CaseReader"
    },
    {
        "allowedMemberTypes": ["User"],
        "description": "Can read, create, and manage cases and evidence files",
        "displayName": "Case Admin",
        "id": "${ROLE_ADMIN_ID}",
        "isEnabled": true,
        "value": "CaseAdmin"
    }
]
EOF
)

az ad app update \
    --id "${API_APP_ID}" \
    --app-roles "${ROLES_JSON}"

echo "    CaseReader role created (ID: ${ROLE_READER_ID})"
echo "    CaseAdmin role created  (ID: ${ROLE_ADMIN_ID})"

# ---------------------------------------------------------------------------
# Step 4 — Create SPA app registration
# ---------------------------------------------------------------------------
echo ""
echo "==> Creating SPA app registration: ${SPA_NAME}..."

SPA_APP_ID=$(az ad app create \
    --display-name "${SPA_NAME}" \
    --sign-in-audience AzureADMyOrg \
    --enable-id-token-issuance false \
    --query appId -o tsv)

echo "    SPA Application (client) ID: ${SPA_APP_ID}"

# ---------------------------------------------------------------------------
# Step 5 — Configure SPA platform redirect URI
# ---------------------------------------------------------------------------
echo ""
echo "==> Configuring SPA platform redirect URI: ${REDIRECT_URI}..."

az ad app update \
    --id "${SPA_APP_ID}" \
    --set "spa.redirectUris=[\"${REDIRECT_URI}\"]"

echo "    Redirect URI configured"

# ---------------------------------------------------------------------------
# Step 6 — Add delegated API permission (Evidence.Read) to SPA
# ---------------------------------------------------------------------------
echo ""
echo "==> Adding delegated API permission Evidence.Read to SPA..."

az ad app permission add \
    --id "${SPA_APP_ID}" \
    --api "${API_APP_ID}" \
    --api-permissions "${SCOPE_ID}=Scope"

echo "    Delegated permission added"

# ---------------------------------------------------------------------------
# Step 7 — Pre-authorize SPA on API for Evidence.Read
# ---------------------------------------------------------------------------
echo ""
echo "==> Pre-authorizing SPA on API for Evidence.Read..."

PREAUTH_JSON=$(cat <<EOF
[
    {
        "appId": "${SPA_APP_ID}",
        "delegatedPermissionIds": ["${SCOPE_ID}"]
    }
]
EOF
)

az ad app update \
    --id "${API_APP_ID}" \
    --set "api.preAuthorizedApplications=${PREAUTH_JSON}"

echo "    SPA pre-authorized on API"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Entra ID App Registrations Created Successfully"
echo "============================================================"
echo ""
echo " Tenant ID:      ${TENANT_ID}"
echo " API App ID:     ${API_APP_ID}"
echo " SPA App ID:     ${SPA_APP_ID}"
echo " Identifier URI: ${IDENTIFIER_URI}"
echo " Redirect URI:   ${REDIRECT_URI}"
echo ""
echo " Next steps:"
echo "   1. Assign CaseReader / CaseAdmin roles to users in the Azure Portal"
echo "   2. Update sample-app/spa/src/environments/environment.ts with SPA App ID"
echo "   3. Update sample-app/api/src/main/resources/application.properties with API App ID"
echo "============================================================"
