#!/bin/bash
# Unified Configuration for Bootstrap and Destroy Scripts
# Single source of truth for all project configuration
#
# CONFIGURATION HIERARCHY:
# 1. Environment variables (highest priority - set by GitHub Actions via repository variables)
# 2. Hardcoded defaults (fallback for local execution)
#
# FOR GITHUB ACTIONS:
# Set repository variables at: https://github.com/OWNER/REPO/settings/variables/actions
# These will automatically override defaults when running in CI/CD
#
# FOR LOCAL EXECUTION:
# Hardcoded defaults are used unless environment variables are explicitly set
# No environment variables are required - scripts work out of the box
#
# FOR FORKING:
# 1. Update repository variables in GitHub (recommended)
# 2. OR update the hardcoded defaults below (alternative)

set -euo pipefail

# Disable AWS CLI pager for non-interactive script execution
export AWS_PAGER=""

# =============================================================================
# PROJECT IDENTITY
# =============================================================================

# Repository name (org/repo format)
# Example: "YourOrg/your-repo"
# GitHub Actions: Set via vars.REPO_FULL_NAME (or use built-in github.repository)
# Local/Script: Can also use GITHUB_REPO env var for backward compatibility
# IMPORTANT: Replace OWNER/REPO with your actual repository (e.g., "YourOrg/your-repo")
readonly GITHUB_REPO="${REPO_FULL_NAME:-${GITHUB_REPO:-mhanyc/demo-cicd-terraform}}"

# Repository owner (extracted from repository)
# GitHub Actions: Set via vars.REPO_OWNER (or use built-in github.repository_owner)
# Local/Script: Can also use GITHUB_OWNER env var for backward compatibility
readonly GITHUB_OWNER="${REPO_OWNER:-${GITHUB_OWNER:-${GITHUB_REPO%%/*}}}"

# Short project name (used for resource naming within accounts)
# Example: "your-repo"
# GitHub Actions: Set via vars.PROJECT_SHORT_NAME
# IMPORTANT: Replace "my-project" with your actual project name
readonly PROJECT_SHORT_NAME="${PROJECT_SHORT_NAME:demo-cicd-terraform}"

# Full project name (used for globally unique resources like S3 buckets)
# Format: {owner-lowercase}-{repo-name}
# Example: "yourorg-your-repo"
# GitHub Actions: Set via vars.PROJECT_NAME
# IMPORTANT: Replace "owner-demo-cicd-terraformmy-project" with your actual project (e.g., "yourorg-your-repo")
readonly PROJECT_NAME="${PROJECT_NAME:mhanyc-demo-cicd-terraform}"

# Project OU name (extracted from repository name)
readonly PROJECT_OU_NAME="${GITHUB_REPO##*/}"

# External ID for cross-account role assumption
# GitHub Actions: Set via vars.EXTERNAL_ID
# Note: Dynamically generated from PROJECT_SHORT_NAME
readonly EXTERNAL_ID="${EXTERNAL_ID:-github-actions-${PROJECT_SHORT_NAME}}"

# =============================================================================
# RESOURCE NAMING PATTERNS
# =============================================================================
# These are derived from PROJECT_NAME and PROJECT_SHORT_NAME above
# No need to override these individually

# State bucket naming: {PREFIX}-state-{env}-{account-id}
readonly STATE_BUCKET_PREFIX="${PROJECT_NAME}"

# Lock table naming: {PREFIX}-locks-{env}
readonly LOCK_TABLE_PREFIX="${PROJECT_NAME}"

# KMS key naming: {PREFIX}-state-{env}-{account-id}
readonly KMS_KEY_PREFIX="${PROJECT_NAME}"

