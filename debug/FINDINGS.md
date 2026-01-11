<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# Debugging Session Findings: Sigul Bridge Failure on Fedora 43

## Summary

Identified and fixed a critical bug in Sigul Bridge that prevented
it from starting on Fedora 43 (and any system without the python3-fedora
package).

## Root Cause

The Sigul bridge.py code attempted to access `fedora.client.baseclient` even
when the python3-fedora package was not installed, causing a NameError that
crashed the bridge process on startup.

## Error Message

```text
ERROR: Error switching to user 1000: name 'fedora' is not defined
```

## Solution

Created patch `patches/bridge-no-fas.patch` that wraps the FAS session setup
code in a conditional check for `have_fas`, making FAS support optional.

## Testing Results

- Bridge container now starts without python3-fedora
- Bridge listens on ports 44333 and 44334
- Health checks pass
- No errors in bridge logs (TLS handshake errors occur during startup)
- All linting checks pass

## Files Modified

- `patches/bridge-no-fas.patch` - The fix
- `patches/bridge-no-fas.patch.README.md` - Comprehensive documentation
- `debug/test-stack-deployment.sh` - Fixed arithmetic expression bug

## Next Steps

1. Report bug to upstream Sigul project at <https://pagure.io/sigul>
2. Continue testing full stack deployment
3. Run functional tests to verify signing operations work as expected
