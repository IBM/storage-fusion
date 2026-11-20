#!/usr/bin/env bash
# run-all.sh — Master orchestration script for IBM Fusion CAS + NVIDIA AI-Q
# ──────────────────────────────────────────────────────────────────────────────
# Sequentially executes all deployment stages:
#   1. Patch AI-Q Repository (01-patch-aiq.sh)
#   [Manual Review Gate] -> Verify/Commit/Push patches
#   2. Build and Push Container Images (02-build-push-image.sh)
#   3. Setup Kubernetes Secrets, Tokens & ConfigMaps (03-setup-secrets-and-token.sh)
#   4. Deploy AI-Q via Helm Chart & Configure Route (04-deploy-helm.sh)
#   5. Verify Deployment Health & End-to-End Queries (05-verify-deployment.sh)
#
# Flags:
#   --env-file <path>   Path to env file (default: ./aiq-fusion.env)
#   --from <step>       Start from step (1: patch, 2: build, 3: secrets, 4: deploy, 5: verify)
#   --only <step>       Run only specified step (1-5 or name: patch, build, secrets, deploy, verify)
#   --skip-patch        Skip Step 1 (01-patch-aiq.sh)
#   --skip-build        Skip Step 2 (02-build-push-image.sh)
#   --skip-secrets      Skip Step 3 (03-setup-secrets-and-token.sh)
#   --skip-deploy       Skip Step 4 (04-deploy-helm.sh)
#   --skip-verify       Skip Step 5 (05-verify-deployment.sh)
#   --yes, -y           Non-interactive mode (skip interactive prompts)
#   --dry-run           Check environment and print execution plan without running scripts
#   -h, --help          Show this help message
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[master]${NC} $*"; }
success() { echo -e "${GREEN}[master]${NC} ✓ $*"; }
warn()    { echo -e "${YELLOW}[master]${NC} ⚠ $*"; }
die()     { echo -e "${RED}[master]${NC} ✗ $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_FILE="${REPO_ROOT}/aiq-fusion.env"
SKIP_PATCH=false
SKIP_BUILD=false
SKIP_SECRETS=false
SKIP_DEPLOY=false
SKIP_VERIFY=false
DRY_RUN=false
NON_INTERACTIVE=false
FROM_STEP=1

usage() {
    cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

Master deployment script for IBM Fusion CAS integration with NVIDIA AI-Q.

${BOLD}Options:${NC}
  --env-file <path>   Path to configuration env file (default: ${REPO_ROOT}/aiq-fusion.env)
  --from <step>       Start from step (1: patch, 2: build, 3: secrets, 4: deploy, 5: verify)
  --only <step>       Run only specified step (1-5 or name: patch, build, secrets, deploy, verify)
  --skip-patch        Skip Step 1 (01-patch-aiq.sh)
  --skip-build        Skip Step 2 (02-build-push-image.sh)
  --skip-secrets      Skip Step 3 (03-setup-secrets-and-token.sh)
  --skip-deploy       Skip Step 4 (04-deploy-helm.sh)
  --skip-verify       Skip Step 5 (05-verify-deployment.sh)
  -y, --yes           Auto-confirm prompts (non-interactive)
  --dry-run           Check configuration and print execution plan without running scripts
  -h, --help          Show this help message

${BOLD}Two-Phase Workflow Recommendation:${NC}
  Phase 1 (Patch):    ./scripts/run-all.sh --only patch
                      Review diff, commit, and push branch in your AIQ repo
  Phase 2 (Deploy):   ./scripts/run-all.sh --from build
EOF
}

# ── Parse Arguments ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env-file)
            ENV_FILE="$2"
            shift 2
            ;;
        --from)
            case "$2" in
                1|patch)   FROM_STEP=1 ;;
                2|build)   FROM_STEP=2 ;;
                3|secrets) FROM_STEP=3 ;;
                4|deploy)  FROM_STEP=4 ;;
                5|verify)  FROM_STEP=5 ;;
                *) die "Invalid --from step: $2 (allowed: 1-5, patch, build, secrets, deploy, verify)" ;;
            esac
            shift 2
            ;;
        --only)
            case "$2" in
                1|patch)   FROM_STEP=1; SKIP_PATCH=false; SKIP_BUILD=true; SKIP_SECRETS=true; SKIP_DEPLOY=true; SKIP_VERIFY=true ;;
                2|build)   FROM_STEP=2; SKIP_PATCH=true; SKIP_BUILD=false; SKIP_SECRETS=true; SKIP_DEPLOY=true; SKIP_VERIFY=true ;;
                3|secrets) FROM_STEP=3; SKIP_PATCH=true; SKIP_BUILD=true; SKIP_SECRETS=false; SKIP_DEPLOY=true; SKIP_VERIFY=true ;;
                4|deploy)  FROM_STEP=4; SKIP_PATCH=true; SKIP_BUILD=true; SKIP_SECRETS=true; SKIP_DEPLOY=false; SKIP_VERIFY=true ;;
                5|verify)  FROM_STEP=5; SKIP_PATCH=true; SKIP_BUILD=true; SKIP_SECRETS=true; SKIP_DEPLOY=true; SKIP_VERIFY=false ;;
                *) die "Invalid --only step: $2 (allowed: 1-5, patch, build, secrets, deploy, verify)" ;;
            esac
            shift 2
            ;;
        --skip-patch)   SKIP_PATCH=true; shift ;;
        --skip-build)   SKIP_BUILD=true; shift ;;
        --skip-secrets) SKIP_SECRETS=true; shift ;;
        --skip-deploy)  SKIP_DEPLOY=true; shift ;;
        --skip-verify)  SKIP_VERIFY=true; shift ;;
        -y|--yes)       NON_INTERACTIVE=true; shift ;;
        --dry-run)      DRY_RUN=true; shift ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "Unknown argument: $1. Use --help for usage." ;;
    esac
