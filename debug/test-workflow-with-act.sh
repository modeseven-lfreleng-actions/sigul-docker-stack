#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Act Workflow Testing Helper Script
#
# This script helps test GitHub Actions workflows locally using nektos/act
#
# Usage:
#   ./debug/test-workflow-with-act.sh [OPTIONS] [JOB]
#
# Options:
#   --list               List available jobs
#   --dry-run            Show what would run without executing
#   --no-cache           Clear act cache before running
#   --platform PLATFORM  Specify platform (linux/amd64 or linux/arm64)
#   --help               Show this help message
#
# Jobs:
#   build-client         Build client container only
#   build-server         Build server container only
#   build-bridge         Build bridge container only
#   stack-deploy         Test stack deployment
#   functional-tests     Run functional tests
#   all                  Run complete workflow (resource intensive!)

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default options
JOB=""
DRY_RUN=false
NO_CACHE=false
LIST_JOBS=false
PLATFORM=""

# Detect platform
detect_platform() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64)
            echo "linux/amd64"
            ;;
        arm64|aarch64)
            echo "linux/arm64"
            ;;
        *)
            echo "linux/amd64"
            ;;
    esac
}

PLATFORM="${PLATFORM:-$(detect_platform)}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[ACT]${NC} $*"
}

success() {
    echo -e "${GREEN}[ACT]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[ACT]${NC} $*"
}

error() {
    echo -e "${RED}[ACT]${NC} $*" >&2
}

# Check if act is installed
check_act() {
    if ! command -v act >/dev/null 2>&1; then
        error "act is not installed"
        error ""
        error "Install with:"
        error "  macOS:  brew install act"
        error "  Linux:  curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash"
        error ""
        error "More info: https://github.com/nektos/act"
        exit 1
    fi

    log "Using act version: $(act --version | head -1)"
}

# List available jobs
list_jobs() {
    log "Listing available jobs in workflow..."
    echo ""

    cd "${PROJECT_ROOT}"
    act -l -W .github/workflows/build-test.yaml || true

    echo ""
    log "To run a specific job:"
    log "  $0 <job-name>"
    echo ""
}

# Clear act cache
clear_cache() {
    log "Clearing act cache..."

    # Remove act cache directory
    if [[ -d ~/.cache/act ]]; then
        rm -rf ~/.cache/act
        success "Cache cleared"
    else
        log "No cache to clear"
    fi
}

# Run specific job with act
run_job() {
    local job="$1"

    log "Running job: ${job}"
    log "Platform: ${PLATFORM}"
    log "Workflow: .github/workflows/build-test.yaml"
    echo ""

    cd "${PROJECT_ROOT}"

    local act_args=(
        -W .github/workflows/build-test.yaml
        --platform "${PLATFORM}"
    )

    # Add job filter if specified
    if [[ -n "${job}" ]] && [[ "${job}" != "all" ]]; then
        act_args+=(-j "${job}")
    fi

    # Add dry-run flag if requested
    if [[ "${DRY_RUN}" == "true" ]]; then
        act_args+=(--dryrun)
    fi

    # Add verbose flag for debugging
    act_args+=(--verbose)

    log "Command: act ${act_args[*]}"
    echo ""

    if act "${act_args[@]}"; then
        success "Job completed successfully"
    else
        error "Job failed"
        return 1
    fi
}

# Show usage
show_usage() {
    cat << 'EOF'
Act Workflow Testing Helper Script

This script helps test GitHub Actions workflows locally using nektos/act.

Usage:
    ./debug/test-workflow-with-act.sh [OPTIONS] [JOB]

Options:
    --list               List available jobs
    --dry-run            Show what would run without executing
    --no-cache           Clear act cache before running
    --platform PLATFORM  Specify platform (linux/amd64 or linux/arm64)
    --help               Show this help message

Jobs:
    build-containers     Build all containers
    stack-deploy-test    Test stack deployment
    functional-tests     Run functional tests
    all                  Run complete workflow (very resource intensive!)

Examples:
    # List all available jobs
    ./debug/test-workflow-with-act.sh --list

    # Test stack deployment (dry-run)
    ./debug/test-workflow-with-act.sh --dry-run stack-deploy-test

    # Run stack deployment test
    ./debug/test-workflow-with-act.sh stack-deploy-test

    # Clear cache and run
    ./debug/test-workflow-with-act.sh --no-cache stack-deploy-test

    # Run on specific platform
    ./debug/test-workflow-with-act.sh --platform linux/arm64 stack-deploy-test

Notes:
    - Running workflows with act requires Docker
    - Some workflows may consume significant resources
    - Use --dry-run first to see what will execute
    - Act uses container images from catthehacker/ubuntu
    - Secrets can be provided via --secret-file .secrets

Limitations:
    - Some GitHub Actions features may not work identically
    - ARM builds may not work on x86 hosts and vice versa
    - Network connectivity may differ from GitHub Actions
    - Some GitHub-specific contexts may be unavailable

For more information:
    - Act documentation: https://github.com/nektos/act
    - Act runners: https://github.com/catthehacker/docker_images

EOF
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --list)
                LIST_JOBS=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-cache)
                NO_CACHE=true
                shift
                ;;
            --platform)
                PLATFORM="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            -*)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                JOB="$1"
                shift
                ;;
        esac
    done
}

# Main execution
main() {
    log "=== Act Workflow Testing ==="
    echo ""

    parse_args "$@"

    # Check prerequisites
    check_act

    # Clear cache if requested
    if [[ "${NO_CACHE}" == "true" ]]; then
        clear_cache
    fi

    # List jobs if requested
    if [[ "${LIST_JOBS}" == "true" ]]; then
        list_jobs
        exit 0
    fi

    # Validate job specified
    if [[ -z "${JOB}" ]]; then
        warn "No job specified"
        echo ""
        list_jobs
        exit 0
    fi

    # Run the job
    run_job "${JOB}"

    echo ""
    success "=== Testing Complete ==="
    echo ""

    if [[ "${DRY_RUN}" == "true" ]]; then
        log "This was a dry-run. Remove --dry-run to execute."
    fi
}

# Run main
main "$@"
