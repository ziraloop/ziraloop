#!/bin/bash

# Deploy script for Connect app to AWS S3 + CloudFront
#
# Usage:
#   ./scripts/deploy.sh <environment>
#
# Environment:
#   - dev:    deploys to connect.dev.llmvault.dev
#   - prod:   deploys to connect.llmvault.dev
#
# Required:
#   - AWS CLI configured (aws configure or env vars)
#   - Stack must be deployed first via CDK

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${CYAN}[STEP]${NC} $1"
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CDK_DIR="${PROJECT_ROOT}/infrastructure/cdk"
APP_DIR="${SCRIPT_DIR}/.."

# Environment configuration
ENV="${1:-}"

if [[ -z "$ENV" ]]; then
    log_error "Environment not specified"
    echo ""
    echo "Usage: $0 <environment>"
    echo ""
    echo "Environments:"
    echo "  dev   - Deploy to connect.dev.llmvault.dev"
    echo "  prod  - Deploy to connect.llmvault.dev"
    echo ""
    exit 1
fi

case "$ENV" in
    dev|development)
        ENV="dev"
        STACK_NAME="LlmVault-Dev-Connect"
        ;;
    prod|production)
        ENV="prod"
        STACK_NAME="LlmVault-Prod-Connect"
        ;;
    *)
        log_error "Unknown environment: $ENV"
        echo ""
        echo "Valid environments: dev, prod"
        exit 1
        ;;
esac

echo ""
echo "========================================"
echo "  Deploy Connect App"
echo "  Environment: $ENV"
echo "========================================"
echo ""

# Get stack outputs from CloudFormation
log_step "Fetching infrastructure details from CloudFormation..."
log_info "Stack: $STACK_NAME"

if ! aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region us-east-2 &>/dev/null; then
    log_error "Stack '$STACK_NAME' not found or not accessible"
    log_info "Has the infrastructure been deployed?"
    log_info "Run: cd infrastructure/cdk && npx cdk deploy $STACK_NAME"
    exit 1
fi

get_output() {
    local key="$1"
    aws cloudformation describe-stacks \
        --stack-name "$STACK_NAME" \
        --region us-east-2 \
        --query "Stacks[0].Outputs[?OutputKey=='$key'].OutputValue" \
        --output text
}

BUCKET_NAME=$(get_output "S3BucketName")
DISTRIBUTION_ID=$(get_output "DistributionId")
DOMAIN=$(get_output "ConnectDomain")
CLOUDFRONT_DOMAIN=$(get_output "CloudFrontDomain")

if [[ -z "$BUCKET_NAME" || "$BUCKET_NAME" == "None" ]]; then
    log_error "Failed to get S3BucketName from stack outputs"
    exit 1
fi

if [[ -z "$DISTRIBUTION_ID" || "$DISTRIBUTION_ID" == "None" ]]; then
    log_error "Failed to get DistributionId from stack outputs"
    exit 1
fi

log_success "Found infrastructure:"
log_info "  S3 Bucket:     $BUCKET_NAME"
log_info "  CloudFront ID: $DISTRIBUTION_ID"
log_info "  Domain:        $DOMAIN"
log_info "  CloudFront:    $CLOUDFRONT_DOMAIN"
echo ""

# Build the app
log_step "Building Vite app..."
cd "$APP_DIR"

if [[ "$ENV" == "prod" ]]; then
    npm run build:prod
else
    npm run build
fi

if [[ ! -d "dist" ]]; then
    log_error "Build failed - dist directory not found"
    exit 1
fi

log_success "Build complete"
echo ""

# Sync to S3
log_step "Uploading to S3..."
log_info "Syncing dist/ to s3://$BUCKET_NAME/"

aws s3 sync dist/ "s3://$BUCKET_NAME/" \
    --delete \
    --cache-control "max-age=31536000,immutable" \
    --exclude "*.html" \
    --exclude "*.json"

# HTML and JSON files with no-cache
aws s3 sync dist/ "s3://$BUCKET_NAME/" \
    --delete \
    --cache-control "no-cache,no-store,must-revalidate" \
    --include "*.html" \
    --include "*.json"

log_success "Upload complete"
echo ""

# Invalidate CloudFront cache
log_step "Invalidating CloudFront cache..."
log_info "Distribution: $DISTRIBUTION_ID"

INVALIDATION_RESULT=$(aws cloudfront create-invalidation \
    --distribution-id "$DISTRIBUTION_ID" \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text)

if [[ -z "$INVALIDATION_RESULT" || "$INVALIDATION_RESULT" == "None" ]]; then
    log_warn "Invalidation may have failed - check AWS console"
else
    log_success "Invalidation created: $INVALIDATION_RESULT"
fi

echo ""
echo "========================================"
log_success "Deployment complete!"
echo "========================================"
echo ""
log_info "Domain:    https://$DOMAIN"
log_info "CloudFront: https://$CLOUDFRONT_DOMAIN"
echo ""

# Check if custom domain CNAME is set up
if [[ -n "$DOMAIN" && -n "$CLOUDFRONT_DOMAIN" ]]; then
    log_info "Note: Ensure DNS CNAME record exists:"
    log_info "  $DOMAIN → $CLOUDFRONT_DOMAIN"
fi

echo ""
