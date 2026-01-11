#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Debug script for local Docker builds with detailed timing and progress tracking
# This script helps identify build performance bottlenecks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
COMPONENT="${COMPONENT:-}"
PLATFORM="${PLATFORM:-linux/amd64}"
NO_CACHE="${NO_CACHE:-false}"
BUILDKIT_PROGRESS="${BUILDKIT_PROGRESS:-plain}"
VERBOSE="${VERBOSE:-false}"
DEBUG="${DEBUG:-false}"

# Timing variables
START_TIME=$(date +%s)

# Logging functions
log_info() {
    local elapsed=$(($(date +%s) - START_TIME))
    echo -e "${BLUE}[$(printf '%3d' $elapsed)s]${NC} $*"
}

log_success() {
    local elapsed=$(($(date +%s) - START_TIME))
    echo -e "${GREEN}[$(printf '%3d' $elapsed)s]${NC} $*"
}

log_warning() {
    local elapsed=$(($(date +%s) - START_TIME))
    echo -e "${YELLOW}[$(printf '%3d' $elapsed)s]${NC} $*"
}

log_error() {
    local elapsed=$(($(date +%s) - START_TIME))
    echo -e "${RED}[$(printf '%3d' $elapsed)s]${NC} $*"
}

log_debug() {
    if [[ "${DEBUG}" == "true" ]]; then
        local elapsed=$(($(date +%s) - START_TIME))
        echo -e "${CYAN}[DEBUG $(printf '%3d' $elapsed)s]${NC} $*"
    fi
}

log_stage() {
    local elapsed=$(($(date +%s) - START_TIME))
    echo ""
    echo -e "${MAGENTA}╔═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${MAGENTA}║${NC} ${CYAN}[$(printf '%3d' $elapsed)s]${NC} $*"
    echo -e "${MAGENTA}╚═══════════════════════════════════════════════════════════════${NC}"
}

# Print usage
usage() {
    cat << EOF
${CYAN}Debug Local Docker Build${NC}

Usage: $0 [OPTIONS] [COMPONENT] [PLATFORM]

Arguments:
    COMPONENT    Component to build (client|server|bridge) [default: client]
    PLATFORM     Platform to build for (linux/amd64|linux/arm64) [default: linux/amd64]

Options:
    -h, --help       Show this help message
    -d, --debug      Enable debug logging
    -v, --verbose    Show verbose Docker output
    -n, --no-cache   Build without cache

Examples:
    $0                              # Build client for amd64
    $0 server                       # Build server for amd64
    $0 client linux/arm64           # Build client for arm64
    $0 --no-cache client            # Build client without cache
    $0 --debug --verbose server     # Build server with debug output

EOF
}

# Show system information
show_system_info() {
    log_stage "System Information"

    log_info "Architecture: $(uname -m)"
    log_info "OS: $(uname -s)"
    log_info "Kernel: $(uname -r)"

    if command -v docker >/dev/null 2>&1; then
        log_info "Docker version: $(docker --version | cut -d' ' -f3 | tr -d ',')"

        # Docker disk usage
        local disk_usage
        disk_usage=$(docker system df 2>/dev/null | grep -i 'build cache' || echo "N/A")
        log_info "Build cache: ${disk_usage}"
    fi

    # Check available disk space
    local available_space
    available_space=$(df -h "${PROJECT_ROOT}" | awk 'NR==2 {print $4}')
    log_info "Available disk space: ${available_space}"

    # Check available memory
    if [[ -f /proc/meminfo ]]; then
        local available_mem
        available_mem=$(grep MemAvailable /proc/meminfo | awk '{printf "%.1f GB", $2/1024/1024}')
        log_info "Available memory: ${available_mem}"
    fi
}

# Check Docker buildx
check_buildx() {
    log_stage "Checking Docker BuildKit"

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    if ! docker buildx version >/dev/null 2>&1; then
        log_error "Docker buildx is not available"
        exit 1
    fi

    log_success "Docker BuildKit is ready"

    # Show current builder
    local builder
    builder=$(docker buildx inspect --bootstrap 2>/dev/null | grep -i 'name:' | head -1 | awk '{print $2}')
    log_info "Using builder: ${builder}"
}

# Validate component and dockerfile
validate_component() {
    log_stage "Validating Component: ${COMPONENT}"

    local dockerfile="${PROJECT_ROOT}/Dockerfile.${COMPONENT}"

    if [[ ! -f "${dockerfile}" ]]; then
        log_error "Dockerfile not found: ${dockerfile}"
        log_error "Valid components: client, server, bridge"
        exit 1
    fi

    log_success "Found Dockerfile: Dockerfile.${COMPONENT}"

    # Count build stages/layers
    local layer_count
    layer_count=$(grep -c '^RUN\|^COPY\|^ADD' "${dockerfile}" || true)
    log_info "Build layers/stages: ${layer_count}"

    # Check for Python version
    local python_version
    python_version=$(grep -oP 'install-python\.sh --version \K[0-9.]+' "${dockerfile}" || echo "unknown")
    log_info "Python version: ${python_version}"
}

