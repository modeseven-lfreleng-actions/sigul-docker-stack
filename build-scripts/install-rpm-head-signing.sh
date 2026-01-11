#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Build and install rpm-head-signing from source with RPM 6.0.x compatibility
#
# BACKGROUND:
# Fedora 43 ships with RPM 6.0.x, but the packaged rpm-head-signing (v1.7.4)
# has a binary incompatibility - the pre-compiled C extension references the
# rpmWriteSignature symbol which was removed/changed in RPM 6.0.x.
#
# SOLUTION:
# Build rpm-head-signing v1.7.6 from source, which has RPM 6.0 support.
# The build process:
#   1. Requires rpm-devel, krb5-devel (for gssapi), and python3-rpm
#   2. Installs dependencies (cryptography, koji, xattr) separately
#   3. Builds rpm-head-signing using --no-deps to avoid the PyPI 'rpm' package
#   4. Uses system python3-rpm bindings instead of PyPI's broken 'rpm' package
#
# This script builds rpm-head-signing against the correct RPM development
# libraries to ensure binary compatibility with Fedora 43's RPM 6.0.x

set -euo pipefail

# Configuration
RPM_HEAD_SIGNING_VERSION="${RPM_HEAD_SIGNING_VERSION:-1.7.6}"
RPM_HEAD_SIGNING_REPO="https://github.com/fedora-iot/rpm-head-signing"
BUILD_DIR="/tmp/rpm-head-signing-build"
VERIFY_MODE=false

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verify)
            VERIFY_MODE=true
            shift
            ;;
        --version)
            RPM_HEAD_SIGNING_VERSION="$2"
            shift 2
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Check if rpm-devel is installed
if ! rpm -q rpm-devel >/dev/null 2>&1; then
    log_error "rpm-devel is not installed"
    log_error "Please install it first: dnf install -y rpm-devel"
    exit 1
fi

# Check if krb5-devel is installed (required for gssapi dependency)
if ! rpm -q krb5-devel >/dev/null 2>&1; then
    log_error "krb5-devel is not installed"
    log_error "Please install it first: dnf install -y krb5-devel"
    exit 1
fi

# Check if python3-rpm is installed (system RPM Python bindings)
if ! python3 -c "import rpm" >/dev/null 2>&1; then
    log_error "python3-rpm is not installed"
    log_error "Please install it first: dnf install -y python3-rpm"
    exit 1
fi

# Get RPM version for logging
RPM_VERSION=$(rpm --version | awk '{print $3}')
log_info "Building rpm-head-signing ${RPM_HEAD_SIGNING_VERSION} \
against RPM ${RPM_VERSION}"

# Clean up any previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

log_info "Cloning rpm-head-signing repository..."
git clone --depth 1 --branch "v${RPM_HEAD_SIGNING_VERSION}" \
    "${RPM_HEAD_SIGNING_REPO}" "${BUILD_DIR}"

cd "${BUILD_DIR}"

log_info "Building rpm-head-signing from source..."

# Ensure setuptools and wheel are installed for building
pip3 install --no-cache-dir setuptools wheel

# Install dependencies first, excluding the 'rpm' package from PyPI
# We use the system python3-rpm package instead
log_info "Installing rpm-head-signing dependencies (excluding rpm package)..."
pip3 install --no-cache-dir cryptography koji xattr

# Install using pip3 which will compile the C extension
# Use --no-deps to prevent installing the 'rpm' PyPI package
log_info "Installing rpm-head-signing without dependencies..."
pip3 install --no-cache-dir --no-deps .

# Change directory to avoid importing from source tree
cd /

log_info "Verifying rpm-head-signing installation..."

# Test basic import
if ! python3 -c "import rpm_head_signing" 2>&1; then
    log_error "Failed to import rpm_head_signing module"
    log_error "Check the error output above for details"
    exit 1
fi

# Test that the compiled extension can load
if ! python3 -c "from rpm_head_signing.insertlib import \
insert_signatures" 2>&1; then
    log_error "Failed to import rpm_head_signing.insertlib"
    log_error "The C extension may have compatibility issues"
    log_error "Check the error output above for details"
    exit 1
fi

log_info "rpm-head-signing built and installed successfully"

# Verify mode - run additional checks
if [ "${VERIFY_MODE}" = true ]; then
    log_info "Running verification checks..."

    # Check that all expected symbols are available
    python3 << 'EOF'
import rpm_head_signing
from rpm_head_signing import extract_header, insert_signature
from rpm_head_signing.insertlib import insert_signatures

print("✓ All rpm-head-signing modules imported successfully")
print("✓ rpm-head-signing installed and functional")
EOF

    log_info "All verification checks passed"
fi

# Clean up build directory
rm -rf "${BUILD_DIR}"

log_info "Cleanup completed"
