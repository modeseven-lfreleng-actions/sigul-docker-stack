<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# GitHub Workflow Audit: Functional Tests Job

## Executive Summary

The `functional-tests` job in `.github/workflows/build-test.yaml`
replicates the stack initialization process from `stack-deploy-test` and
includes all recent fixes.

## Audit Findings

### ✅ Correct Behaviors

1. **Image Artifacts**: Both jobs download the same pre-built container
   images that include:
   - rpm-head-signing v1.7.6 built from source (fixes RPM 6.0.x
     compatibility)
   - krb5-devel and python3-rpm dependencies
   - All build-time fixes from the server Dockerfile

2. **Image Loading**: Both jobs use identical image loading and tagging
   logic:
   - Platform detection (linux/amd64 or linux/arm64)
   - Same tag naming scheme (`{component}-{platform}-image:test`)
   - Proper error handling for missing images

3. **Deployment Script**: Both jobs call the same deployment script:
   - `scripts/deploy-sigul-infrastructure.sh --verbose`
   - Script handles cert-init, server, and bridge deployment
   - Includes comprehensive health checks

4. **Environment Variables**: Both jobs set:
   - `SIGUL_PLATFORM_ID` - Platform identifier for image selection
   - `DOCKER_PLATFORM` - Docker platform string (linux/amd64 or
     linux/arm64)
   - The deployment script consumes these to set image names

5. **Container Cleanup**: The deployment script cleans up:
   - Stops existing Sigul containers
   - Removes existing containers
   - Removes data volumes (ensuring fresh state)
   - Prevents state leakage between test runs

6. **Fresh Stack Initialization**: Each functional-tests run gets:
   - Clean volume state
   - New ephemeral passwords (admin and NSS)
   - Fresh certificate generation via cert-init
   - Independent container instances

### 📋 Process Flow Comparison

#### stack-deploy-test job

```text
1. Download artifacts (pre-built images with all fixes)
2. Load & tag images
3. Run deployment script:
   a. Clean up existing infrastructure
   b. Start cert-init (generate certificates)
   c. Start sigul-server (with health checks)
   d. Start sigul-bridge (with health checks)
   e. Verify infrastructure
4. Export outputs for downstream jobs
```

#### functional-tests job

```text
1. Download artifacts (SAME pre-built images)
2. Load & tag images (SAME process)
3. Run deployment script (SAME script):
   a. Clean up existing infrastructure
   b. Start cert-init (fresh certificates)
   c. Start sigul-server (with health checks)
   d. Start sigul-bridge (with health checks)
   e. Verify infrastructure
4. Check NSS certificates
5. Run integration tests
```

### 🔍 Deep Analysis: rpm-head-signing Fix Propagation

The rpm-head-signing fix is included in functional-tests because:

1. **Build Phase** (`build-containers` job):
   - Builds server image with Dockerfile.server
   - Dockerfile.server includes:

     ```dockerfile
     RUN dnf install rpm-devel rpm-libs krb5-devel python3-rpm...
     COPY build-scripts/install-rpm-head-signing.sh...
     RUN /tmp/install-rpm-head-signing.sh --verify
     ```

   - The build process saves the image as artifact with all fixes baked
     in

2. **Deploy Phase** (both jobs):
   - Download the SAME artifact (pre-built image)
   - Load into Docker
   - Start containers
   - The fix is already in the image - no rebuild needed

3. **Runtime Verification**:
   - Server starts without ImportError
   - rpm_head_signing module imports without errors
   - No "undefined symbol: rpmWriteSignature" error

### 🎯 Conclusions

**No changes required** - The functional-tests job:

- Uses the same pre-built images with all fixes
- Replicates the deployment process identically
- Ensures fresh stack state via cleanup
- Validates infrastructure before tests

The architecture is sound:

- Single source of truth (build-containers job builds once)
- Artifacts ensure consistency across test jobs
- Deployment script provides uniform initialization
- Each job gets clean, isolated infrastructure

## Recommendations (Optional Enhancements)

While not required, these could improve observability:

1. **Add explicit fix verification** in functional-tests:

   ```bash
   # Verify rpm-head-signing is working
   docker exec sigul-server python3 -c \
     "from rpm_head_signing.insertlib import insert_signatures; \
      print('✓ rpm-head-signing working')"
   ```

2. **Log image build metadata** to confirm artifact freshness:

   ```bash
   docker inspect server-linux-amd64-image:test | \
     jq '.[0].Created'
   ```

3. **Add deployment script version check** to ensure consistency.
