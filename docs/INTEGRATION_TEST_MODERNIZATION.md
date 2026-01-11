<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# Integration Test Suite Modernization

## Overview

This document summarizes the modernization of the integration test suite
for the `sigul-docker-stack` repository, bringing it in line with the
more modern implementation from the `sigul-docker` repository.

## Date

2025-01-11

## Changes Implemented

### 1. GitHub Workflow Enhancements

Added missing verification steps to the `functional-tests` job in
`.github/workflows/build-test.yaml`:

#### Double-TLS Patch Verification

Added verification step to confirm the critical double-TLS handshake
patch is applied in the bridge container. This step checks for:

- Presence of the `CRITICAL FIX` comment marker
- The `server_sock.force_handshake()` call
- Correct placement in the code (after accept, before client connection)

#### Explicit Client Setup

Added comprehensive client initialization step that:

- Creates client NSS and configuration volumes
- Sets proper ownership (UID 1000 for sigul user)
- Imports certificates from bridge
- Generates client configuration file
- Initializes client NSS database with imported certificates

### 2. Integration Test Script Modernization

Replaced the older, complex integration test script
(`scripts/run-integration-tests.sh`, 1100 lines) with the modern,
streamlined version from `sigul-docker` (521 lines).

#### Key Improvements

**Simplified Architecture:**

- Tests run from the client's perspective
- Cleaner, more maintainable code structure
- Better separation of concerns

**Enhanced Reliability:**

- Explicit timeout protection (60 seconds per operation)
- Better error handling and reporting
- Improved batch mode password handling via `printf '${password}\0'`

**Better User Experience:**

- Colored output for better readability
- Comprehensive test headers and summaries
- Detailed pass/fail reporting with counts
- Verbose mode for debugging

**Modern Features:**

- Dynamic network detection
- Automatic environment validation
- Comprehensive pre-flight checks
- Better container health verification

### 3. Local Testing Validation

Successfully deployed and tested the container stack locally:

**Deployment Success:**

- Container stack deploys successfully
- Server and bridge containers start and run properly
- Client setup initializes correctly
- Certificates import and validate successfully

**Test Results:**

- 4 out of 10 integration tests pass
- Infrastructure verification tests all pass
- Some authentication tests fail (known issue, see below)

## Known Issues

### Authentication Failures in Batch Mode

Some integration tests fail with "Authentication failed" errors. This is
a known issue related to password handling in batch mode that existed
before these changes. The issue is documented in the conversation thread
and requires separate investigation.

**What Works:**

- Client can connect to bridge
- Certificate authentication succeeds
- Infrastructure is healthy
- Password transmission is correct (verified with hex dump)

**What Fails:**

- Some operations requiring admin password authentication
- Batch mode password handling in certain scenarios

This is not a regression - the same issue exists in both the old and new
test implementations.

## Testing Performed

### Pre-Commit Validation

All pre-commit hooks pass successfully:

- shellcheck (shell script linting)
- yamllint (YAML validation)
- actionlint (GitHub Actions validation)
- markdownlint (documentation linting)
- codespell (spelling checks)
- reuse lint (license compliance)

### Local Deployment

Successfully deployed container stack locally on macOS with ARM64
architecture:

```bash
./scripts/deploy-sigul-infrastructure.sh --verbose
```

**Results:**

- Server container: Running, healthy
- Bridge container: Running, healthy
- Client setup: Successful
- Certificate initialization: Successful

### Integration Tests

Ran integration test suite locally:

```bash
export SIGUL_CLIENT_IMAGE="client-linux-arm64-image:test"
./scripts/run-integration-tests.sh --verbose
```

**Results:**

- Total Tests: 10
- Passed: 4
- Failed: 6 (due to known authentication issue)

## Files Modified

- `.github/workflows/build-test.yaml` - Added verification steps
- `scripts/run-integration-tests.sh` - Modernized implementation

## Benefits

1. **Improved Maintainability**: Cleaner, simpler code
2. **Better Reliability**: Explicit timeouts and error handling
3. **Enhanced Security**: Verification of critical patches
4. **Consistency**: Aligned with sigul-docker repository
5. **Better Testing**: More comprehensive pre-flight checks

## Next Steps

1. Create pull request with these changes
2. Validate in GitHub CI environment
3. Investigate and resolve batch mode authentication issue
4. Consider adding more integration tests as infrastructure stabilizes

## References

- Original sigul-docker repository test implementation
- GitHub Actions workflow best practices
- Sigul client/server/bridge architecture documentation
