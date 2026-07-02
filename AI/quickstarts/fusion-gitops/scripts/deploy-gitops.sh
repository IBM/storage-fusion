#!/bin/bash
#
# Main deployment script for Red Hat GitOps on Fusion HCI
# This script deploys using Helm directly (no Ansible required)
#

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source common functions
source "${SCRIPT_DIR}/lib/common.sh"

# Default values
HELM_CHART_PATH="${PROJECT_ROOT}/helm/fusion-gitops"
VALUES_FILE=""
RELEASE_NAME="fusion-gitops"
NAMESPACE="default"
DRY_RUN=false
SKIP_PREFLIGHT=false
SKIP_VALIDATION=false
VERBOSE=false
TIMEOUT="15m"

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy Red Hat GitOps Operator on Fusion HCI using Helm.

OPTIONS:
    -h, --help              Show this help message
    -n, --namespace NAME    Kubernetes namespace (default: default)
    -r, --release NAME      Helm release name (default: fusion-gitops)
    -f, --values FILE       Helm values file (e.g., environments/dev/values.yaml, environments/prod/values.yaml)
    -d, --dry-run           Perform a dry-run without making changes
    --skip-preflight        Skip pre-flight checks
    --skip-validation       Skip post-deployment validation
    -v, --verbose           Enable verbose output
    --force                 Skip confirmation prompts
    --timeout DURATION      Helm timeout duration (default: 15m)

EXAMPLES:
    # Development deployment (getting started)
    $0 -f helm/fusion-gitops/environments/dev/values.yaml

    # Staging deployment (pre-production testing)
    $0 -f helm/fusion-gitops/environments/stage/values.yaml

    # Default deployment (basic HA)
    $0

    # Production deployment (full HA)
    $0 -f helm/fusion-gitops/environments/prod/values.yaml

    # Dry-run deployment
    $0 --dry-run

    # Deploy to specific namespace
    $0 -n openshift-gitops

    # Verbose deployment with custom release name
    $0 -v -r my-gitops -n my-namespace

ENVIRONMENT VARIABLES:
    KUBECONFIG              Path to kubeconfig file
    DEBUG                   Enable debug output (true/false)

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -n|--namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -r|--release)
                RELEASE_NAME="$2"
                shift 2
                ;;
            -f|--values)
                VALUES_FILE="$2"
                if [ ! -f "$VALUES_FILE" ]; then
                    log_error "Values file not found: $VALUES_FILE"
                    exit 1
                fi
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --skip-preflight)
                SKIP_PREFLIGHT=true
                shift
                ;;
            --skip-validation)
                SKIP_VALIDATION=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            --force)
                export FORCE=true
                shift
                ;;
            --timeout)
                TIMEOUT="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Check prerequisites
check_prerequisites() {
    print_banner "Checking Prerequisites"
    
    # Check for required commands
    local required_commands=("helm")
    for cmd in "${required_commands[@]}"; do
        if ! command_exists "$cmd"; then
            log_error "$cmd is not installed. Please install it first."
            echo ""
            echo "Install Helm:"
            echo "  https://helm.sh/docs/intro/install/"
            exit 1
        fi
        log_success "$cmd is installed ($(helm version --short 2>/dev/null || echo 'version unknown'))"
    done
    
    # Check for kubectl or oc
    local cli=$(detect_cli)
    log_success "Using CLI: $cli"
    
    # Check cluster connectivity
    if ! $cli cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    log_success "Connected to cluster: $(get_cluster_context)"
    
    # Check Helm chart exists
    if [ ! -d "$HELM_CHART_PATH" ]; then
        log_error "Helm chart not found: $HELM_CHART_PATH"
        exit 1
    fi
    log_success "Helm chart found: $HELM_CHART_PATH"
    
    # Validate Helm chart
    log_info "Validating Helm chart..."
    if helm lint "$HELM_CHART_PATH" &> /dev/null; then
        log_success "Helm chart validation passed"
    else
        log_warning "Helm chart validation had warnings (non-fatal)"
    fi
}

