<!--
SPDX-License-Identifier: Apache-2.0
SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# Debug and Testing Tools

This directory contains tools for debugging and testing the Sigul Docker stack
locally without relying on GitHub Actions.

## Available Tools

### 1. Local Stack Deployment Test (`test-stack-deployment.sh`)

Simulates the GitHub Actions workflow locally by building, saving, loading, and
deploying containers.

**Usage:**

```bash
# Test deployment with existing images
./debug/test-stack-deployment.sh

# Build containers first, then deploy
./debug/test-stack-deployment.sh --build-first

# Clean everything and start fresh
./debug/test-stack-deployment.sh --clean --build-first

# Build and save images without deploying
./debug/test-stack-deployment.sh --build-first --skip-deploy --verbose

# Show all options
./debug/test-stack-deployment.sh --help
```

**Features:**

- Builds containers for the current platform (amd64 or arm64)
- Saves built images to `/tmp/*.tar` files (simulates CI artifacts)
- Loads images from tar files (simulates artifact download)
- Deploys stack using the deployment script
- Verifies no rebuilding occurs during deployment

**Workflow Steps:**

1. **Build** - Creates container images using Dockerfiles
2. **Save** - Exports images to tar archives
3. **Load** - Imports images from tar archives
4. **Deploy** - Runs `scripts/deploy-sigul-infrastructure.sh`

### 2. Act Workflow Testing (`test-workflow-with-act.sh`)

Tests GitHub Actions workflows locally using [nektos/act](https://github.com/nektos/act).

**Prerequisites:**

Install act:

```bash
# macOS
brew install act

# Linux
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash
```

**Usage:**

```bash
# List all available jobs in the workflow
./debug/test-workflow-with-act.sh --list

# Test stack deployment (dry-run first)
./debug/test-workflow-with-act.sh --dry-run stack-deploy-test

# Actually run stack deployment test
./debug/test-workflow-with-act.sh stack-deploy-test

# Clear act cache before running
./debug/test-workflow-with-act.sh --no-cache stack-deploy-test

# Run on specific platform
./debug/test-workflow-with-act.sh --platform linux/arm64 stack-deploy-test

# Show all options
./debug/test-workflow-with-act.sh --help
```

**Available Jobs:**

- `build-containers` - Build all container images
- `stack-deploy-test` - Test stack deployment
- `functional-tests` - Run functional tests
- `all` - Run complete workflow (resource intensive!)

**Limitations:**

- ARM builds may not work on x86 hosts and vice versa
- Some GitHub Actions features may behave differently
- Network connectivity may differ from GitHub Actions
- Resource intensive - use `--dry-run` first

## Common Debugging Scenarios

### Scenario 1: Test if containers rebuild during deployment

```bash
# Build and deploy
./debug/test-stack-deployment.sh --clean --build-first --verbose

# Check deployment script logs for "docker build" (should not appear)
```

**Expected:** No `docker build` commands should run during deployment.

**Actual Fix:** Added `--no-build` flag to `docker compose up` commands.

### Scenario 2: Test complete CI workflow locally

```bash
# List available jobs
./debug/test-workflow-with-act.sh --list

# Dry-run to see what will execute
./debug/test-workflow-with-act.sh --dry-run stack-deploy-test

# Run the actual test
./debug/test-workflow-with-act.sh stack-deploy-test
```

### Scenario 3: Debug container startup failures

```bash
# Deploy with verbose output
./debug/test-stack-deployment.sh --build-first --verbose

# Check logs after failure
docker logs sigul-cert-init
docker logs sigul-bridge
docker logs sigul-server

# Inspect container state
docker ps -a --filter "name=sigul"
docker inspect sigul-bridge
```

### Scenario 4: Test with clean environment

```bash
# Remove everything and start fresh
./debug/test-stack-deployment.sh --clean --build-first

# Check that volumes exist
docker volume ls --filter "name=sigul"
```

## Troubleshooting

### Issue: Images not found

**Problem:** `load_containers` reports images not found

**Solution:**

```bash
# Build images first
./debug/test-stack-deployment.sh --build-first --skip-deploy

# Verify tar files exist
ls -lh /tmp/*-linux-*.tar
```

### Issue: Containers rebuild during deployment

**Problem:** Build logs appear when running deployment

**Solution:**

- Check `docker-compose.sigul.yml` has `image:` fields set
- Verify `SIGUL_*_IMAGE` environment variables exist
- Ensure compose commands include the `--no-build` flag

### Issue: Act fails to run

**Problem:** Act command not found or fails

**Solution:**

```bash
# Check for act installation
which act

# Show version
command -v act && act --version

# Check Docker is running
docker ps

# Try with dry-run first
./debug/test-workflow-with-act.sh --dry-run --list
```

### Issue: Permission denied

**Problem:** Scripts fail with permission errors

**Solution:**

```bash
# Make scripts executable
chmod +x debug/*.sh

# Check Docker permissions
docker ps
```

## Environment Variables

Both scripts respect these environment variables:

- `SIGUL_SERVER_IMAGE` - Server container image name
- `SIGUL_BRIDGE_IMAGE` - Bridge container image name
- `SIGUL_RUNNER_PLATFORM` - Platform identifier (e.g., `linux-amd64`)
- `SIGUL_DOCKER_PLATFORM` - Docker platform (e.g., `linux/amd64`)
- `VERBOSE` - Enable verbose output
- `DEBUG` - Enable debug mode

## Cleanup

Remove test artifacts:

```bash
# Stop and remove all containers
docker compose -f docker-compose.sigul.yml down -v

# Remove saved images
rm -f /tmp/*-linux-*.tar

# Remove test artifacts
rm -rf test-artifacts/

# Remove act cache
rm -rf ~/.cache/act
```

## Best Practices

1. **Always use `--dry-run` first** when testing with act
2. **Use `--verbose`** to see detailed output during debugging
3. **Clean between tests** using `--clean` flag
4. **Check logs** after failures using `docker logs`
5. **Verify images** with `docker images` before deploying

## Related Scripts

- `../scripts/deploy-sigul-infrastructure.sh` - Main deployment script
- `../scripts/cert-init.sh` - Certificate initialization
- `../scripts/entrypoint-bridge.sh` - Bridge entrypoint
- `../scripts/entrypoint-server.sh` - Server entrypoint

## References

- [nektos/act](https://github.com/nektos/act) - Run GitHub Actions locally
- [Docker Compose](https://docs.docker.com/compose/) - Multi-container Docker
- [GitHub Actions](https://docs.github.com/en/actions) - CI/CD platform