done

# Apply FROM_STEP only if --only was NOT used (--only already set all SKIP_ flags).
# Without this guard, "--only patch" would set FROM_STEP=1, then these lines
# would no-op (FROM_STEP not > 1..4), but future edits could break that.
# Detect --only by checking if all non-target steps are skipped together.
_ONLY_MODE=false
if [[ "${SKIP_BUILD}" == "true" && "${SKIP_SECRETS}" == "true" && "${SKIP_DEPLOY}" == "true" && "${SKIP_VERIFY}" == "true" ]]; then _ONLY_MODE=true; fi
if [[ "${SKIP_PATCH}" == "true" && "${SKIP_SECRETS}" == "true" && "${SKIP_DEPLOY}" == "true" && "${SKIP_VERIFY}" == "true" ]]; then _ONLY_MODE=true; fi
if [[ "${SKIP_PATCH}" == "true" && "${SKIP_BUILD}" == "true" && "${SKIP_DEPLOY}" == "true" && "${SKIP_VERIFY}" == "true" ]]; then _ONLY_MODE=true; fi
if [[ "${SKIP_PATCH}" == "true" && "${SKIP_BUILD}" == "true" && "${SKIP_SECRETS}" == "true" && "${SKIP_VERIFY}" == "true" ]]; then _ONLY_MODE=true; fi
if [[ "${SKIP_PATCH}" == "true" && "${SKIP_BUILD}" == "true" && "${SKIP_SECRETS}" == "true" && "${SKIP_DEPLOY}" == "true" ]]; then _ONLY_MODE=true; fi

if [[ "${_ONLY_MODE}" != "true" ]]; then
    if [[ ${FROM_STEP} -gt 1 ]]; then SKIP_PATCH=true; fi
    if [[ ${FROM_STEP} -gt 2 ]]; then SKIP_BUILD=true; fi
    if [[ ${FROM_STEP} -gt 3 ]]; then SKIP_SECRETS=true; fi
    if [[ ${FROM_STEP} -gt 4 ]]; then SKIP_DEPLOY=true; fi
fi

echo -e "${BOLD}${CYAN}================================================================${NC}"
echo -e "${BOLD}${CYAN}   IBM Fusion CAS + NVIDIA AI-Q — Master Deployment Runner      ${NC}"
echo -e "${BOLD}${CYAN}================================================================${NC}"