# IAM role naming: GitHubActions-{PREFIX}-{Env}-Role
# Note: Bash 3.2 compatible title case function (matches Terraform's title())
# Capitalizes first letter of each word (separated by hyphens, spaces, underscores)
_title_case() {
    echo "$1" | awk -F'-' '{
        for(i=1; i<=NF; i++) {
            $i = toupper(substr($i,1,1)) substr($i,2)
        }
        print
    }' OFS='-'
}
readonly IAM_ROLE_PREFIX="GitHubActions-$(_title_case "${PROJECT_SHORT_NAME}")"

# Read-only console role naming: {Title(PROJECT_SHORT_NAME)}-{env}
# Must match Terraform's title() output: "static-site" -> "Static-Site"
readonly READONLY_ROLE_PREFIX="$(_title_case "${PROJECT_SHORT_NAME}")"

# Account naming: {PREFIX}-{env}
readonly ACCOUNT_NAME_PREFIX="${PROJECT_SHORT_NAME}"

# Account email prefix: aws+{PREFIX}-{env}@domain
readonly ACCOUNT_EMAIL_PREFIX="aws+${PROJECT_SHORT_NAME}"

# Project-specific resource patterns for discovery/validation
# Note: Using tr for uppercase conversion (macOS Bash 3.x compatible)
readonly PROJECT_PATTERNS=(
    "${PROJECT_SHORT_NAME}"
    "${PROJECT_NAME}"
    "$(_title_case "${PROJECT_SHORT_NAME}")"
    "terraform-state"
    "GitHubActions"
    "cloudtrail-logs"
)

# =============================================================================
# AWS CONFIGURATION
# =============================================================================

# AWS Default Region
# GitHub Actions: Set via vars.AWS_DEFAULT_REGION
readonly AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

# Management Account ID (12 digits)
# GitHub Actions: Set via vars.MANAGEMENT_ACCOUNT_ID
# Local/Script: Loaded dynamically from AWS credentials or accounts.json
# Note: Not readonly to allow dynamic detection in bootstrap scripts
MANAGEMENT_ACCOUNT_ID="${MANAGEMENT_ACCOUNT_ID:-}"

# Environment-specific Account IDs (loaded dynamically from accounts.json or env vars)
# GitHub Actions: Set via vars.AWS_ACCOUNT_ID_DEV, vars.AWS_ACCOUNT_ID_STAGING, vars.AWS_ACCOUNT_ID_PROD
# These are loaded by load_accounts() function below, but can be overridden here if needed
: "${AWS_ACCOUNT_ID_DEV:=}"
: "${AWS_ACCOUNT_ID_STAGING:=}"
: "${AWS_ACCOUNT_ID_PROD:=}"

# =============================================================================
# PATHS (Context-aware - set by calling scripts)
# =============================================================================

# These paths are expected to be set by the calling script before sourcing config.sh
# Bootstrap scripts should set: SCRIPT_DIR, and we derive paths from there
# Destroy scripts should set: SCRIPT_DIR, and we derive paths from there

# Set default paths if not already set
: "${ACCOUNTS_FILE:=$(dirname "${BASH_SOURCE[0]}")/bootstrap/accounts.json}"

# =============================================================================
# STATE MANAGEMENT DOCUMENTATION
# =============================================================================

# Central Foundation State Bucket:
#   Name: ${PROJECT_NAME}-terraform-state-${MANAGEMENT_ACCOUNT_ID}
#   Purpose: Stores Terraform state for foundational infrastructure
#   Created: Automatically by bootstrap-foundation.sh
#   Stores state for:
#     - OIDC providers (foundations/github-oidc/)
#     - IAM management roles (foundations/iam-management/)
#     - Organization management (foundations/org-management/)
#   Access: All engineers with management account credentials
#   Region: us-east-1
#
# Per-Account State Buckets:
#   Name: ${PROJECT_NAME}-state-{env}-{account-id}
#   Purpose: Stores Terraform state for environment-specific infrastructure
#   Created: By bootstrap-foundation.sh via Terraform bootstrap module
#   Stores state for:
#     - Workload infrastructure (workloads/static-site/)
#     - Environment-specific resources
#   Access: Environment-specific deployment roles
#
# This architecture enables:
#   - Multi-engineer collaboration (shared remote state)
#   - State isolation (foundation vs environment)
#   - Scalability (easily add new accounts/environments)

