#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# configure-app-settings.sh
#
# Configures App Service application settings for both the SPA and API
# after deployment. Sets MSAL, Azure AD, storage, and telemetry settings.
#
# Usage:
#   ./scripts/configure-app-settings.sh \
#       --resource-group "rg-evidence-dev" \
#       --spa-app-name "app-evidence-spa-dev" \
#       --api-app-name "app-evidence-api-dev" \
#       --spa-client-id "<SPA_CLIENT_ID>" \
#       --api-client-id "<API_CLIENT_ID>" \
#       --tenant-id "<TENANT_ID>" \
#       --storage-account-name "stevidencedev" \
#       --api-base-url "https://app-evidence-api-dev.azurewebsites.net"
###############################################################################

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
RESOURCE_GROUP=""
SPA_APP_NAME=""
API_APP_NAME=""
SPA_CLIENT_ID=""
API_CLIENT_ID=""
TENANT_ID=""
STORAGE_ACCOUNT_NAME=""
API_BASE_URL=""
CONTAINER_NAME="evidence"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Configures App Service settings for the Evidence Portal SPA and API.

Required:
  --resource-group         Azure resource group name
  --spa-app-name           SPA App Service name
  --api-app-name           API App Service name
  --spa-client-id          SPA application (client) ID
  --api-client-id          API application (client) ID
  --tenant-id              Azure AD tenant ID
  --storage-account-name   Azure Storage account name
  --api-base-url           API base URL (e.g., https://app-evidence-api-dev.azurewebsites.net)

Optional:
  --container-name         Blob container name (default: evidence)
  -h, --help               Show this help message
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group)        RESOURCE_GROUP="$2"; shift 2 ;;
        --spa-app-name)          SPA_APP_NAME="$2"; shift 2 ;;
        --api-app-name)          API_APP_NAME="$2"; shift 2 ;;
        --spa-client-id)         SPA_CLIENT_ID="$2"; shift 2 ;;
        --api-client-id)         API_CLIENT_ID="$2"; shift 2 ;;
        --tenant-id)             TENANT_ID="$2"; shift 2 ;;
        --storage-account-name)  STORAGE_ACCOUNT_NAME="$2"; shift 2 ;;
        --api-base-url)          API_BASE_URL="$2"; shift 2 ;;
        --container-name)        CONTAINER_NAME="$2"; shift 2 ;;
        -h|--help)               usage ;;
        *) echo "ERROR: Unknown option $1"; usage ;;
    esac
done

# Validate required parameters
MISSING=()
[[ -z "$RESOURCE_GROUP" ]]       && MISSING+=("--resource-group")
[[ -z "$SPA_APP_NAME" ]]         && MISSING+=("--spa-app-name")
[[ -z "$API_APP_NAME" ]]         && MISSING+=("--api-app-name")
[[ -z "$SPA_CLIENT_ID" ]]        && MISSING+=("--spa-client-id")
[[ -z "$API_CLIENT_ID" ]]        && MISSING+=("--api-client-id")
[[ -z "$TENANT_ID" ]]            && MISSING+=("--tenant-id")
[[ -z "$STORAGE_ACCOUNT_NAME" ]] && MISSING+=("--storage-account-name")
[[ -z "$API_BASE_URL" ]]         && MISSING+=("--api-base-url")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: Missing required parameters: ${MISSING[*]}"
    usage
fi

# ---------------------------------------------------------------------------
# Retrieve Application Insights connection string
# ---------------------------------------------------------------------------
echo "==> Retrieving Application Insights connection string..."

APPINSIGHTS_NAME=$(az monitor app-insights component list \
    --resource-group "${RESOURCE_GROUP}" \
    --query "[0].name" -o tsv 2>/dev/null || true)

APPINSIGHTS_CONNSTR=""
if [[ -n "${APPINSIGHTS_NAME}" ]]; then
    APPINSIGHTS_CONNSTR=$(az monitor app-insights component show \
        --app "${APPINSIGHTS_NAME}" \
        --resource-group "${RESOURCE_GROUP}" \
        --query "connectionString" -o tsv)
    echo "    Found Application Insights: ${APPINSIGHTS_NAME}"
else
    echo "    WARNING: No Application Insights found in resource group ${RESOURCE_GROUP}"
fi

# ---------------------------------------------------------------------------
# Configure SPA App Service settings
# ---------------------------------------------------------------------------
echo ""
echo "==> Configuring SPA App Service: ${SPA_APP_NAME}..."

SPA_SETTINGS=(
    "MSAL_CLIENT_ID=${SPA_CLIENT_ID}"
    "MSAL_TENANT_ID=${TENANT_ID}"
    "API_BASE_URL=${API_BASE_URL}"
)

if [[ -n "${APPINSIGHTS_CONNSTR}" ]]; then
    SPA_SETTINGS+=("APPLICATIONINSIGHTS_CONNECTION_STRING=${APPINSIGHTS_CONNSTR}")
fi

az webapp config appsettings set \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${SPA_APP_NAME}" \
    --settings "${SPA_SETTINGS[@]}" \
    --output none

echo "    SPA settings configured:"
echo "      MSAL_CLIENT_ID"
echo "      MSAL_TENANT_ID"
echo "      API_BASE_URL"
[[ -n "${APPINSIGHTS_CONNSTR}" ]] && echo "      APPLICATIONINSIGHTS_CONNECTION_STRING"

# ---------------------------------------------------------------------------
# Configure API App Service settings
# ---------------------------------------------------------------------------
echo ""
echo "==> Configuring API App Service: ${API_APP_NAME}..."

API_IDENTIFIER_URI="api://${API_CLIENT_ID}"

API_SETTINGS=(
    "AZURE_TENANT_ID=${TENANT_ID}"
    "JWT_ISSUER_URI=https://login.microsoftonline.com/${TENANT_ID}/v2.0"
    "JWT_AUDIENCE=${API_IDENTIFIER_URI}"
    "AZURE_STORAGE_ACCOUNT_NAME=${STORAGE_ACCOUNT_NAME}"
    "AZURE_STORAGE_CONTAINER_NAME=${CONTAINER_NAME}"
    "WEBSITES_PORT=8080"
    "SPRING_PROFILES_ACTIVE=prod"
)

if [[ -n "${APPINSIGHTS_CONNSTR}" ]]; then
    API_SETTINGS+=("APPLICATIONINSIGHTS_CONNECTION_STRING=${APPINSIGHTS_CONNSTR}")
fi

az webapp config appsettings set \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${API_APP_NAME}" \
    --settings "${API_SETTINGS[@]}" \
    --output none

echo "    API settings configured:"
echo "      AZURE_TENANT_ID"
echo "      JWT_ISSUER_URI"
echo "      JWT_AUDIENCE"
echo "      AZURE_STORAGE_ACCOUNT_NAME"
echo "      AZURE_STORAGE_CONTAINER_NAME"
echo "      WEBSITES_PORT=8080"
echo "      SPRING_PROFILES_ACTIVE=prod"
[[ -n "${APPINSIGHTS_CONNSTR}" ]] && echo "      APPLICATIONINSIGHTS_CONNECTION_STRING"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " App Service Settings Configured Successfully"
echo "============================================================"
echo ""
echo " Resource Group:  ${RESOURCE_GROUP}"
echo " SPA App Service: ${SPA_APP_NAME}"
echo " API App Service: ${API_APP_NAME}"
echo "============================================================"
