#!/bin/bash
#
# Cleanup script for Red Hat GitOps Operator
# This script ensures proper cleanup order:
# 1. Remove Helm release (if exists)
# 2. Clean up ArgoCD instance and GitOps Service CR
# 3. Clean up operator subscription and CSV
# 4. Remove namespaces (optional)
#
# Usage: ./scripts/cleanup-gitops.sh [OPTIONS]

set -e

# Default values
RELEASE_NAME="fusion-gitops"
RELEASE_NAMESPACE="fusion-gitops"
ARGOCD_NAME="openshift-gitops"
ARGOCD_NAMESPACE="openshift-gitops"
OPERATOR_NAMESPACE="openshift-gitops-operator"
KEEP_OPERATOR=false
KEEP_NAMESPACE=false
FORCE=false
DRY_RUN=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
  cat << EOF
Usage: $0 [OPTIONS]

Cleanup Red Hat GitOps Operator with proper ordering.

OPTIONS:
  --release-name NAME        Helm release name (default: fusion-gitops)
  --namespace NAMESPACE      Helm release namespace (default: fusion-gitops)
  --argocd-name NAME         ArgoCD instance name (default: openshift-gitops)
  --argocd-namespace NS      ArgoCD namespace (default: openshift-gitops)
  --operator-namespace NS    Operator namespace (default: openshift-gitops-operator)
  --keep-operator            Keep operator installed (remove instances only)
  --keep-namespace           Don't delete namespaces
  --force                    Skip confirmation prompts
  --dry-run                  Show what would be done without doing it
  -h, --help                 Show this help message

EXAMPLES:
  # Basic cleanup
  $0

  # Keep operator, remove instances only
  $0 --keep-operator

  # Dry run
  $0 --dry-run

  # Custom configuration
  $0 --namespace openshift-gitops --argocd-name my-argocd

EOF
  exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --release-name)
      RELEASE_NAME="$2"
      shift 2
      ;;
    --namespace)
      RELEASE_NAMESPACE="$2"
      shift 2
      ;;
    --argocd-name)
      ARGOCD_NAME="$2"
      shift 2
      ;;
    --argocd-namespace)
      ARGOCD_NAMESPACE="$2"
      shift 2
      ;;
    --operator-namespace)
      OPERATOR_NAMESPACE="$2"
      shift 2
      ;;
    --keep-operator)
      KEEP_OPERATOR=true
      shift
      ;;
    --keep-namespace)
      KEEP_NAMESPACE=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_usage
      ;;
    *)
      log_error "Unknown option: $1"
      show_usage
      ;;
  esac
done

run_command() {
  local cmd="$1"
  local description="$2"
  
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would run: $cmd"
    return 0
  fi
  
  log_info "$description"
  if eval "$cmd"; then
    log_success "$description completed"
    return 0
  else
    log_warning "$description failed (continuing)"
    return 1
  fi
}

wait_for_deletion() {
  local resource_type="$1"
  local resource_name="$2"
  local namespace="$3"
  local timeout=60
  local elapsed=0
  
  if [ "$DRY_RUN" = true ]; then
    return 0
  fi
  
  log_info "Waiting for $resource_type/$resource_name to be deleted..."
  while oc get "$resource_type" "$resource_name" -n "$namespace" &>/dev/null; do
    if [ $elapsed -ge $timeout ]; then
      log_warning "Timeout waiting for $resource_type/$resource_name deletion"
      return 1
    fi
    echo -n "."
    sleep 2
    elapsed=$((elapsed + 2))
  done
  echo ""
  return 0
}

confirm_action() {
  if [ "$FORCE" = true ]; then
    return 0
  fi
  
  log_warning "This will remove:"
  echo "  - GitOps Service CR (if exists)"
  echo "  - ArgoCD instance: $ARGOCD_NAME in namespace $ARGOCD_NAMESPACE"
  if [ "$KEEP_OPERATOR" = false ]; then
    echo "  - GitOps operator subscription and CSV"
  fi
  if [ "$KEEP_NAMESPACE" = false ]; then
    echo "  - Namespaces: $RELEASE_NAMESPACE, $ARGOCD_NAMESPACE, $OPERATOR_NAMESPACE"
  fi
  echo ""
  read -p "Continue? (yes/no): " -r
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    log_info "Cleanup cancelled"
    exit 0
  fi
}