# ── Load Environment File ────────────────────────────────────────────────────
if [[ -f "${ENV_FILE}" ]]; then
    info "Loading configuration from: ${ENV_FILE}"
    # shellcheck disable=SC1090
    set -a
    source "${ENV_FILE}"
    set +a
    success "Configuration loaded"
else
    warn "Configuration file not found at: ${ENV_FILE}"
    warn "Checking whether required environment variables are exported in shell environment..."
fi

# ── Validate Environment Variables ───────────────────────────────────────────
MISSING_VARS=()
check_var() {
    local var_name="$1"
    local required_by="$2"
    if [[ -z "${!var_name:-}" ]]; then
        MISSING_VARS+=("${var_name} (required by ${required_by})")
    fi
}

if [[ "${SKIP_PATCH}" != "true" ]]; then
    check_var "AIQ_REPO_DIR" "Step 01: Patch"
    check_var "AIQ_COMMIT"   "Step 01: Patch"
fi

if [[ "${SKIP_BUILD}" != "true" ]]; then
    check_var "AIQ_REPO_DIR"    "Step 02: Build"
    check_var "IMAGE_REGISTRY"  "Step 02: Build"
    check_var "IMAGE_NAMESPACE" "Step 02: Build"
fi

if [[ "${SKIP_SECRETS}" != "true" ]]; then
    check_var "AIQ_REPO_DIR"         "Step 03: Secrets"
    check_var "NGC_API_KEY"          "Step 03: Secrets"
    check_var "TAVILY_API_KEY"       "Step 03: Secrets"
    check_var "FUSION_CAS_URL"       "Step 03: Secrets"
    check_var "FUSION_CAS_TOKEN"     "Step 03: Secrets"
    check_var "FUSION_VECTOR_STORE_1" "Step 03: Secrets"
    check_var "FUSION_VECTOR_STORE_2" "Step 03: Secrets"
    check_var "CLUSTER_DOMAIN"       "Step 03: Secrets"
fi

if [[ "${SKIP_DEPLOY}" != "true" ]]; then
    check_var "AIQ_REPO_DIR"    "Step 04: Deploy"
    check_var "IMAGE_REGISTRY"  "Step 04: Deploy"
    check_var "IMAGE_NAMESPACE" "Step 04: Deploy"
    check_var "CLUSTER_DOMAIN"  "Step 04: Deploy"
fi

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
    echo ""
    echo -e "${RED}Missing required configuration variable(s):${NC}"
    for v in "${MISSING_VARS[@]}"; do
        echo -e "  ✗ ${v}"
    done
    echo ""
    die "Please define missing variables in ${ENV_FILE} or export them in your shell."
fi

# ── Print Execution Plan ──────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Execution Plan:${NC}"
echo -e "  Step 1: Patch AI-Q Repo     [$( [[ "${SKIP_PATCH}" == "true" ]] && echo -e "${YELLOW}SKIP${NC}" || echo -e "${GREEN}EXECUTE${NC}" )]"
echo -e "  Step 2: Build & Push Images [$( [[ "${SKIP_BUILD}" == "true" ]] && echo -e "${YELLOW}SKIP${NC}" || echo -e "${GREEN}EXECUTE${NC}" )]"
echo -e "  Step 3: Setup Secrets/Token [$( [[ "${SKIP_SECRETS}" == "true" ]] && echo -e "${YELLOW}SKIP${NC}" || echo -e "${GREEN}EXECUTE${NC}" )]"
echo -e "  Step 4: Deploy Helm Release [$( [[ "${SKIP_DEPLOY}" == "true" ]] && echo -e "${YELLOW}SKIP${NC}" || echo -e "${GREEN}EXECUTE${NC}" )]"
echo -e "  Step 5: Verify Deployment   [$( [[ "${SKIP_VERIFY}" == "true" ]] && echo -e "${YELLOW}SKIP${NC}" || echo -e "${GREEN}EXECUTE${NC}" )]"
echo ""