# Display deployment configuration
display_config() {
    print_banner "Deployment Configuration"
    
    log_info "Release Name: $RELEASE_NAME"
    log_info "Namespace: $NAMESPACE"
    log_info "Helm Chart: $HELM_CHART_PATH"
    log_info "Values File: ${VALUES_FILE:-<default>}"
    log_info "Dry Run: $DRY_RUN"
    log_info "Skip Preflight: $SKIP_PREFLIGHT"
    log_info "Skip Validation: $SKIP_VALIDATION"
    log_info "Timeout: $TIMEOUT"
    log_info "Cluster: $(get_cluster_context)"
    
    # Show configuration type if using pre-configured values
    if [ -n "$VALUES_FILE" ]; then
        if [[ "$VALUES_FILE" == *"dev"* ]]; then
            echo ""
            log_info "📦 Configuration: DEVELOPMENT (1 replica, no HA, ephemeral storage)"
            log_info "   Resources: ~1.1 CPU, ~1.2Gi RAM"
            log_info "   Best for: Getting started, development, testing"
        elif [[ "$VALUES_FILE" == *"stage"* ]]; then
            echo ""
            log_info "📦 Configuration: STAGING (2 replicas, basic HA, 20Gi storage)"
            log_info "   Resources: ~5 CPU, ~8Gi RAM"
            log_info "   Best for: Pre-production testing, staging environments"
        elif [[ "$VALUES_FILE" == *"prod"* ]]; then
            echo ""
            log_info "📦 Configuration: PRODUCTION (3 replicas, full HA, 50Gi storage)"
            log_info "   Resources: ~8 CPU, ~12Gi RAM"
            log_info "   Best for: Mission-critical deployments"
        fi
    else
        echo ""
        log_info "📦 Configuration: DEFAULT (2 replicas, basic HA, 10Gi storage)"
        log_info "   Resources: ~3.5 CPU, ~5.5Gi RAM"
        log_info "   Best for: Standard production workloads"
    fi
    
    echo ""
}

# Confirm deployment
confirm_deployment() {
    if [ "$DRY_RUN" = true ]; then
        log_info "Running in dry-run mode. No changes will be made."
        return 0
    fi
    
    if ! confirm "Do you want to proceed with the deployment?"; then
        log_info "Deployment cancelled by user"
        exit 0
    fi
}

# Run Helm deployment
run_helm_deployment() {
    print_banner "Deploying with Helm"
    
    # Build Helm command
    local helm_cmd="helm"
    
    # Check if release already exists
    if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "^${RELEASE_NAME}"; then
        log_info "Release '$RELEASE_NAME' already exists. Upgrading..."
        helm_cmd+=" upgrade"
    else
        log_info "Installing new release '$RELEASE_NAME'..."
        helm_cmd+=" install"
    fi
    
    helm_cmd+=" ${RELEASE_NAME}"
    helm_cmd+=" ${HELM_CHART_PATH}"
    helm_cmd+=" --namespace ${NAMESPACE}"
    helm_cmd+=" --create-namespace"
    
    if [ -n "$VALUES_FILE" ]; then
        helm_cmd+=" --values ${VALUES_FILE}"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        helm_cmd+=" --dry-run --debug"
    else
        helm_cmd+=" --wait --timeout ${TIMEOUT}"
    fi
    
    if [ "$VERBOSE" = true ]; then
        helm_cmd+=" --debug"
    fi
    
    log_debug "Helm command: $helm_cmd"
    
    # Run Helm
    echo ""
    if eval "$helm_cmd"; then
        echo ""
        log_success "Helm deployment completed successfully"
        return 0
    else
        echo ""
        log_error "Helm deployment failed"
        return 1
    fi
}

# Validate deployment
validate_deployment() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    print_banner "Validating Deployment"
    
    local cli=$(detect_cli)
    
    # Wait a moment for resources to stabilize
    log_info "Waiting for resources to stabilize..."
    sleep 5
    
    # Check operator deployment
    log_info "Checking GitOps operator..."
    if $cli get deployment gitops-operator-controller-manager -n openshift-gitops-operator &> /dev/null; then
        log_success "GitOps operator is deployed"
    else
        log_warning "GitOps operator not found (may still be deploying)"
    fi
    
    # Check ArgoCD instance
    log_info "Checking ArgoCD instance..."
    if $cli get argocd openshift-gitops -n openshift-gitops &> /dev/null; then
        log_success "ArgoCD instance exists"
    else
        log_warning "ArgoCD instance not found (may still be creating)"
    fi
    
    # Check ArgoCD pods
    log_info "Checking ArgoCD pods..."
    local pod_count=$($cli get pods -n openshift-gitops -l app.kubernetes.io/part-of=argocd --no-headers 2>/dev/null | wc -l)
    if [ "$pod_count" -gt 0 ]; then
        log_success "Found $pod_count ArgoCD pod(s)"
        
        # Check if pods are running
        local running_count=$($cli get pods -n openshift-gitops -l app.kubernetes.io/part-of=argocd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [ "$running_count" -gt 0 ]; then
            log_success "$running_count pod(s) are running"
        else
            log_warning "Pods are not running yet (may still be starting)"
        fi
    else
        log_warning "No ArgoCD pods found yet (may still be creating)"
    fi
    
    # Check storage (if not dev config)
    if [ -z "$VALUES_FILE" ] || [[ "$VALUES_FILE" != *"dev"* ]]; then
        log_info "Checking persistent storage..."
        local pvc_count=$($cli get pvc -n openshift-gitops --no-headers 2>/dev/null | wc -l)
        if [ "$pvc_count" -gt 0 ]; then
            log_success "Found $pvc_count PVC(s)"
        else
            log_info "No PVCs found (may be using ephemeral storage or still creating)"
        fi
    fi
    
    echo ""
    log_info "Validation complete. Check above for any warnings."
}

