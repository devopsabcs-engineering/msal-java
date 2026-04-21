#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# deploy.sh
#
# End-to-end deployment script for the Evidence Portal workshop.
# Builds both apps, deploys infrastructure via Bicep, deploys artifacts
# to Azure App Service, and configures app settings.
#
# Usage:
#   ./scripts/deploy.sh \
#       --resource-group "rg-evidence-dev" \
#       --environment "dev" \
#       --spa-client-id "<SPA_CLIENT_ID>" \
#       --api-client-id "<API_CLIENT_ID>" \
#       --tenant-id "<TENANT_ID>"
###############################################################################

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
RESOURCE_GROUP=""
ENVIRONMENT=""
SPA_CLIENT_ID=""
API_CLIENT_ID=""
TENANT_ID=""
LOCATION="canadacentral"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Builds and deploys the Evidence Portal SPA and API to Azure.

Required:
  --resource-group   Azure resource group name
  --environment      Environment name (e.g., dev, staging, prod)
  --spa-client-id    SPA application (client) ID
  --api-client-id    API application (client) ID
  --tenant-id        Azure AD tenant ID

Optional:
  --location         Azure region (default: canadacentral)
  -h, --help         Show this help message

Examples:
  $(basename "$0") --resource-group rg-evidence-dev --environment dev \\
      --spa-client-id "00000000-..." --api-client-id "00000000-..." \\
      --tenant-id "00000000-..."
EOF
    exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
        --environment)    ENVIRONMENT="$2"; shift 2 ;;
        --spa-client-id)  SPA_CLIENT_ID="$2"; shift 2 ;;
        --api-client-id)  API_CLIENT_ID="$2"; shift 2 ;;
        --tenant-id)      TENANT_ID="$2"; shift 2 ;;
        --location)       LOCATION="$2"; shift 2 ;;
        -h|--help)        usage ;;
        *) echo "ERROR: Unknown option $1"; usage ;;
    esac
done

# Validate required parameters
MISSING=()
[[ -z "$RESOURCE_GROUP" ]] && MISSING+=("--resource-group")
[[ -z "$ENVIRONMENT" ]]    && MISSING+=("--environment")
[[ -z "$SPA_CLIENT_ID" ]]  && MISSING+=("--spa-client-id")
[[ -z "$API_CLIENT_ID" ]]  && MISSING+=("--api-client-id")
[[ -z "$TENANT_ID" ]]      && MISSING+=("--tenant-id")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "ERROR: Missing required parameters: ${MISSING[*]}"
    usage
fi

# ---------------------------------------------------------------------------
# Verify prerequisites
# ---------------------------------------------------------------------------
echo "==> Checking prerequisites..."

for cmd in az node npm mvn; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '${cmd}' is not installed or not on PATH."
        exit 1
    fi
done

if ! az account show &>/dev/null; then
    echo "ERROR: Not logged in to Azure CLI. Run 'az login' first."
    exit 1
fi

echo "    All prerequisites satisfied"

# ---------------------------------------------------------------------------
# Step 1 — Build Angular SPA
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 1: Building Angular SPA..."

cd "${REPO_ROOT}/sample-app/spa"
npm ci
npx ng build --configuration production

SPA_DIST_DIR="${REPO_ROOT}/sample-app/spa/dist/spa/browser"
if [[ ! -d "${SPA_DIST_DIR}" ]]; then
    # Fallback — Angular may output to dist/spa/ directly
    SPA_DIST_DIR="${REPO_ROOT}/sample-app/spa/dist/spa"
fi

echo "    SPA build complete: ${SPA_DIST_DIR}"

# ---------------------------------------------------------------------------
# Step 2 — Build Spring Boot API
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 2: Building Spring Boot API..."

cd "${REPO_ROOT}/sample-app/api"
mvn clean package -DskipTests

API_JAR=$(find "${REPO_ROOT}/sample-app/api/target" -name "*.jar" -not -name "*-sources.jar" -not -name "*-javadoc.jar" | head -1)

if [[ -z "${API_JAR}" ]]; then
    echo "ERROR: No JAR file found in sample-app/api/target/"
    exit 1
