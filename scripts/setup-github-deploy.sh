#!/usr/bin/env bash
# =============================================================================
# One-time setup that connects GitHub Actions (cd.yml) to the Azure
# environment created by Terraform. Run it from the repository root AFTER
# `terraform apply`, on a machine where `az login` and `gh auth login` are done.
#
#   bash scripts/setup-github-deploy.sh [path/to/ssh/private/key]
#
# What it does (safe to run again; it reuses what already exists):
#   1. Creates an Entra ID app registration + service principal for GitHub.
#   2. Adds a federated credential so ONLY this repo's "production"
#      environment can log in as it (OIDC: no password or secret is stored).
#   3. Grants it Contributor on the Ikimina resource group only (push to ACR,
#      edit the bastion NSG rule during deploys). Nothing outside the group.
#   4. Creates the GitHub "production" environment and stores the deployment
#      settings: variables (names, IPs, IDs) and secrets (SSH key, DB URL).
# =============================================================================
set -euo pipefail

# Git Bash on Windows rewrites arguments that start with "/" into Windows
# paths, which breaks Azure resource IDs like /subscriptions/...
export MSYS_NO_PATHCONV=1

KEY_FILE="${1:-$HOME/.ssh/id_ed25519}"
APP_NAME="ikimina-tracker-github-cd"
ENVIRONMENT="production"

for tool in az gh terraform; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool"; exit 1; }
done
[ -f "$KEY_FILE" ] || { echo "SSH private key not found: $KEY_FILE"; exit 1; }

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
tf() { terraform -chdir=terraform output -raw "$1"; }

echo "==> Reading Terraform outputs"
RESOURCE_GROUP=$(tf resource_group_name)
ACR_NAME=$(tf acr_name)
ACR_LOGIN_SERVER=$(tf acr_login_server)
BASTION_IP=$(tf bastion_public_ip)
BASTION_NSG=$(tf public_nsg_name)
APP_PRIVATE_IP=$(tf app_private_ip)
ADMIN_USERNAME=$(tf admin_username)
APP_URL=$(tf app_url)
DATABASE_URL=$(tf database_url)

SUBSCRIPTION_ID=$(az account show --query id --output tsv)
TENANT_ID=$(az account show --query tenantId --output tsv)
RG_ID=$(az group show --name "$RESOURCE_GROUP" --query id --output tsv)

echo "==> App registration: $APP_NAME"
CLIENT_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" --output tsv)
if [ -z "$CLIENT_ID" ]; then
  CLIENT_ID=$(az ad app create --display-name "$APP_NAME" --query appId --output tsv)
fi
az ad sp show --id "$CLIENT_ID" >/dev/null 2>&1 || az ad sp create --id "$CLIENT_ID" --output none

echo "==> Federated credential for repo:$REPO:environment:$ENVIRONMENT"
if ! az ad app federated-credential list --id "$CLIENT_ID" --query "[].name" --output tsv | grep -qx "github-$ENVIRONMENT"; then
  az ad app federated-credential create --id "$CLIENT_ID" --output none --parameters "{
    \"name\": \"github-$ENVIRONMENT\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"repo:$REPO:environment:$ENVIRONMENT\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }"
fi

echo "==> Contributor role on $RESOURCE_GROUP only"
SP_ID=$(az ad sp show --id "$CLIENT_ID" --query id --output tsv)
if [ -z "$(az role assignment list --assignee "$SP_ID" --scope "$RG_ID" --role Contributor --query "[0].id" --output tsv)" ]; then
  # A new service principal can take a few seconds to appear everywhere.
  for i in 1 2 3 4 5 6; do
    az role assignment create --assignee-object-id "$SP_ID" --assignee-principal-type ServicePrincipal \
      --role Contributor --scope "$RG_ID" --output none && break
    echo "   retrying in 10 s ($i/6)"; sleep 10
  done
fi

echo "==> GitHub environment '$ENVIRONMENT' in $REPO"
gh api --method PUT "repos/$REPO/environments/$ENVIRONMENT" --silent

setvar() { gh variable set "$1" --env "$ENVIRONMENT" --repo "$REPO" --body "$2"; }
setvar AZURE_CLIENT_ID "$CLIENT_ID"
setvar AZURE_TENANT_ID "$TENANT_ID"
setvar AZURE_SUBSCRIPTION_ID "$SUBSCRIPTION_ID"
setvar RESOURCE_GROUP "$RESOURCE_GROUP"
setvar ACR_LOGIN_SERVER "$ACR_LOGIN_SERVER"
setvar BASTION_IP "$BASTION_IP"
setvar BASTION_NSG "$BASTION_NSG"
setvar APP_PRIVATE_IP "$APP_PRIVATE_IP"
setvar ADMIN_USERNAME "$ADMIN_USERNAME"
setvar APP_URL "$APP_URL"
# ACR_NAME is also a repository variable: cd.yml uses it to skip deployment
# jobs until this setup has been done.
setvar ACR_NAME "$ACR_NAME"
gh variable set ACR_NAME --repo "$REPO" --body "$ACR_NAME"

gh secret set SSH_PRIVATE_KEY --env "$ENVIRONMENT" --repo "$REPO" < "$KEY_FILE"
printf '%s' "$DATABASE_URL" | gh secret set DATABASE_URL --env "$ENVIRONMENT" --repo "$REPO"

echo
echo "Done. GitHub Actions can now deploy to Azure."
echo "  Live URL (after the first deploy): $APP_URL"
echo "  First deploy: gh workflow run cd.yml --ref main   (or merge any PR)"
