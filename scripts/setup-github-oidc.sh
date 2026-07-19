#!/usr/bin/env bash
# setup-github-oidc.sh
#
# Automates the GitHub Actions ↔ Azure OIDC federation that replaces stored secrets.
# Run this once after `terraform apply` (Phase 1) to wire up CI/CD.
#
# Usage:
#   ./scripts/setup-github-oidc.sh \
#     --org  gvreddylab \
#     --repo azure-llmops-project \
#     --resource-group rg-llmops-learning \
#     --acr  llmopslearnacr
#
# Prerequisites:
#   - az CLI logged in (az login)
#   - Caller must have Application Administrator (or Global Administrator) in Azure AD
#   - jq installed

set -euo pipefail

# ── Defaults (override via flags) ─────────────────────────────────────────────
GITHUB_ORG=""
GITHUB_REPO=""
RESOURCE_GROUP="rg-llmops-learning"
ACR_NAME="llmopslearnacr"
APP_NAME="llmops-github-actions"

usage() {
  echo "Usage: $0 --org <github-org> --repo <github-repo> [--resource-group <rg>] [--acr <acr-name>]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --org)            GITHUB_ORG="$2";      shift 2 ;;
    --repo)           GITHUB_REPO="$2";     shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2";  shift 2 ;;
    --acr)            ACR_NAME="$2";        shift 2 ;;
    *) usage ;;
  esac
done

[[ -z "$GITHUB_ORG"  ]] && { echo "ERROR: --org is required";  usage; }
[[ -z "$GITHUB_REPO" ]] && { echo "ERROR: --repo is required"; usage; }

# ── Prerequisites check ────────────────────────────────────────────────────────
command -v az  >/dev/null || { echo "ERROR: az CLI not found"; exit 1; }
command -v jq  >/dev/null || { echo "ERROR: jq not found (brew install jq / apt install jq)"; exit 1; }

SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

echo ""
echo "==> Subscription : $SUBSCRIPTION_ID"
echo "==> Tenant       : $TENANT_ID"
echo "==> GitHub repo  : $GITHUB_ORG/$GITHUB_REPO"
echo ""

# ── 1. App Registration (idempotent) ──────────────────────────────────────────
echo "==> Checking for existing App Registration '$APP_NAME'..."
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [[ -z "$APP_ID" || "$APP_ID" == "None" ]]; then
  echo "    Creating App Registration..."
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  echo "    Created: $APP_ID"
else
  echo "    Already exists: $APP_ID"
fi

# ── 2. Service Principal (idempotent) ─────────────────────────────────────────
echo "==> Ensuring Service Principal exists..."
SP_OBJECT_ID=$(az ad sp show --id "$APP_ID" --query id -o tsv 2>/dev/null || true)

if [[ -z "$SP_OBJECT_ID" || "$SP_OBJECT_ID" == "None" ]]; then
  echo "    Creating Service Principal..."
  SP_OBJECT_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
  echo "    Created: $SP_OBJECT_ID"
else
  echo "    Already exists: $SP_OBJECT_ID"
fi

# ── 3. Role assignments ────────────────────────────────────────────────────────
RG_SCOPE="/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"
ACR_SCOPE="$RG_SCOPE/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME"

assign_role() {
  local role="$1" scope="$2"
  local existing
  existing=$(az role assignment list \
    --assignee "$SP_OBJECT_ID" --role "$role" --scope "$scope" \
    --query "[0].id" -o tsv 2>/dev/null || true)
  if [[ -z "$existing" || "$existing" == "None" ]]; then
    echo "    Assigning '$role'..."
    az role assignment create \
      --assignee-object-id "$SP_OBJECT_ID" \
      --assignee-principal-type ServicePrincipal \
      --role "$role" --scope "$scope" --output none
  else
    echo "    '$role' already assigned"
  fi
}

echo "==> Role assignments..."
# AcrPush: needed for 'docker push' in CI
assign_role "AcrPush" "$ACR_SCOPE"
# Contributor on RG: needed for 'az containerapp update'
assign_role "Contributor" "$RG_SCOPE"

# ── 4. Federated credential (idempotent) ──────────────────────────────────────
CRED_NAME="github-actions-main"
SUBJECT="repo:${GITHUB_ORG}/${GITHUB_REPO}:ref:refs/heads/main"

echo "==> Federated credential for subject: $SUBJECT"

EXISTING_CRED=$(az ad app federated-credential list --id "$APP_ID" \
  --query "[?name=='$CRED_NAME'].id" -o tsv 2>/dev/null || true)

if [[ -z "$EXISTING_CRED" || "$EXISTING_CRED" == "None" ]]; then
  echo "    Creating federated credential..."
  az ad app federated-credential create --id "$APP_ID" --parameters "$(cat <<JSON
{
  "name": "$CRED_NAME",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "$SUBJECT",
  "description": "GitHub Actions main branch OIDC trust",
  "audiences": ["api://AzureADTokenExchange"]
}
JSON
)" --output none
  echo "    Created."
else
  echo "    Already exists."
fi

# ── 5. Print GitHub secrets ────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════"
echo " Add these three secrets to your GitHub repository:"
echo " Settings → Secrets and variables → Actions → New repository secret"
echo "════════════════════════════════════════════════════════"
echo ""
echo "  AZURE_CLIENT_ID       = $APP_ID"
echo "  AZURE_TENANT_ID       = $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID = $SUBSCRIPTION_ID"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
echo "NOTE: If CI/CD fails with 'subject does not match', check the exact"
echo "      subject claim in the Actions run log under ACTIONS_ID_TOKEN_REQUEST_URL."
echo "      GitHub appends a numeric @id suffix for renamed orgs/repos."
echo "      Update the federated credential subject to match exactly."
echo ""