fi

echo "    API build complete: ${API_JAR}"

# ---------------------------------------------------------------------------
# Step 3 — Create resource group (if not exists)
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 3: Ensuring resource group exists..."

az group create \
    --name "${RESOURCE_GROUP}" \
    --location "${LOCATION}" \
    --output none

echo "    Resource group '${RESOURCE_GROUP}' ready in ${LOCATION}"

# ---------------------------------------------------------------------------
# Step 4 — Deploy infrastructure via Bicep
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 4: Deploying infrastructure via Bicep..."

DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "${REPO_ROOT}/infra/main.bicep" \
    --parameters "${REPO_ROOT}/infra/main.bicepparam" \
    --parameters environmentName="${ENVIRONMENT}" \
    --query "properties.outputs" \
    -o json)

# Extract output values
SPA_APP_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | python3 -c "import sys,json; print(json.load(sys.stdin)['spaAppName']['value'])" 2>/dev/null || \
               echo "app-evidence-spa-${ENVIRONMENT}")
API_APP_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | python3 -c "import sys,json; print(json.load(sys.stdin)['apiAppName']['value'])" 2>/dev/null || \
               echo "app-evidence-api-${ENVIRONMENT}")
STORAGE_ACCOUNT_NAME=$(echo "${DEPLOYMENT_OUTPUT}" | python3 -c "import sys,json; print(json.load(sys.stdin)['storageAccountName']['value'])" 2>/dev/null || \
                       echo "stevidence${ENVIRONMENT}")

echo "    Infrastructure deployed"
echo "    SPA App Service:    ${SPA_APP_NAME}"
echo "    API App Service:    ${API_APP_NAME}"
echo "    Storage Account:    ${STORAGE_ACCOUNT_NAME}"

# ---------------------------------------------------------------------------
# Step 5 — Deploy SPA to App Service
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 5: Deploying SPA to App Service..."

SPA_ZIP="/tmp/evidence-spa-${ENVIRONMENT}.zip"
cd "${SPA_DIST_DIR}"
zip -r "${SPA_ZIP}" . --quiet

az webapp deploy \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${SPA_APP_NAME}" \
    --src-path "${SPA_ZIP}" \
    --type zip \
    --output none

rm -f "${SPA_ZIP}"
echo "    SPA deployed to ${SPA_APP_NAME}"

# ---------------------------------------------------------------------------
# Step 6 — Deploy API to App Service
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 6: Deploying API JAR to App Service..."

az webapp deploy \
    --resource-group "${RESOURCE_GROUP}" \
    --name "${API_APP_NAME}" \
    --src-path "${API_JAR}" \
    --type jar \
    --output none

echo "    API deployed to ${API_APP_NAME}"

# ---------------------------------------------------------------------------
# Step 7 — Configure app settings
# ---------------------------------------------------------------------------
echo ""
echo "==> Step 7: Configuring app settings..."

API_BASE_URL="https://${API_APP_NAME}.azurewebsites.net"

"${SCRIPT_DIR}/configure-app-settings.sh" \
    --resource-group "${RESOURCE_GROUP}" \
    --spa-app-name "${SPA_APP_NAME}" \
    --api-app-name "${API_APP_NAME}" \
    --spa-client-id "${SPA_CLIENT_ID}" \
    --api-client-id "${API_CLIENT_ID}" \
    --tenant-id "${TENANT_ID}" \
    --storage-account-name "${STORAGE_ACCOUNT_NAME}" \
    --api-base-url "${API_BASE_URL}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "============================================================"
echo " Deployment Complete"
echo "============================================================"
echo ""
echo " Resource Group:  ${RESOURCE_GROUP}"
echo " Environment:     ${ENVIRONMENT}"
echo " SPA URL:         https://${SPA_APP_NAME}.azurewebsites.net"
echo " API URL:         ${API_BASE_URL}"
echo ""
echo " Next steps:"
echo "   1. Assign CaseReader / CaseAdmin roles to users"
echo "   2. Upload sample evidence PDFs to storage container 'evidence'"
echo "   3. Browse to the SPA URL and sign in"
echo "============================================================"
