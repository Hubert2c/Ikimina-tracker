#!/usr/bin/env bash
# =============================================================================
# One-time setup that connects GitHub Actions (cd.yml) to the AWS environment
# created by Terraform. Run it from the repository root AFTER
# `terraform apply`, on a machine where `gh auth login` is done.
#
#   bash scripts/setup-github-deploy.sh [path/to/ssh/private/key]
#
# Terraform already created the AWS side (terraform/github_oidc.tf): an IAM
# role that ONLY this repo's "production" environment can assume through
# OIDC, allowed to push to ECR and edit the bastion's SSH rule. No AWS access
# key is created or stored anywhere.
#
# What this script does (safe to run again):
#   1. Creates the GitHub "production" environment.
#   2. Stores the deployment settings there: variables (role, region,
#      registry, IPs, IDs) and secrets (SSH key, database URL).
# =============================================================================
set -euo pipefail

KEY_FILE="${1:-$HOME/.ssh/id_ed25519}"
ENVIRONMENT="production"

for tool in gh terraform; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool"; exit 1; }
done
[ -f "$KEY_FILE" ] || { echo "SSH private key not found: $KEY_FILE"; exit 1; }

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
tf() { terraform -chdir=terraform output -raw "$1"; }

echo "==> Reading Terraform outputs"
AWS_ROLE_ARN=$(tf github_deploy_role_arn)
AWS_REGION=$(tf aws_region)
ECR_REGISTRY=$(tf ecr_registry)
BASTION_IP=$(tf bastion_public_ip)
BASTION_SG_ID=$(tf bastion_security_group_id)
APP_PRIVATE_IP=$(tf app_private_ip)
ADMIN_USERNAME=$(tf admin_username)
APP_URL=$(tf app_url)
DATABASE_URL=$(tf database_url)

echo "==> GitHub environment '$ENVIRONMENT' in $REPO"
gh api --method PUT "repos/$REPO/environments/$ENVIRONMENT" --silent

setvar() { gh variable set "$1" --env "$ENVIRONMENT" --repo "$REPO" --body "$2"; }
setvar AWS_ROLE_ARN "$AWS_ROLE_ARN"
setvar AWS_REGION "$AWS_REGION"
setvar ECR_REGISTRY "$ECR_REGISTRY"
setvar BASTION_IP "$BASTION_IP"
setvar BASTION_SG_ID "$BASTION_SG_ID"
setvar APP_PRIVATE_IP "$APP_PRIVATE_IP"
setvar ADMIN_USERNAME "$ADMIN_USERNAME"
setvar APP_URL "$APP_URL"
# ECR_REGISTRY is also a repository variable: cd.yml uses it to skip the
# deployment jobs until this setup has been done.
gh variable set ECR_REGISTRY --repo "$REPO" --body "$ECR_REGISTRY"

gh secret set SSH_PRIVATE_KEY --env "$ENVIRONMENT" --repo "$REPO" < "$KEY_FILE"
printf '%s' "$DATABASE_URL" | gh secret set DATABASE_URL --env "$ENVIRONMENT" --repo "$REPO"

echo
echo "Done. GitHub Actions can now deploy to AWS."
echo "  Live URL (after the first deploy): $APP_URL"
echo "  First deploy: gh workflow run cd.yml --ref main   (or merge any PR)"