# Main cleanup process
main() {
  log_info "Starting GitOps cleanup"
  log_info "Release: $RELEASE_NAME in namespace $RELEASE_NAMESPACE"
  log_info "ArgoCD: $ARGOCD_NAME in namespace $ARGOCD_NAMESPACE"
  log_info "Operator namespace: $OPERATOR_NAMESPACE"
  echo ""
  
  # Confirm
  confirm_action
  
  # Step 1: Remove Helm release
  log_info "========================================="
  log_info "Step 1: Removing Helm release"
  log_info "========================================="
  
  if helm list -n "$RELEASE_NAMESPACE" 2>/dev/null | grep -q "$RELEASE_NAME"; then
    run_command "helm uninstall $RELEASE_NAME -n $RELEASE_NAMESPACE --wait" \
                "Uninstalling Helm release $RELEASE_NAME"
    sleep 5
  else
    log_info "Helm release $RELEASE_NAME not found"
  fi
  echo ""
  
  # Step 2: Clean up GitOps Service and ArgoCD
  log_info "========================================="
  log_info "Step 2: Cleaning up GitOps Service and ArgoCD"
  log_info "========================================="
  
  # Delete GitOps Service (check both namespaces)
  GITOPS_SERVICE_FOUND=false
  
  # Function to force delete GitOpsService with finalizer removal
  force_delete_gitopsservice() {
    local namespace=$1
    log_info "Force deleting GitOpsService in $namespace..."
    
    # Get all GitOpsService names
    local services=$(oc get gitopsservice -n "$namespace" -o name 2>/dev/null || echo "")
    
    if [ -z "$services" ]; then
      return 0
    fi
    
    for service in $services; do
      log_info "Deleting $service in $namespace"
      
      # Try normal deletion first
      oc delete "$service" -n "$namespace" --wait=false 2>/dev/null || true
      
      # Remove finalizers if stuck
      log_info "Removing finalizers from $service"
      oc patch "$service" -n "$namespace" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      
      # Force delete
      oc delete "$service" -n "$namespace" --grace-period=0 --force 2>/dev/null || true
    done
  }
  
  # Check in operator namespace first (most common location)
  if oc get gitopsservice -n "$OPERATOR_NAMESPACE" 2>/dev/null | grep -q .; then
    log_info "Found GitOpsService in $OPERATOR_NAMESPACE"
    force_delete_gitopsservice "$OPERATOR_NAMESPACE"
    GITOPS_SERVICE_FOUND=true
    sleep 5
  else
    log_info "No GitOpsService found in $OPERATOR_NAMESPACE"
  fi
  
  # Also check in release namespace
  if oc get gitopsservice -n "$RELEASE_NAMESPACE" 2>/dev/null | grep -q .; then
    log_info "Found GitOpsService in $RELEASE_NAMESPACE"
    force_delete_gitopsservice "$RELEASE_NAMESPACE"
    GITOPS_SERVICE_FOUND=true
    sleep 5
  else
    log_info "No GitOpsService found in $RELEASE_NAMESPACE"
  fi
  
  if [ "$GITOPS_SERVICE_FOUND" = false ]; then
    log_info "No GitOpsService found"
  fi
  
  # Delete ArgoCD instance (operator creates it in openshift-gitops namespace)
  if oc get argocd "$ARGOCD_NAME" -n "$ARGOCD_NAMESPACE" &>/dev/null 2>&1; then
    run_command "oc delete argocd $ARGOCD_NAME -n $ARGOCD_NAMESPACE --wait=true --timeout=5m" \
                "Deleting ArgoCD instance $ARGOCD_NAME in $ARGOCD_NAMESPACE"
    wait_for_deletion "argocd" "$ARGOCD_NAME" "$ARGOCD_NAMESPACE"
    sleep 10
  else
    log_info "ArgoCD instance $ARGOCD_NAME not found in $ARGOCD_NAMESPACE"
  fi
  
  # Clean up HorizontalPodAutoscalers (HPAs) that may be left behind
  log_info "Cleaning up HorizontalPodAutoscalers..."
  HPA_LIST=$(oc get hpa -n "$ARGOCD_NAMESPACE" -o name 2>/dev/null || echo "")
  if [ -n "$HPA_LIST" ]; then
    log_info "Found HPAs to delete:"
    echo "$HPA_LIST" | sed 's/^/  /'
    
    for hpa in $HPA_LIST; do
      run_command "oc delete $hpa -n $ARGOCD_NAMESPACE --force --grace-period=0" \
                  "Deleting $hpa"
    done
    
    # Wait for HPAs to be deleted
    log_info "Waiting for HPAs to be removed..."
    for i in {1..12}; do
      REMAINING=$(oc get hpa -n "$ARGOCD_NAMESPACE" -o name 2>/dev/null | wc -l)
      if [ "$REMAINING" -eq 0 ]; then
        log_success "All HPAs removed"
        break
      fi
      if [ $i -eq 12 ]; then
        log_warning "Some HPAs may still exist"
        oc get hpa -n "$ARGOCD_NAMESPACE" 2>/dev/null || true
      fi
      sleep 5
    done
  else
    log_info "No HPAs found"
  fi
  
  echo ""
  
  # Step 3: Clean up operator (if not keeping)
  if [ "$KEEP_OPERATOR" = false ]; then
    log_info "========================================="
    log_info "Step 3: Cleaning up GitOps operator"
    log_info "========================================="
    
    if oc get subscription openshift-gitops-operator -n "$OPERATOR_NAMESPACE" &>/dev/null 2>&1; then
      run_command "oc delete subscription openshift-gitops-operator -n $OPERATOR_NAMESPACE" \
                  "Deleting operator subscription"
    fi
    
    CSV=$(oc get csv -n "$OPERATOR_NAMESPACE" -o name 2>/dev/null | grep gitops-operator || echo "")
    if [ -n "$CSV" ]; then
      run_command "oc delete $CSV -n $OPERATOR_NAMESPACE" \
                  "Deleting ClusterServiceVersion"
    fi
    
    sleep 10
    echo ""
  else
    log_info "Keeping operator (--keep-operator flag set)"
    echo ""
  fi
  
  # Step 4: Remove namespaces (if not keeping)
  if [ "$KEEP_NAMESPACE" = false ]; then
    log_info "========================================="
    log_info "Step 4: Removing namespaces"
    log_info "========================================="
    
    # Delete release namespace if different from ArgoCD namespace
    if [ "$RELEASE_NAMESPACE" != "$ARGOCD_NAMESPACE" ]; then
      if oc get namespace "$RELEASE_NAMESPACE" &>/dev/null 2>&1; then
        run_command "oc delete namespace $RELEASE_NAMESPACE --wait=true --timeout=5m" \
                    "Deleting namespace $RELEASE_NAMESPACE"
      fi
    fi
    
    # Delete ArgoCD namespace (usually openshift-gitops)
    if oc get namespace "$ARGOCD_NAMESPACE" &>/dev/null 2>&1; then
      run_command "oc delete namespace $ARGOCD_NAMESPACE --wait=true --timeout=5m" \
                  "Deleting namespace $ARGOCD_NAMESPACE"
    fi
    
    # Delete operator namespace
    if oc get namespace "$OPERATOR_NAMESPACE" &>/dev/null 2>&1; then
      run_command "oc delete namespace $OPERATOR_NAMESPACE --wait=true --timeout=5m" \
                  "Deleting namespace $OPERATOR_NAMESPACE"
    fi
    echo ""
  else
    log_info "Keeping namespaces (--keep-namespace flag set)"
    echo ""
  fi
  
  # Verification
  log_info "========================================="
  log_info "Verification"
  log_info "========================================="
  
  ISSUES=0
  
  # Check for GitOpsService in both namespaces
  GITOPS_SERVICE_EXISTS=false
  
  # Check operator namespace
  GITOPS_IN_OPERATOR=$(oc get gitopsservice -n "$OPERATOR_NAMESPACE" 2>/dev/null | grep -v "^NAME" | wc -l)
  if [ "$GITOPS_IN_OPERATOR" -gt 0 ]; then
    log_warning "GitOpsService still exists in $OPERATOR_NAMESPACE"
    oc get gitopsservice -n "$OPERATOR_NAMESPACE" 2>/dev/null
    GITOPS_SERVICE_EXISTS=true
    ISSUES=$((ISSUES + 1))
  fi
  
  # Check release namespace
  GITOPS_IN_RELEASE=$(oc get gitopsservice -n "$RELEASE_NAMESPACE" 2>/dev/null | grep -v "^NAME" | wc -l)
  if [ "$GITOPS_IN_RELEASE" -gt 0 ]; then
    log_warning "GitOpsService still exists in $RELEASE_NAMESPACE"
    oc get gitopsservice -n "$RELEASE_NAMESPACE" 2>/dev/null
    GITOPS_SERVICE_EXISTS=true
    ISSUES=$((ISSUES + 1))
  fi
  
  if [ "$GITOPS_SERVICE_EXISTS" = false ]; then
    log_success "GitOpsService removed"
  fi
  
  if oc get argocd "$ARGOCD_NAME" -n "$ARGOCD_NAMESPACE" &>/dev/null 2>&1; then
    log_warning "ArgoCD instance still exists in $ARGOCD_NAMESPACE"
    ISSUES=$((ISSUES + 1))
  else
    log_success "ArgoCD instance removed from $ARGOCD_NAMESPACE"
  fi
  
  if [ "$KEEP_OPERATOR" = false ]; then
    if oc get subscription openshift-gitops-operator -n "$OPERATOR_NAMESPACE" &>/dev/null 2>&1; then
      log_warning "Operator subscription still exists"
      ISSUES=$((ISSUES + 1))
    else
      log_success "Operator subscription removed"
    fi
  fi
  
  echo ""
  if [ $ISSUES -eq 0 ]; then
    log_success "========================================="
    log_success "Cleanup completed successfully!"
    log_success "========================================="
    exit 0
  else
    log_warning "========================================="
    log_warning "Cleanup completed with $ISSUES issue(s)"
    log_warning "========================================="
    exit 1
  fi
}

# Run main function
main

# Made with Bob