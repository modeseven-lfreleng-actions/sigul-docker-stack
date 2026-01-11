<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# Patch Documentation: bridge-no-fas.patch

## Problem Description

When running Sigul Bridge on Fedora 43 (or any modern system without the
legacy python3-fedora package), the bridge process crashes after startup
with the error:

```text
ERROR: Error switching to user 1000: name 'fedora' is not defined
```

This error appears in `/var/log/sigul_bridge.log` and causes the container
to exit with code 1.

## Root Cause

The Sigul bridge.py code has a try/except block that handles the absence
of the python3-fedora package by setting `have_fas=False`:

```python
try:
    import fedora.client
    have_fas = True
except ImportError:
    have_fas = False
```

Later in the code (around line 1497), there is unconditional usage of
`fedora.client.baseclient` that is NOT wrapped in a `have_fas` check:

```python
if config.daemon_uid is not None:
    try:
        os.seteuid(config.daemon_uid)
        utils.update_HOME_for_uid(config)
        # Ugly hack: FAS uses $HOME at time of import
        fedora.client.baseclient.SESSION_DIR = \     # <-- CRASH HERE
            os.path.expanduser('~/.fedora')
        fedora.client.baseclient.SESSION_FILE = \
            os.path.join(fedora.client.baseclient.SESSION_DIR,
                         '.fedora_session')
```

When `have_fas=False` (because python3-fedora is not installed), the name
`fedora` is not defined in the global namespace, causing a NameError that
gets caught by the outer try/except and logged as the error above.

## Context: Why python3-fedora is Missing

The python3-fedora package provides the Fedora Account System (FAS) client
library. This is a legacy authentication system used by Fedora
Infrastructure.

1. The package has been **REMOVED** from Fedora 43 repositories
2. Modern Fedora uses Noggin/FreeIPA instead of FAS
3. Most Sigul deployments do **NOT** use FAS integration
4. The Sigul code already has conditional import logic to handle FAS absence

## The Fix

Wrap the `fedora.client.baseclient` usage in the same `have_fas` conditional
check used elsewhere in the code. This makes the FAS session setup optional
and prevents the crash when FAS is not available.

The patch changes this:

```python
# Ugly hack: FAS uses $HOME at time of import
fedora.client.baseclient.SESSION_DIR = \
    os.path.expanduser('~/.fedora')
fedora.client.baseclient.SESSION_FILE = \
    os.path.join(fedora.client.baseclient.SESSION_DIR,
                 '.fedora_session')
```

To this:

```python
# Set FAS session paths if FAS module is available
# Without this check, accessing fedora.client when have_fas=False
# causes: NameError: name 'fedora' is not defined
if have_fas:
    fedora.client.baseclient.SESSION_DIR = \
        os.path.expanduser('~/.fedora')
    fedora.client.baseclient.SESSION_FILE = \
        os.path.join(fedora.client.baseclient.SESSION_DIR,
                     '.fedora_session')
# If have_fas is False, FAS session setup skips (no-op)
```

## Impact

- Bridge starts without python3-fedora installed
- FAS integration becomes inactive (`have_fas=False`)
- All other functionality remains intact
- No behavior change for systems that DO have python3-fedora
- Bridge can authenticate clients and servers using NSS/TLS certificates
- Bridge can forward signing requests between client and server

## Upstream Status

This is a bug in upstream Sigul that requires reporting to:
<https://pagure.io/sigul>

The bug exists in Sigul v1.4 (released 2020-11-11) and affects all
deployments on modern Fedora/RHEL systems that don't have FAS.

## Testing

After applying this patch:

1. Bridge container starts
2. Bridge listens on ports 44333 (server) and 44334 (client)
3. Health checks pass
4. No errors in `/var/log/sigul_bridge.log`
5. FAS functionality becomes inactive (as intended)
6. Certificate-based authentication works as expected

## Verification Steps

```bash
# Build the container
docker build -f Dockerfile.bridge -t sigul-bridge:test .

# Check that the patch applies
docker run --rm sigul-bridge:test \
  grep -A 3 "if have_fas:" /usr/share/sigul/bridge.py

# Run the bridge and check logs
docker-compose up sigul-bridge
docker logs sigul-bridge 2>&1 | grep -i "error\|failed"

# Verify bridge is listening
docker exec sigul-bridge ss -tlnp | grep -E "44333|44334"
```

## References

- Sigul documentation: <https://pagure.io/sigul/>
- Sigul v1.4 tag: <https://pagure.io/sigul/tree/v1.4>
- FAS deprecation:
  <https://docs.fedoraproject.org/en-US/infra/sysadmin_guide/infrastructure-modernization/>
- Issue discovered during: Fedora 43 migration (2026-01-11)
- Related issue: Container stack deployment script debugging

## Discovery Timeline

1. Container builds succeeded on Fedora 43
2. Stack deployment started
3. cert-init completed
4. Bridge container exited with code 1
5. No stdout/stderr output from bridge process
6. Found error in `/var/log/sigul_bridge.log`: "name 'fedora' is not defined"
7. Traced to unconditional `fedora.client.baseclient` usage
8. Confirmed python3-fedora package not available in Fedora 43
9. Created patch to wrap FAS code in `have_fas` conditional
10. Verified fix resolves the issue

## Notes

- The original code comment says "Ugly hack: FAS uses $HOME at time of
  import" which suggests this was always meant to be FAS-specific code
- The fact that there's already a `have_fas` variable shows the developers
  intended to support environments without FAS
- This patch fixes an oversight where the FAS check was incomplete
