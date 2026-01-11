#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Python installation script - simplified version
# This script installs a specified Python version to support python-nss-ng wheels
# UBI9 ships with Python 3.9 (EOL), but python-nss-ng wheels require Python 3.10+

set -euo pipefail

# Default to Python 3.12.8 if not specified
PYTHON_VERSION="${PYTHON_VERSION:-}"
PYTHON_INSTALL_PREFIX="${PYTHON_INSTALL_PREFIX:-/usr/local}"

# Logging functions
log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warning() {
    echo "[WARNING] $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Check if the target Python version is already installed
check_existing_python() {
    if [[ -z "$PYTHON_VERSION" ]]; then
        log_error "PYTHON_VERSION not set"
        return 1
    fi

    local major_minor="${PYTHON_VERSION%.*}"
    local python_cmd="python${major_minor}"

    if command -v "$python_cmd" >/dev/null 2>&1; then
        local version
        version=$("$python_cmd" --version 2>&1 | awk '{print $2}')
        log_info "Python ${major_minor} already installed: $version"
        return 0
    fi
    return 1
}

# Install build dependencies
install_dependencies() {
    log_info "Installing Python build dependencies"

    # Essential dependencies
    local deps=(
        make
        gcc
        git
        wget
        tar
        xz
        gcc-c++
        zlib-devel
        bzip2-devel
        sqlite-devel
        openssl-devel
        libffi-devel
        xz-devel
    )

    local missing_deps=()
    for pkg in "${deps[@]}"; do
        if ! rpm -q "$pkg" >/dev/null 2>&1; then
            missing_deps+=("$pkg")
        fi
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_info "Installing dependencies: ${missing_deps[*]}"
        if ! dnf install -y --setopt=install_weak_deps=False "${missing_deps[@]}" 2>&1; then
            log_error "Failed to install dependencies"
            return 1
        fi
    else
        log_info "All dependencies are already installed"
    fi
}

# Download and build Python from source
install_python() {
    log_info "Installing Python $PYTHON_VERSION from source"

    local workdir="/tmp/python-build-$$"
    mkdir -p "$workdir"
    cd "$workdir"

    # Download Python source
    local major_minor="${PYTHON_VERSION%.*}"
    local tarball="Python-${PYTHON_VERSION}.tar.xz"
    local url="https://www.python.org/ftp/python/${PYTHON_VERSION}/${tarball}"

    log_info "Downloading Python ${PYTHON_VERSION}..."
    if ! wget -q "$url"; then
        log_error "Failed to download Python source from $url"
        cd /
        rm -rf "$workdir"
        return 1
    fi

    # Extract
    log_info "Extracting Python source..."
    tar xf "$tarball"
    cd "Python-${PYTHON_VERSION}"

    # Configure without ensurepip to avoid build failures
    log_info "Configuring Python ${PYTHON_VERSION}..."
    if ! ./configure \
        --prefix="$PYTHON_INSTALL_PREFIX" \
        --enable-optimizations \
        --with-lto \
        --without-ensurepip \
        --enable-shared \
        LDFLAGS="-Wl,-rpath=${PYTHON_INSTALL_PREFIX}/lib" \
        > /tmp/python-configure.log 2>&1; then
        log_error "Python configure failed. Check /tmp/python-configure.log"
        tail -50 /tmp/python-configure.log >&2
        cd /
        rm -rf "$workdir"
        return 1
    fi

    # Build (use all available cores)
    log_info "Building Python ${PYTHON_VERSION} (this may take 3-5 minutes)..."
    if ! make -j"$(nproc)" > /tmp/python-build.log 2>&1; then
        log_error "Python build failed. Check /tmp/python-build.log"
        tail -100 /tmp/python-build.log >&2
        cd /
        rm -rf "$workdir"
        return 1
    fi

    # Install
    log_info "Installing Python ${PYTHON_VERSION}..."
    if ! make altinstall > /tmp/python-install.log 2>&1; then
        log_error "Python installation failed. Check /tmp/python-install.log"
        tail -50 /tmp/python-install.log >&2
        cd /
        rm -rf "$workdir"
        return 1
    fi

    # Clean up build directory
    cd /
    rm -rf "$workdir"

    log_info "Python ${PYTHON_VERSION} installed successfully to ${PYTHON_INSTALL_PREFIX}"
}

# Install pip using get-pip.py
install_pip() {
    local major_minor="${PYTHON_VERSION%.*}"
    log_info "Installing pip for Python ${major_minor}"

    # Get the python binary path
    local python_bin="${PYTHON_INSTALL_PREFIX}/bin/python${major_minor}"

    if [[ ! -f "$python_bin" ]]; then
        log_error "Python 3.12 binary not found at $python_bin"
        return 1
    fi

    # Download and run get-pip.py
    local get_pip_url="https://bootstrap.pypa.io/get-pip.py"

    if command -v wget >/dev/null 2>&1; then
        log_info "Downloading get-pip.py using wget..."
        if ! wget -qO /tmp/get-pip.py "$get_pip_url"; then
            log_error "Failed to download get-pip.py"
            return 1
        fi
    elif command -v curl >/dev/null 2>&1; then
        log_info "Downloading get-pip.py using curl..."
        if ! curl -sSL -o /tmp/get-pip.py "$get_pip_url"; then
            log_error "Failed to download get-pip.py"
            return 1
        fi
    else
        log_error "Neither wget nor curl available"
        return 1
    fi

    # Install pip
    if ! "$python_bin" /tmp/get-pip.py 2>&1; then
        log_error "Failed to install pip"
        rm -f /tmp/get-pip.py
        return 1
    fi

    rm -f /tmp/get-pip.py

    # Upgrade pip, setuptools, and wheel
    log_info "Upgrading pip, setuptools, and wheel..."
    "$python_bin" -m pip install --upgrade pip setuptools wheel || {
        log_warning "Failed to upgrade pip/setuptools/wheel - continuing anyway"
    }

    log_info "pip installed successfully"
}

# Configure system to use the installed Python version
configure_system() {
    local major_minor="${PYTHON_VERSION%.*}"
    log_info "Configuring system to use Python ${major_minor}"

    local python_bin="${PYTHON_INSTALL_PREFIX}/bin/python${major_minor}"
    local pip_bin="${PYTHON_INSTALL_PREFIX}/bin/pip${major_minor}"

    # Create symlinks for convenience
    if [[ -f "$python_bin" ]]; then
        ln -sf "$python_bin" "/usr/local/bin/python${major_minor}"
        ln -sf "$python_bin" /usr/local/bin/python3
        ln -sf "$python_bin" /usr/local/bin/python
        log_info "Created Python symlinks"
    fi

    if [[ -f "$pip_bin" ]]; then
        ln -sf "$pip_bin" "/usr/local/bin/pip${major_minor}"
        ln -sf "$pip_bin" /usr/local/bin/pip3
        ln -sf "$pip_bin" /usr/local/bin/pip
        log_info "Created pip symlinks"
    fi

    # Update ldconfig for shared libraries
    local major_only="${major_minor%%.*}"
    echo "${PYTHON_INSTALL_PREFIX}/lib" > "/etc/ld.so.conf.d/python${major_only}.conf"
    ldconfig

    log_info "System configured to use Python ${major_minor}"
}

# Verify installation
verify_installation() {
    local major_minor="${PYTHON_VERSION%.*}"
    log_info "Verifying Python ${major_minor} installation"

    # Check Python version
    if ! python3 --version 2>&1 | grep -q "${major_minor}"; then
        log_error "Python ${major_minor} verification failed: incorrect version"
        log_error "Expected: Python ${major_minor}.x"
        log_error "Got: $(python3 --version 2>&1)"
        return 1
    fi

    local version
    version=$(python3 --version 2>&1)
    log_info "Python verification passed: $version"

    # Check pip
    if ! python3 -m pip --version >/dev/null 2>&1; then
        log_error "pip verification failed"
        return 1
    fi

    local pip_version
    pip_version=$(python3 -m pip --version 2>&1)
    log_info "pip verification passed: $pip_version"

    # Test basic functionality
    local major="${major_minor%%.*}"
    local minor="${major_minor#*.}"
    if ! python3 -c "import sys; assert sys.version_info >= (${major}, ${minor})" 2>&1; then
        log_error "Python ${major_minor} version check failed"
        return 1
    fi

    log_info "Python ${major_minor} installation verified successfully"
    return 0
}

# Print usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Install Python from source for python-nss-ng compatibility.

OPTIONS:
    -h, --help              Show this help message
    -d, --debug             Enable debug logging
    -v, --verify            Verify installation after install
    -V, --version VERSION   Python version to install (required if PYTHON_VERSION not set)

ENVIRONMENT VARIABLES:
    PYTHON_VERSION          Python version to install (e.g., 3.12.8, 3.13.1)
    PYTHON_INSTALL_PREFIX   Installation prefix [default: /usr/local]

EXAMPLES:
    $0 --version 3.12.8 --verify       # Install Python 3.12.8 and verify
    $0 --version 3.13.1                # Install Python 3.13.1
    PYTHON_VERSION=3.12.8 $0 --verify  # Use environment variable

NOTES:
    - Python 3.9 (UBI9 default) is EOL as of October 2025
    - python-nss-ng requires Python 3.10+ for wheel compatibility
    - Python 3.12+ provides better performance and security
EOF
}

