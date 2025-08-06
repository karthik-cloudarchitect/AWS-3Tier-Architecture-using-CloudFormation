#!/bin/bash

# AWS 3-Tier Architecture Deployment Script
# This script deploys the complete 3-tier architecture using CloudFormation stacks

set -e  # Exit on any error

# Configuration
AWS_REGION=${AWS_REGION:-"us-east-1"}
STACK_PREFIX=${STACK_PREFIX:-"3tier-app"}
KEY_PAIR_NAME=${KEY_PAIR_NAME:-"sshbastion"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if AWS CLI is configured
check_aws_config() {
    print_status "Checking AWS CLI configuration..."
    if ! aws sts get-caller-identity > /dev/null 2>&1; then
        print_error "AWS CLI is not configured or credentials are invalid"
        exit 1
    fi
    print_success "AWS CLI is properly configured"
}

# Function to check if key pair exists
check_key_pair() {
    print_status "Checking if key pair '$KEY_PAIR_NAME' exists..."
    if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" > /dev/null 2>&1; then
        print_error "Key pair '$KEY_PAIR_NAME' does not exist in region '$AWS_REGION'"
        print_status "Please create the key pair or set KEY_PAIR_NAME environment variable"
        exit 1
    fi
    print_success "Key pair '$KEY_PAIR_NAME' exists"
}

# Function to deploy a CloudFormation stack
deploy_stack() {
    local stack_name=$1
    local template_file=$2
    local parameters=$3
    
    print_status "Deploying stack: $stack_name"
    
    if aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" > /dev/null 2>&1; then
        print_warning "Stack '$stack_name' already exists, updating..."
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "$parameters" \
            --capabilities CAPABILITY_IAM \
            --region "$AWS_REGION" || print_warning "No updates to perform"
    else
        print_status "Creating new stack '$stack_name'..."
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "$parameters" \
            --capabilities CAPABILITY_IAM \
            --region "$AWS_REGION"
    fi
    
    print_status "Waiting for stack '$stack_name' to complete..."
    aws cloudformation wait stack-create-complete --stack-name "$stack_name" --region "$AWS_REGION" 2>/dev/null || \
    aws cloudformation wait stack-update-complete --stack-name "$stack_name" --region "$AWS_REGION" 2>/dev/null
    
    print_success "Stack '$stack_name' deployed successfully"
}

# Main deployment function
main() {
    print_status "Starting 3-Tier Architecture Deployment"
    print_status "Region: $AWS_REGION"
    print_status "Stack Prefix: $STACK_PREFIX"
    print_status "Key Pair: $KEY_PAIR_NAME"
    
    # Pre-deployment checks
    check_aws_config
    check_key_pair
    
    # Deploy stacks in order
    deploy_stack "${STACK_PREFIX}-network" "cfn-templates/network-stack.yaml" ""
    deploy_stack "${STACK_PREFIX}-database" "cfn-templates/db-stack.yaml" "ParameterKey=NetworkStackName,ParameterValue=${STACK_PREFIX}-network"
    deploy_stack "${STACK_PREFIX}-alb" "cfn-templates/alb-stack.yaml" "ParameterKey=NetworkStackName,ParameterValue=${STACK_PREFIX}-network"
    deploy_stack "${STACK_PREFIX}-web" "cfn-templates/web-tier-stack.yaml" "ParameterKey=NetworkStackName,ParameterValue=${STACK_PREFIX}-network ParameterKey=ALBStackName,ParameterValue=${STACK_PREFIX}-alb ParameterKey=KeyPairName,ParameterValue=${KEY_PAIR_NAME}"
    deploy_stack "${STACK_PREFIX}-app" "cfn-templates/app-tier-stack.yaml" "ParameterKey=NetworkStackName,ParameterValue=${STACK_PREFIX}-network ParameterKey=ALBStackName,ParameterValue=${STACK_PREFIX}-alb ParameterKey=DatabaseStackName,ParameterValue=${STACK_PREFIX}-database ParameterKey=KeyPairName,ParameterValue=${KEY_PAIR_NAME}"
    
    print_success "All stacks deployed successfully!"
    print_status "Getting application URL..."
    
    # Get the ALB DNS name
    ALB_DNS=$(aws cloudformation describe-stacks \
        --stack-name "${STACK_PREFIX}-alb" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ALBDNSName`].OutputValue' \
        --output text)
    
    if [ -n "$ALB_DNS" ]; then
        print_success "Application URL: http://$ALB_DNS"
    else
        print_warning "Could not retrieve application URL"
    fi
}

# Help function
show_help() {
    echo "AWS 3-Tier Architecture Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Environment Variables:"
    echo "  AWS_REGION        AWS region (default: us-east-1)"
    echo "  STACK_PREFIX      CloudFormation stack prefix (default: 3tier-app)"
    echo "  KEY_PAIR_NAME     EC2 key pair name (default: sshbastion)"
    echo ""
    echo "Options:"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with defaults"
    echo "  AWS_REGION=us-west-2 $0              # Deploy to us-west-2"
    echo "  STACK_PREFIX=myapp $0                # Use custom stack prefix"
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac