#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation

# Test rpm-head-signing build from source in Fedora 43
#
# PURPOSE:
# This script validates that the rpm-head-signing build process works correctly
# in a clean Fedora 43 container before building the full sigul-server image.
#
# USAGE:
#   ./debug/test-rpm-head-signing.sh
#
# WHAT IT TESTS:
#   1. Installation of build dependencies (rpm-devel, krb5-devel, python3-rpm)
#   2. Building rpm-head-signing v1.7.6 from source with RPM 6.0.x support
#   3. Verifying the compiled C extension loads without symbol errors
#   4. Confirming all modules import successfully
#
# This test should complete successfully before merging changes that affect
# the rpm-head-signing build process in Dockerfile.server.

set -euo pipefail

echo "=== Testing rpm-head-signing build in Fedora 43 ==="
echo ""

# Run test in a temporary Fedora 43 container
docker run --rm -v "$(pwd)/build-scripts:/build-scripts:ro" fedora:43 bash -c '
set -euo pipefail

echo "Step 1: Install base dependencies..."
dnf update -y -q
dnf install -y -q --setopt=install_weak_deps=False \
    git python3 python3-devel python3-pip \
    rpm-devel rpm-libs krb5-devel python3-rpm gcc make

echo ""
echo "Step 2: Install Python build dependencies..."
pip3 install --no-cache-dir setuptools wheel

echo ""
echo "Step 3: Check RPM version..."
rpm --version

echo ""
echo "Step 4: Copy and run rpm-head-signing build script..."
cp /build-scripts/install-rpm-head-signing.sh /tmp/
chmod +x /tmp/install-rpm-head-signing.sh
/tmp/install-rpm-head-signing.sh --verify

echo ""
echo "Step 5: Test importing the module..."
python3 -c "
import rpm_head_signing
from rpm_head_signing import extract_header, insert_signature
from rpm_head_signing.insertlib import insert_signatures
print(\"✓ Successfully imported all rpm_head_signing modules\")
print(\"✓ rpm_head_signing installed and functional\")
"

echo ""
echo "Step 6: Check for the problematic symbol..."
python3 << "PYEOF"
import rpm_head_signing.insertlib
import inspect
module_file = inspect.getfile(rpm_head_signing.insertlib)
print(f"Module loaded from: {module_file}")
PYEOF

echo ""
echo "=== SUCCESS: rpm-head-signing built and works correctly ==="
'
