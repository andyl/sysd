# Sysd

Deploy Elixir Releases to bare metal servers over SSH as systemd services.
A minimalist deployment workflow targeting LAN/internal environments, using
YAML configuration, SSHex for SSH connectivity, and systemd for service
management.

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
by adding `sysd` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sysd, "~> 0.3.0"}
  ]
end
```

## Mix Tasks

### sysd.init

Generate starter configuration files in the consumer project:
- `config/sysd.yaml` with default server and SSH settings
- `priv/sysd/<appname>.service` systemd service file as an EEX template

### sysd.sshcheck

Validate SSH connectivity and permissions on all configured servers:
- Test SSH connection to each server
- Verify the deploy user has sudo access
- Verify the deploy user can create `/opt/sysd/<appname>`

### sysd.setup

Perform first-time server setup and initial deploy for each server:
- Create the systemd service file at `/etc/systemd/services/<appname>.service`
- Create the `/opt/sysd/<appname>` directory structure
- Run the deploy workflow (see sysd.deploy)

### sysd.release

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

### sysd.deploy

Push an existing release tarball to every configured server:
- If no local tarball exists for `@version`, invoke `mix sysd.release`
  to build one (the default path)
- With `--from-release`, fetch the tarball for `@version` from the first
  fetch-capable publisher — useful for deploying from a fresh checkout
- For each server:
  - Copy the tarball to `/opt/sysd/<appname>/archives/<version>.tar.gz`
  - Extract the release to `/opt/sysd/<appname>/releases/<version>`
  - Update the symlink `/opt/sysd/<appname>/current` to point to the new release
  - Start or restart the systemd service
  - Write `/opt/sysd/<appname>/releases/<version>/RELEASE_INFO` with
    the git sha, build host, timestamp, and publisher URL (if used)

### sysd.versions

List deployed release versions on each configured server by reading `/opt/sysd/<appname>/releases`.

### sysd.rollback

Roll back to a previous release version on all servers:
- Accept a version argument
- Update the symlink `/opt/sysd/<appname>/current` to point to the specified version
- Restart the systemd service

### sysd.remove

Remove an old release version from all servers:
- Accept a version argument
- Refuse to remove the currently active version
- Remove `/opt/sysd/<appname>/releases/<version>` and `/opt/sysd/<appname>/archives/<version>.tar`

### sysd.cleanup

Fully remove the deployment from a specific server:
- Remove the server entry from `config/sysd.yaml`
- Remove the systemd service file
- Remove the `/opt/sysd/<appname>` directory

## Configuration

YAML configuration at `config/sysd.yaml`:

```yaml
servers:
  - host1
  - host2
ssh:
  user: <name>

# Optional. Publishers run in order during `mix sysd.release` and are
# walked in order for `mix sysd.deploy --from-release`. Omit the
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
MIX_ENV=prod mix sysd.release          # build and publish
MIX_ENV=prod mix sysd.deploy           # push to servers
```

Deploying from a fresh checkout with no local build:

```
git checkout v0.3.0
MIX_ENV=prod mix sysd.deploy --from-release
```

## Remote Server Layout

```
/opt/sysd/<appname>/
  archives/<version>.tar
  releases/<version>/
  current -> releases/<version>
```

Each application gets its own subdirectory under `/opt/sysd/`, allowing
multiple apps to be deployed on the same server.