if [[ "${DRY_RUN}" == "true" ]]; then
    success "Dry run validation complete. No steps were executed."
    exit 0
fi

run_step() {
    local step_num="$1"
    local step_name="$2"
    local script_file="$3"

    echo ""
    echo -e "${BOLD}${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}${CYAN} [Step ${step_num}/5] ${step_name}${NC}"
    echo -e "${BOLD}${CYAN} Script: ${script_file}${NC}"
    echo -e "${BOLD}${CYAN}────────────────────────────────────────────────────────────────${NC}"

    if [[ ! -f "${script_file}" ]]; then
        die "Script file not found: ${script_file}"
    fi

    chmod +x "${script_file}"
    "${script_file}"
    success "Completed Step ${step_num}: ${step_name}"
}

# ── Step 1: Patch AI-Q Repository ─────────────────────────────────────────────
if [[ "${SKIP_PATCH}" != "true" ]]; then
    run_step "1" "Patch AI-Q Repository" "${SCRIPT_DIR}/01-patch-aiq.sh"

    # ── Secret Leak Prevention & Code Review Gate ──────────────────────────────
    echo ""
    echo -e "${BOLD}${CYAN}Checking for secret leaks in modified files...${NC}"
    (
        cd "${AIQ_REPO_DIR}"
        LEAK_FOUND=0
        
        # Check if any .env or secret files are tracked or staged
        for sensitive_pattern in "*.env" "aiq-fusion.env" "pull-secret.json" "oauth-ca.crt"; do
            if git status --porcelain | grep -E "(^[AMU? ]{2}|\s)${sensitive_pattern}" >/dev/null 2>&1; then
                echo -e "${RED}[SECURITY ALERT] Sensitive file pattern '${sensitive_pattern}' detected in git status!${NC}"
                LEAK_FOUND=1
            fi
        done

        # Scan staged/unstaged diff for actual values of keys that must never be committed.
        # Use both `git diff` (unstaged) and `git diff --cached` (staged) to cover repos
        # with no commits yet (where `git diff HEAD` would fail) as well as staged-but-
        # not-yet-committed changes.
        COMBINED_DIFF="$(git diff 2>/dev/null; git diff --cached 2>/dev/null)"
        for secret_val in "${FUSION_CAS_TOKEN:-}" "${NGC_API_KEY:-}" "${TAVILY_API_KEY:-}" "${OAUTH_CLIENT_SECRET:-}" "${NEXTAUTH_SECRET:-}"; do
            if [[ -n "${secret_val}" && ${#secret_val} -ge 8 ]]; then
                if echo "${COMBINED_DIFF}" | grep -qF "${secret_val}"; then
                    echo -e "${RED}[SECURITY ALERT] Actual secret value found in git diff!${NC}"
                    LEAK_FOUND=1
                fi
            fi
        done

        if [[ ${LEAK_FOUND} -eq 1 ]]; then
            echo -e "${RED}Refusing to proceed: Remove sensitive data/files before committing!${NC}"
            exit 1
        else
            echo -e "${GREEN}✓ Secret leak check passed: No plain-text tokens or credentials found in git diff.${NC}"
        fi
    )

    if [[ "${SKIP_BUILD}" != "true" && "${NON_INTERACTIVE}" != "true" ]]; then
        echo ""
        echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${BOLD}${YELLOW}  MANUAL REVIEW & COMMIT GATE                                ${NC}"
        echo -e "${BOLD}${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}Patches have been applied locally to:${NC} ${AIQ_REPO_DIR}"
        echo ""
        (
            cd "${AIQ_REPO_DIR}"
            echo -e "${BOLD}Current Git status:${NC}"
            git status --short || true
        )
        echo ""
        echo -e "${YELLOW}Security reminder:${NC}"
        echo -e "  • ${BOLD}Never${NC} commit 'aiq-fusion.env' or files containing real tokens/passwords."
        echo -e "  • All tokens/secrets are injected via Kubernetes Secrets in Step 3."
        echo ""
        echo -e "${YELLOW}Important:${NC} If using OpenShift BuildConfig, these changes ${BOLD}must${NC} be"
        echo -e "committed and pushed to your remote Git branch (${AIQ_GIT_REF:-main}) before building."
        echo ""

        while true; do
            read -r -p "Select action: [c] Continue to build, [d] View git diff, [s] Scan git diff for leaks, [q] Quit to review manually: " action
            case "${action}" in
                [dD]*)
                    (cd "${AIQ_REPO_DIR}" && git diff | less || git diff)
                    ;;
                [sS]*)
                    (
                        cd "${AIQ_REPO_DIR}"
                        echo -e "${CYAN}Searching git diff for sensitive variable assignments...${NC}"
                        { git diff; git diff --cached; } | grep -E "(TOKEN|KEY|SECRET|PASSWORD)\s*=\s*['\"][^'\"]+['\"]" || echo "✓ No suspicious plain-text secret assignments found."
                    )
                    ;;
                [cC]*)
                    info "Proceeding to Step 2..."
                    break
                    ;;
                [qQ]*)
                    echo ""
                    info "Paused for manual review. When you have committed & pushed your changes, resume with:"
                    echo -e "  ${BOLD}${CYAN}./scripts/run-all.sh --from 2${NC}"
                    echo ""
                    exit 0
                    ;;
                *)
                    echo "Please enter 'c' to continue, 'd' to view diff, 's' to scan for leaks, or 'q' to quit."
                    ;;
            esac
        done
    fi