# =============================================================================
# EXECUTION MODES
# =============================================================================

DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
SKIP_VERIFICATION="${SKIP_VERIFICATION:-false}"

# Destroy-specific modes
FORCE_DESTROY="${FORCE_DESTROY:-false}"
INCLUDE_CROSS_ACCOUNT="${INCLUDE_CROSS_ACCOUNT:-true}"
CLOSE_MEMBER_ACCOUNTS="${CLOSE_MEMBER_ACCOUNTS:-false}"
CLEANUP_TERRAFORM_STATE="${CLEANUP_TERRAFORM_STATE:-true}"
ACCOUNT_FILTER="${ACCOUNT_FILTER:-}"
S3_TIMEOUT="${S3_TIMEOUT:-180}"

# =============================================================================
# METADATA (For AWS Organizations Tagging and Contacts)
# =============================================================================

# Resource tags for AWS Organizations resources (OUs, accounts)
# Can be customized via environment variable or sourcing from CODEOWNERS
: "${RESOURCE_TAGS_JSON:=$(cat <<EOF
{
  "ManagedBy": "bootstrap-scripts",
  "Repository": "${GITHUB_REPO}",
  "Project": "${PROJECT_SHORT_NAME}"
}
EOF
)}"
export RESOURCE_TAGS_JSON

# Contact information for AWS accounts (optional)
# Can be customized via environment variable or sourcing from CODEOWNERS
: "${CONTACT_INFO_JSON:={}}"
export CONTACT_INFO_JSON

# =============================================================================
# COLORS
# =============================================================================

if [[ -t 1 ]]; then
    readonly RED='\033[0;31m'
    readonly GREEN='\033[0;32m'
    readonly YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m'
    readonly BOLD='\033[1m'
    readonly NC='\033[0m'
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

# =============================================================================
# DYNAMIC ACCOUNT LOADING
# =============================================================================

