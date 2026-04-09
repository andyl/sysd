# RelDep

RelDep Tasks are for deploying Elixir Releases to bare metal servers over SSH.
RelDep provides a minimalist deployment workflow targeting LAN/internal
environments, using YAML configuration, SSHex for SSH connectivity, and systemd
for service management.

Goals

- Provide a complete CLI via Mix tasks for the full deployment lifecycle
- Support multi-server deployments configured through a simple YAML file
- Use systemd for reliable service management on remote servers
- Keep the tool minimal with no proxy, SSL provisioning, or complex orchestration

Non-Goals

- Zero-downtime or rolling deployments (service goes offline during deploy)
- SSL/TLS provisioning or reverse proxy configuration
- Container-based or cloud-native deployments
- Multi-architecture release builds

## Installation

The package can be installed
by adding `reldep` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:reldep, "~> 0.2.1"}
  ]
end
```

## Mix Tasks

### reldep.init

Generate starter configuration files in the consumer project:
- `config/reldep.yaml` with default server and SSH settings
- `priv/reldep/<appname>.service` systemd service file as an EEX template

### reldep.sshcheck

Validate SSH connectivity and permissions on all configured servers:
- Test SSH connection to each server
- Verify the deploy user has sudo access
- Verify the deploy user can create `/opt/reldep/<appname>`

### reldep.setup

Perform first-time server setup and initial deploy for each server:
- Create the systemd service file at `/etc/systemd/services/<appname>.service`
- Create the `/opt/reldep/<appname>` directory structure
- Run the deploy workflow (see reldep.deploy)

### reldep.release

Build a production release tarball and optionally publish it to the
configured publishers:
- Verify that the `v<@version>` git tag exists locally (create it with
  `mix git_ops.release`)
- Run publisher preflight checks up front so misconfiguration fails fast
- Skip the build if a tarball for `@version` already exists, unless
  `--force` is passed
- Otherwise run `mix assets.deploy` followed by `mix release`
- Invoke each configured publisher in order

Flags: `--force`, `--replace`, `--no-publish`.

### reldep.deploy

Push an existing release tarball to every configured server:
- If no local tarball exists for `@version`, invoke `mix reldep.release`
  to build one (the default path)
- With `--from-release`, fetch the tarball for `@version` from the first
  fetch-capable publisher — useful for deploying from a fresh checkout
- For each server:
  - Copy the tarball to `/opt/reldep/<appname>/archives/<version>.tar.gz`
  - Extract the release to `/opt/reldep/<appname>/releases/<version>`
  - Update the symlink `/opt/reldep/<appname>/current` to point to the new release
  - Start or restart the systemd service
  - Write `/opt/reldep/<appname>/releases/<version>/RELEASE_INFO` with
    the git sha, build host, timestamp, and publisher URL (if used)

### reldep.versions

List deployed release versions on each configured server by reading `/opt/reldep/<appname>/releases`.

### reldep.rollback

Roll back to a previous release version on all servers:
- Accept a version argument
- Update the symlink `/opt/reldep/<appname>/current` to point to the specified version
- Restart the systemd service

### reldep.remove

Remove an old release version from all servers:
- Accept a version argument
- Refuse to remove the currently active version
- Remove `/opt/reldep/<appname>/releases/<version>` and `/opt/reldep/<appname>/archives/<version>.tar`

### reldep.cleanup

Fully remove RelDep from a specific server:
- Remove the server entry from `config/reldep.yaml`
- Remove the systemd service file
- Remove the `/opt/reldep/<appname>` directory

## Configuration

YAML configuration at `config/reldep.yaml`:

```yaml
servers:
  - host1
  - host2
ssh:
  user: <name>

# Optional. Publishers run in order during `mix reldep.release` and are
# walked in order for `mix reldep.deploy --from-release`. Omit the
# `release.publish` block entirely for a local-only build.
release:
  publish:
    - type: github
      draft: false
      prerelease: false
    - type: file
      path: /mnt/releases/myapp/
```

### Publishers

Two publisher types ship out of the box:

- **`github`** — uses the `gh` CLI to upload the tarball as a release
  asset on the `v<@version>` tag. Requires `gh` on `$PATH`, a valid
  `gh auth status`, and a `github.com` origin remote.
- **`file`** — copies the tarball to `<path>/<app>-<version>.tar.gz`.
  Useful for NFS shares, static web directories, or local archive
  folders. The target directory must already exist and be writable.

Typical flow:

```
mix git_ops.release                    # bump version, create v<x.y.z>
MIX_ENV=prod mix reldep.release        # build and publish
MIX_ENV=prod mix reldep.deploy         # push to servers
```

Deploying from a fresh checkout with no local build:

```
git checkout v0.3.0
MIX_ENV=prod mix reldep.deploy --from-release
```

## Remote Server Layout

```
/opt/reldep/<appname>/
  archives/<version>.tar
  releases/<version>/
  current -> releases/<version>
```

Each application gets its own subdirectory under `/opt/reldep/`, allowing
multiple apps to be deployed on the same server.