# Display post-deployment information
display_post_deployment() {
    if [ "$DRY_RUN" = true ]; then
        return 0
    fi
    
    print_banner "Post-Deployment Information"
    
    local cli=$(detect_cli)
    
    # Get ArgoCD password
    log_info "Retrieving ArgoCD credentials..."
    sleep 2  # Give a moment for secret to be created
    
    local argocd_password=$(get_secret_value "openshift-gitops-cluster" "admin.password" "openshift-gitops" 2>/dev/null || echo "")
    
    if [ -n "$argocd_password" ]; then
        echo ""
        log_success "ArgoCD Credentials:"
        echo "  Username: admin"
        echo "  Password: $argocd_password"
    else
        echo ""
        log_warning "ArgoCD password not available yet. Retrieve it later with:"
        echo "  $cli get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d"
    fi
    
    echo ""
    
    # Get ArgoCD URL
    if is_openshift; then
        log_info "Retrieving ArgoCD URL..."
        local argocd_url=$(get_route_host "openshift-gitops-server" "openshift-gitops" 2>/dev/null || echo "")
        
        if [ -n "$argocd_url" ]; then
            log_success "ArgoCD URL: https://$argocd_url"
        else
            log_warning "ArgoCD route not available yet. Check with:"
            echo "  $cli get route openshift-gitops-server -n openshift-gitops"
        fi
    else
        log_info "To access ArgoCD, use port-forward:"
        echo "  $cli port-forward svc/openshift-gitops-server -n openshift-gitops 8080:443"
        echo "  Then open: https://localhost:8080"
    fi
    
    echo ""
    log_info "Next Steps:"
    echo "  1. Access the ArgoCD UI using the credentials above"
    echo "  2. Add your Git repositories"
    echo "  3. Deploy your first application"
    echo ""
}

# Main function
main() {
    # Parse arguments
    parse_args "$@"
    
    # Display banner
    print_banner "Red Hat GitOps on Fusion HCI"
    echo "Helm-based deployment (no Ansible required)"
    echo ""
    
    # Check prerequisites
    if [ "$SKIP_PREFLIGHT" = false ]; then
        check_prerequisites
    else
        log_info "Skipping pre-flight checks (--skip-preflight)"
    fi
    
    # Display configuration
    display_config
    
    # Confirm deployment
    confirm_deployment
    
    # Run Helm deployment
    if run_helm_deployment; then
        # Validate deployment
        if [ "$SKIP_VALIDATION" = false ]; then
            validate_deployment
        else
            log_info "Skipping validation (--skip-validation)"
        fi
        
        # Display post-deployment information
        display_post_deployment
        
        print_banner "Deployment Complete"
        log_success "Red Hat GitOps has been deployed successfully!"
        echo ""
        log_info "To upgrade your configuration later:"
        echo "  helm upgrade $RELEASE_NAME $HELM_CHART_PATH -n $NAMESPACE -f <new-values-file>"
        echo ""
        log_info "To uninstall:"
        echo "  helm uninstall $RELEASE_NAME -n $NAMESPACE"
        exit 0
    else
        print_banner "Deployment Failed"
        log_error "Deployment failed. Check the logs above for details."
        echo ""
        log_info "Troubleshooting:"
        echo "  - Check Helm release status: helm list -n $NAMESPACE"
        echo "  - Check Helm release history: helm history $RELEASE_NAME -n $NAMESPACE"
        echo "  - Check pod status: $cli get pods -n openshift-gitops"
        echo "  - Check events: $cli get events -n openshift-gitops --sort-by='.lastTimestamp'"
        exit 1
    fi
}

# Run main function
main "$@"

# Made with Bob
