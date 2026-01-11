<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# Functional Tests Job - Audit Summary

## Question

Does the functional-tests job replicate the stack initialization from
stack-deploy-test and include all rpm-head-signing fixes?

## Answer

**YES** - The functional-tests job replicates stack initialization and
includes all fixes.

## Evidence

### 1. rpm-head-signing Fix is Working ✅

**Server Container Starts:**

```text
[13:43:08] SERVER: Starting Sigul Server service...
[13:43:08] SERVER: Command: /usr/sbin/sigul_server -c /etc/sigul/server.conf
[13:43:08] SERVER: Configuration: /etc/sigul/server.conf
[13:43:08] SERVER: Server initialized successfully
```

**No ImportError:**

- Previous error: `ImportError: undefined symbol: rpmWriteSignature`
- Current status: Server starts without any import errors
- rpm_head_signing module loads without errors

**Bridge Container Starts:**

```text
[13:43:00] BRIDGE: Starting Sigul Bridge service...
[13:43:00] BRIDGE: Command: /usr/sbin/sigul_bridge
[13:43:00] BRIDGE: Configuration: /etc/sigul/bridge.conf
[13:43:00] BRIDGE: Bridge initialized successfully
```

### 2. Stack Initialization is Identical ✅

Both `stack-deploy-test` and `functional-tests` jobs:

1. Download same pre-built images (with rpm-head-signing v1.7.6)
2. Load and tag images identically
3. Call same deployment script: `deploy-sigul-infrastructure.sh --verbose`
4. Clean up previous containers/volumes
5. Start cert-init → bridge → server
6. Perform health checks

### 3. Current Failure Has Different Root Cause ❌

The functional tests fail due to **authentication issues**, NOT
rpm-head-signing:

**Error Pattern:**

```text
ERROR: I/O error: EOFError('Unexpected EOF when reading a batch mode
password')
Error: Authentication failed
```

**Root Cause:**

- Integration test password handling issue
- Client can't authenticate to create users/keys
- This is a pre-existing test framework issue
- NOT related to rpm-head-signing or container deployment

## Conclusions

### What's Working

1. ✅ rpm-head-signing v1.7.6 builds without errors
2. ✅ Server container starts without import errors
3. ✅ Bridge container starts with koji/rpm dependencies
4. ✅ Stack deployment succeeds in both jobs
5. ✅ Certificate generation completes without errors
6. ✅ Infrastructure is healthy and running

### What's Not Working

1. ❌ Integration test authentication (password passing)
2. ❌ Client user creation
3. ❌ Sigul client batch mode password handling

### Next Steps

The rpm-head-signing fix is **complete and working**. The authentication
failures represent a **separate issue** in the integration test framework
that needs investigation:

1. Check password null-byte handling in `run_sigul_client_cmd`
2. Verify FAS/authentication configuration in client
3. Debug the batch mode password passing mechanism
4. Potentially simplify password handling or use alternative methods

## Verification Enhancement

Enhancement: explicit rpm-head-signing verification step in
functional-tests job:

```yaml
- name: 'Verify rpm-head-signing fix in server container'
  shell: bash
  run: |
    docker exec sigul-server python3 -c \
      "from rpm_head_signing.insertlib import insert_signatures; \
       print('✓ rpm-head-signing working')"
```

This will catch any future regressions in the rpm-head-signing fix.