# Pre-build checks
pre_build_checks() {
    log_stage "Pre-Build Checks"

    # Check if build scripts exist
    local build_scripts_dir="${PROJECT_ROOT}/build-scripts"
    if [[ ! -d "${build_scripts_dir}" ]]; then
        log_error "build-scripts directory not found"
        exit 1
    fi

    local required_scripts=(
        "setup-repositories.sh"
        "install-python.sh"
        "install-python-nss.sh"
    )

    for script in "${required_scripts[@]}"; do
        if [[ -f "${build_scripts_dir}/${script}" ]]; then
            log_success "✓ ${script}"
        else
            log_error "✗ ${script} (missing)"
            exit 1
        fi
    done

    # Check network connectivity to key URLs
    log_info "Testing network connectivity..."
    local test_urls=(
        "https://www.python.org/ftp/python/"
        "https://pypi.org/simple/"
        "https://dl.fedoraproject.org/pub/epel/"
    )

    for url in "${test_urls[@]}"; do
        if timeout 5 curl -s --head "${url}" >/dev/null 2>&1; then
            log_success "✓ ${url}"
        else
            log_warning "✗ ${url} (unreachable - may use cache or fail)"
        fi
    done
}

# Build the Docker image
build_image() {
    log_stage "Building Docker Image: ${COMPONENT} (${PLATFORM})"

    local dockerfile="Dockerfile.${COMPONENT}"
    local image_tag
    local build_start build_end duration

    image_tag="sigul-debug-${COMPONENT}:${PLATFORM//\//-}-$(date +%Y%m%d-%H%M%S)"

    log_info "Component: ${COMPONENT}"
    log_info "Platform: ${PLATFORM}"
    log_info "Dockerfile: ${dockerfile}"
    log_info "Image tag: ${image_tag}"
    log_info "Cache: $([ "${NO_CACHE}" = "true" ] && echo "disabled" || echo "enabled")"
    log_info "Progress: ${BUILDKIT_PROGRESS}"

    # Change to project root for build context
    cd "${PROJECT_ROOT}"

    # Prepare build arguments
    local build_args=(
        docker buildx build
        --platform "${PLATFORM}"
        --file "${dockerfile}"
        --tag "${image_tag}"
        --progress="${BUILDKIT_PROGRESS}"
        --load
    )

    # Add no-cache flag if requested
    if [[ "${NO_CACHE}" == "true" ]]; then
        build_args+=(--no-cache)
        log_warning "Cache disabled - build will take longer"
    fi

    # Add verbose output if requested
    if [[ "${VERBOSE}" == "true" ]]; then
        build_args+=(--progress=plain)
    fi

    # Add build context
    build_args+=(.)

    log_info "Starting build..."
    echo ""
    echo -e "${CYAN}Build Command:${NC}"
    echo "  ${build_args[*]}"
    echo ""

    build_start=$(date +%s)

    # Run the build
    if "${build_args[@]}"; then
        build_end=$(date +%s)
        duration=$((build_end - build_start))

        log_success "Build completed successfully!"
        log_success "Build duration: ${duration}s ($(printf '%d:%02d' $((duration/60)) $((duration%60))))"

        # Show image details
        log_stage "Image Details"

        local image_size
        image_size=$(docker images "${image_tag}" --format "{{.Size}}")
        log_info "Image size: ${image_size}"

        # Show image layers
        log_info "Image layers:"
        docker history "${image_tag}" --human --no-trunc | head -20

        echo ""
        log_info "Test the image with:"
        echo "  docker run --rm -it ${image_tag} /bin/bash"
        echo ""
        log_info "Remove the image with:"
        echo "  docker rmi ${image_tag}"

        return 0
    else
        build_end=$(date +%s)
        duration=$((build_end - build_start))

        log_error "Build failed after ${duration}s"
        return 1
    fi
}

# Print build summary
print_summary() {
    local end_time total_duration
    end_time=$(date +%s)
    total_duration=$((end_time - START_TIME))

    log_stage "Build Summary"

    log_info "Total execution time: ${total_duration}s ($(printf '%d:%02d' $((total_duration/60)) $((total_duration%60))))"
    log_info "Component: ${COMPONENT}"
    log_info "Platform: ${PLATFORM}"

    # Show cache usage
    log_info "Docker disk usage:"
    docker system df

    echo ""
    log_info "To clear Docker build cache:"
    echo "  docker builder prune --all --force"
    echo ""
    log_info "To view BuildKit cache:"
    echo "  docker buildx du"
}

# Main function
main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--debug)
                DEBUG=true
                log_debug "Debug mode enabled"
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -n|--no-cache)
                NO_CACHE=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                # Positional arguments
                if [[ -z "${COMPONENT}" ]]; then
                    COMPONENT="$1"
                elif [[ "${PLATFORM}" == "linux/amd64" ]]; then
                    PLATFORM="$1"
                else
                    log_error "Too many arguments: $1"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # Set default component if not specified
    if [[ -z "${COMPONENT}" ]]; then
        COMPONENT="client"
    fi

    log_stage "Docker Build Debug Tool"
    log_info "Project: $(basename "${PROJECT_ROOT}")"
    log_info "Started: $(date '+%Y-%m-%d %H:%M:%S')"

    show_system_info
    check_buildx
    validate_component
    pre_build_checks

    if build_image; then
        print_summary
        exit 0
    else
        print_summary
        exit 1
    fi
}

# Run main function
main "$@"
