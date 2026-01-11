#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Local Stack Deployment Test Script
#
# This script simulates the GitHub Actions workflow locally to test
# the stack deployment without rebuilding containers.
#
# Usage:
#   ./debug/test-stack-deployment.sh [OPTIONS]
#
# Options:
#   --build-first    Build containers first (simulates build job)
#   --skip-deploy    Load images but skip deployment
#   --verbose        Enable verbose output
#   --clean          Clean up everything before starting
#   --help           Show this help message

set -euo pipefail

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Default options
BUILD_FIRST=false
SKIP_DEPLOY=false
VERBOSE=false
CLEAN=false
PLATFORM="linux/amd64"

# Detect actual platform
if [[ "$(uname -m)" == "arm64" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
    PLATFORM="linux/arm64"
fi

PLATFORM_ID="${PLATFORM//\//-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Logging functions
log() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] INFO:${NC} $*"
}

success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] SUCCESS:${NC} $*"
}

warn() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] WARN:${NC} $*"
}

error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ERROR:${NC} $*" >&2
}

verbose() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${PURPLE}[$(date '+%H:%M:%S')] DEBUG:${NC} $*"
    fi
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-first)
                BUILD_FIRST=true
                shift
                ;;
            --skip-deploy)
                SKIP_DEPLOY=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --clean)
                CLEAN=true
                shift
                ;;
            --help)
                cat << EOF
Local Stack Deployment Test Script

This script simulates the GitHub Actions workflow locally to test
the stack deployment without rebuilding containers.

Usage:
    $0 [OPTIONS]

Options:
    --build-first    Build containers first (simulates build job)
    --skip-deploy    Load images but skip deployment
    --verbose        Enable verbose output
    --clean          Clean up everything before starting
    --help           Show this help message

Examples:
    # Test deployment with existing images
    $0

    # Build first, then deploy
    $0 --build-first

    # Clean everything and start fresh
    $0 --clean --build-first

    # Build and save images without deploying
    $0 --build-first --skip-deploy --verbose

EOF
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

# Clean up function
cleanup() {
    log "Cleaning up existing containers and volumes..."

    # Stop and remove containers
    docker compose -f "${PROJECT_ROOT}/docker-compose.sigul.yml" down -v 2>/dev/null || true

    # Remove test artifacts
    rm -rf "${PROJECT_ROOT}/test-artifacts"
    rm -f "/tmp/server-${PLATFORM_ID}.tar"
    rm -f "/tmp/bridge-${PLATFORM_ID}.tar"
    rm -f "/tmp/client-${PLATFORM_ID}.tar"

    success "Cleanup completed"
}

# Build containers
build_containers() {
    log "Building containers for platform: ${PLATFORM}"

    local components=("server" "bridge" "client")

    for component in "${components[@]}"; do
        log "Building ${component}..."

        if docker build \
            --platform "${PLATFORM}" \
            -f "Dockerfile.${component}" \
            -t "${component}-${PLATFORM_ID}-image:test" \
            "${PROJECT_ROOT}"; then
            success "Built ${component}"
        else
            error "Failed to build ${component}"
            return 1
        fi
    done

    success "All containers built successfully"
}

# Save containers to tar files (simulates build artifacts)
save_containers() {
    log "Saving container images to tar files..."

    mkdir -p /tmp

    local components=("server" "bridge" "client")

    for component in "${components[@]}"; do
        local image="${component}-${PLATFORM_ID}-image:test"
        local tarfile="/tmp/${component}-${PLATFORM_ID}.tar"

        verbose "Saving ${image} to ${tarfile}"

        if docker save "${image}" -o "${tarfile}"; then
            success "Saved ${component} ($(du -h "${tarfile}" | cut -f1))"
        else
            error "Failed to save ${component}"
            return 1
        fi
    done

    success "All images saved to /tmp/*.tar"
}