load_accounts() {
    local accounts_file="${ACCOUNTS_FILE:-$(dirname "${BASH_SOURCE[0]}")/bootstrap/accounts.json}"

    if [[ -f "$accounts_file" ]]; then
        MGMT_ACCOUNT=$(jq -r '.management // ""' "$accounts_file" 2>/dev/null || echo "")
        DEV_ACCOUNT=$(jq -r '.dev // ""' "$accounts_file" 2>/dev/null || echo "")
        STAGING_ACCOUNT=$(jq -r '.staging // ""' "$accounts_file" 2>/dev/null || echo "")
        PROD_ACCOUNT=$(jq -r '.prod // ""' "$accounts_file" 2>/dev/null || echo "")

        # Set MANAGEMENT_ACCOUNT_ID from accounts.json if not already set
        if [[ -z "$MANAGEMENT_ACCOUNT_ID" ]] && [[ -n "$MGMT_ACCOUNT" ]]; then
            MANAGEMENT_ACCOUNT_ID="$MGMT_ACCOUNT"
        fi
    else
        MGMT_ACCOUNT="$MANAGEMENT_ACCOUNT_ID"
        DEV_ACCOUNT=""
        STAGING_ACCOUNT=""
        PROD_ACCOUNT=""
    fi

    export MGMT_ACCOUNT DEV_ACCOUNT STAGING_ACCOUNT PROD_ACCOUNT MANAGEMENT_ACCOUNT_ID

    # Also export as array for destroy scripts
    MEMBER_ACCOUNT_IDS=()
    [[ -n "$DEV_ACCOUNT" ]] && MEMBER_ACCOUNT_IDS+=("$DEV_ACCOUNT")
    [[ -n "$STAGING_ACCOUNT" ]] && MEMBER_ACCOUNT_IDS+=("$STAGING_ACCOUNT")
    [[ -n "$PROD_ACCOUNT" ]] && MEMBER_ACCOUNT_IDS+=("$PROD_ACCOUNT")
    export MEMBER_ACCOUNT_IDS
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

require_accounts() {
    if [[ -z "$DEV_ACCOUNT" ]] || [[ -z "$STAGING_ACCOUNT" ]] || [[ -z "$PROD_ACCOUNT" ]]; then
        echo -e "${RED}ERROR:${NC} accounts.json not found or incomplete" >&2
        echo "Run: ./bootstrap-organization.sh first" >&2
        return 1
    fi
}

save_accounts() {
    local accounts_file="${ACCOUNTS_FILE:-$(dirname "${BASH_SOURCE[0]}")/bootstrap/accounts.json}"
    mkdir -p "$(dirname "$accounts_file")"

    # Build JSON with jq to handle replacements properly
    local json_content
    json_content=$(jq -n \
        --arg mgmt "$MGMT_ACCOUNT" \
        --arg dev "$DEV_ACCOUNT" \
        --arg staging "$STAGING_ACCOUNT" \
        --arg prod "$PROD_ACCOUNT" \
        '{
            management: $mgmt,
            dev: $dev,
            staging: $staging,
            prod: $prod
        }')

    # Add _replaced section if REPLACED_ACCOUNTS exists and has entries
    # Note: Using ${REPLACED_ACCOUNTS+x} for bash 3.2 compatibility (macOS default bash)
    if [[ -n "${REPLACED_ACCOUNTS+x}" ]] && [[ ${#REPLACED_ACCOUNTS[@]} -gt 0 ]]; then
        local replaced_json="{}"
        for env in "${!REPLACED_ACCOUNTS[@]}"; do
            IFS='|' read -r old_id status timestamp <<< "${REPLACED_ACCOUNTS[$env]}"
            replaced_json=$(echo "$replaced_json" | jq \
                --arg env "$env" \
                --arg old_id "$old_id" \
                --arg status "$status" \
                --arg timestamp "$timestamp" \
                '.[$env] = {
                    old_account_id: $old_id,
                    old_status: $status,
                    replaced_date: $timestamp,
                    reason: "Account was \($status)"
                }')
        done
        json_content=$(echo "$json_content" | jq --argjson replaced "$replaced_json" '. + {_replaced: $replaced}')
    fi

    echo "$json_content" > "$accounts_file"
}

# Check if resource matches project patterns
matches_project() {
    local resource_name="$1"
    local pattern

    # Handle null or empty resource names
    if [[ -z "$resource_name" ]] || [[ "$resource_name" == "null" ]]; then
        return 1
    fi

    for pattern in "${PROJECT_PATTERNS[@]}"; do
        if [[ "$resource_name" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Check account filter (destroy-specific)
check_account_filter() {
    local account_id="$1"

    if [[ -z "$ACCOUNT_FILTER" ]]; then
        return 0  # No filter, allow all
    fi

    IFS=',' read -ra ACCOUNTS <<< "$ACCOUNT_FILTER"
    for allowed_account in "${ACCOUNTS[@]}"; do
        if [[ "$account_id" == "$allowed_account" ]]; then
            return 0
        fi
    done
    return 1
}

# Get all US AWS regions (destroy-specific)
get_us_regions() {
    aws ec2 describe-regions \
        --query 'Regions[?starts_with(RegionName, `us-`)].RegionName' \
        --output text 2>/dev/null || echo "us-east-1 us-east-2 us-west-1 us-west-2"
}

# Execute function across all US regions (destroy-specific)
execute_in_all_regions() {
    local function_name="$1"
    local regions

    log_info "Executing $function_name across all US regions..."
    regions=$(get_us_regions)

    for region in $regions; do
        log_info "Processing region: $region"
        export AWS_REGION="$region"
        "$function_name" "$region"
    done

    # Reset to default region
    export AWS_REGION="$AWS_DEFAULT_REGION"
}