else
    info "Skipping Step 1 (Patch AI-Q Repository)"
fi

# ── Pre-flight check for OpenShift BuildConfig ───────────────────────────────
if [[ "${SKIP_BUILD}" != "true" && -n "${AIQ_GIT_URI:-}" && -d "${AIQ_REPO_DIR:-}" ]]; then
    (
        cd "${AIQ_REPO_DIR}"
        if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
            warn "There are uncommitted changes in ${AIQ_REPO_DIR}."
            warn "OpenShift BuildConfig pulls directly from ${AIQ_GIT_URI} (${AIQ_GIT_REF:-main})."
            warn "Unpushed local changes will NOT be present in the container image."
            if [[ "${NON_INTERACTIVE}" != "true" ]]; then
                read -r -p "Continue anyway? [y/N]: " confirm
                [[ "${confirm}" =~ ^[yY]$ ]] || die "Aborted. Please commit and push changes first."
            fi
        fi
    )
fi

# ── Step 2: Build & Push Images ──────────────────────────────────────────────
if [[ "${SKIP_BUILD}" != "true" ]]; then
    run_step "2" "Build and Push Container Images" "${SCRIPT_DIR}/02-build-push-image.sh"
else
    info "Skipping Step 2 (Build and Push Images)"
fi

# ── Step 3: Setup Secrets & Tokens ───────────────────────────────────────────
if [[ "${SKIP_SECRETS}" != "true" ]]; then
    run_step "3" "Setup Secrets, Tokens & ConfigMaps" "${SCRIPT_DIR}/03-setup-secrets-and-token.sh"
else
    info "Skipping Step 3 (Setup Secrets and Token)"
fi

# ── Step 4: Deploy Helm Release ──────────────────────────────────────────────
if [[ "${SKIP_DEPLOY}" != "true" ]]; then
    run_step "4" "Deploy AI-Q Helm Release" "${SCRIPT_DIR}/04-deploy-helm.sh"
else
    info "Skipping Step 4 (Deploy Helm Release)"
fi

# ── Step 5: Verify Deployment ─────────────────────────────────────────────────
if [[ "${SKIP_VERIFY}" != "true" ]]; then
    run_step "5" "Verify Deployment and End-to-End Query" "${SCRIPT_DIR}/05-verify-deployment.sh"
else
    info "Skipping Step 5 (Verify Deployment)"
fi

echo ""
echo -e "${BOLD}${GREEN}================================================================${NC}"
echo -e "${BOLD}${GREEN}   All requested steps completed successfully! ✓                ${NC}"
echo -e "${BOLD}${GREEN}================================================================${NC}"
