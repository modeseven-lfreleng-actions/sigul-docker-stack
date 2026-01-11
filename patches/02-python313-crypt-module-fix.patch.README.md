<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# Python 3.13 crypt Module Compatibility Patch

## Overview

This patch addresses the removal of the `crypt` module in Python 3.13+. The
`crypt` module became deprecated in Python 3.11 and Python 3.13 removed it,
causing sigul server components to fail at runtime.

## Problem

Sigul v1.4 uses the standard library `crypt` module for SHA-512 password
hashing in:

- `src/server_common.py` - Password creation/hashing
- `src/server.py` - Password verification for authentication

When running on Python 3.13 (default in Fedora 43), the import fails with:

```text
ModuleNotFoundError: No module named 'crypt'
```

## Solution

Replace `crypt.crypt()` with `passlib.hash.sha512_crypt`, which provides:

- Drop-in replacement for SHA-512 password hashing
- Full compatibility with existing password hashes
- Active maintenance and Python 3.13+ support
- Industry-standard cryptographic library

## Changes

### server_common.py

- Replace `import crypt` with `from passlib.hash import sha512_crypt`
- Update password hashing to use `sha512_crypt.using(rounds=5000).hash()`
- Maintain salt generation logic using existing NSS random generator

### server.py

- Replace `import crypt` with `from passlib.hash import sha512_crypt`
- Update password verification to use `sha512_crypt.verify()`
- Convert stored password from bytes to string for verification

## Dependencies

This patch requires the `passlib` library:

```bash
pip3 install passlib
```

## Compatibility

- Backward compatible with existing password hashes
- Works with Python 3.13+
- No migration of existing user accounts required
- SHA-512 algorithm remains unchanged

## Testing

Verify the patch works by:

1. Creating a user with `sigul_server_add_admin`
2. Authenticating with the created credentials
3. Confirming database schema creation succeeds

## References

- [PEP 594 - Removing deprecated modules](https://peps.python.org/pep-0594/)
- [Python 3.13 Release Notes](https://docs.python.org/3.13/whatsnew/3.13.html)
- [Passlib Documentation](https://passlib.readthedocs.io/)