# Main installation function
main() {
    local verify=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                usage
                exit 0
                ;;
            -d|--debug)
                export DEBUG=1
                shift
                ;;
            -v|--verify)
                verify=true
                shift
                ;;
            -V|--version)
                if [[ -z "${2:-}" ]]; then
                    log_error "Option --version requires a value"
                    usage
                    exit 1
                fi
                PYTHON_VERSION="$2"
                shift 2
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate PYTHON_VERSION is set
    if [[ -z "$PYTHON_VERSION" ]]; then
        log_error "PYTHON_VERSION not set. Use --version or set PYTHON_VERSION environment variable"
        usage
        exit 1
    fi

    log_info "Starting Python installation"
    log_info "Target Python version: $PYTHON_VERSION"
    log_info "Install prefix: $PYTHON_INSTALL_PREFIX"

    # Check if already installed
    if check_existing_python; then
        local major_minor="${PYTHON_VERSION%.*}"
        log_info "Python ${major_minor} already available"
        if [[ "$verify" == "true" ]]; then
            verify_installation
        fi
        return 0
    fi

    # Install dependencies
    if ! install_dependencies; then
        log_error "Failed to install dependencies"
        exit 1
    fi

    # Install Python
    if ! install_python; then
        log_error "Failed to install Python $PYTHON_VERSION"
        exit 1
    fi

    # Install pip
    if ! install_pip; then
        log_error "Failed to install pip"
        exit 1
    fi

    # Configure system
    if ! configure_system; then
        log_error "Failed to configure system"
        exit 1
    fi

    # Verify if requested
    if [[ "$verify" == "true" ]]; then
        if ! verify_installation; then
            log_error "Python ${PYTHON_VERSION} verification failed"
            exit 1
        fi
    fi

    log_info "Python ${PYTHON_VERSION} installation completed successfully"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