# Load containers from tar files (simulates artifact download)
load_containers() {
    log "Loading container images from tar files..."

    local components=("server" "bridge" "client")
    local loaded=0

    for component in "${components[@]}"; do
        local tarfile="/tmp/${component}-${PLATFORM_ID}.tar"
        local target_image="${component}-${PLATFORM_ID}-image:test"

        if [[ ! -f "${tarfile}" ]]; then
            warn "Artifact not found: ${tarfile}"
            warn "Run with --build-first to create images"
            continue
        fi

        verbose "Loading ${component} from ${tarfile}"

        if docker load -i "${tarfile}"; then
            # Verify the image was loaded
            if docker images -q "${target_image}" >/dev/null 2>&1; then
                success "Loaded ${component}: ${target_image}"
                loaded=$((loaded + 1))
            else
                warn "Image loaded but not tagged as expected: ${target_image}"
            fi
        else
            error "Failed to load ${component}"
            return 1
        fi
    done

    if [[ $loaded -eq 0 ]]; then
        error "No images were loaded. Run with --build-first"
        return 1
    fi

    success "Loaded ${loaded} container images"
}

# List loaded images
list_images() {
    log "Current container images:"
    echo ""
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}" | \
        grep -E "REPOSITORY|server-|bridge-|client-" || \
        echo "No matching images found"
    echo ""
}

# Deploy stack
deploy_stack() {
    log "Deploying Sigul stack..."

    # Export image names for docker-compose
    export SIGUL_SERVER_IMAGE="server-${PLATFORM_ID}-image:test"
    export SIGUL_BRIDGE_IMAGE="bridge-${PLATFORM_ID}-image:test"
    export SIGUL_RUNNER_PLATFORM="${PLATFORM_ID}"
    export SIGUL_DOCKER_PLATFORM="${PLATFORM}"

    verbose "Environment variables:"
    verbose "  SIGUL_SERVER_IMAGE=${SIGUL_SERVER_IMAGE}"
    verbose "  SIGUL_BRIDGE_IMAGE=${SIGUL_BRIDGE_IMAGE}"
    verbose "  SIGUL_RUNNER_PLATFORM=${SIGUL_RUNNER_PLATFORM}"
    verbose "  SIGUL_DOCKER_PLATFORM=${SIGUL_DOCKER_PLATFORM}"

    # Run the deployment script
    cd "${PROJECT_ROOT}"

    if [[ "${VERBOSE}" == "true" ]]; then
        bash scripts/deploy-sigul-infrastructure.sh --verbose
    else
        bash scripts/deploy-sigul-infrastructure.sh
    fi

    success "Stack deployment completed"
}

# Show stack status
show_status() {
    log "Stack Status:"
    echo ""

    docker ps -a --filter "name=sigul" \
        --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" || true

    echo ""
    log "Volumes:"
    docker volume ls --filter "name=sigul" || true

    echo ""
}

# Main execution
main() {
    log "=== Local Stack Deployment Test ==="
    log "Platform: ${PLATFORM} (${PLATFORM_ID})"
    echo ""

    parse_args "$@"

    # Step 1: Clean if requested
    if [[ "${CLEAN}" == "true" ]]; then
        cleanup
    fi

    # Step 2: Build if requested
    if [[ "${BUILD_FIRST}" == "true" ]]; then
        build_containers
        save_containers
    fi

    # Step 3: Load images
    load_containers
    list_images

    # Step 4: Deploy (unless skip-deploy)
    if [[ "${SKIP_DEPLOY}" == "false" ]]; then
        deploy_stack
        show_status

        log ""
        log "=== Deployment Complete ==="
        log ""
        log "To inspect containers:"
        log "  docker logs sigul-cert-init"
        log "  docker logs sigul-bridge"
        log "  docker logs sigul-server"
        log ""
        log "To cleanup:"
        log "  docker compose -f docker-compose.sigul.yml down -v"
        log "  rm -f /tmp/*-${PLATFORM_ID}.tar"
        log ""
    else
        log ""
        log "=== Load Complete (Deployment Skipped) ==="
        log ""
        log "To deploy manually:"
        log "  export SIGUL_SERVER_IMAGE=server-${PLATFORM_ID}-image:test"
        log "  export SIGUL_BRIDGE_IMAGE=bridge-${PLATFORM_ID}-image:test"
        log "  ./scripts/deploy-sigul-infrastructure.sh"
        log ""
    fi
}

# Run main function
main "$@"
