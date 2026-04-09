# Sysd

Deploy Elixir Releases to bare metal servers over SSH as systemd services.
A minimalist deployment workflow targeting LAN/internal environments, using
YAML configuration, SSHex for SSH connectivity, and systemd for service
management.

Goals

- Provide a complete CLI via Mix tasks and a standalone escript
- Support multi-server deployments configured through a simple YAML file
- Use systemd for reliable service management on remote servers
- Keep the tool minimal with no proxy, SSL provisioning, or complex orchestration

Non-Goals

- Zero-downtime or rolling deployments (service goes offline during deploy)
- SSL/TLS provisioning or reverse proxy configuration
- Container-based or cloud-native deployments
- Multi-architecture release builds

## Installation

### Mix dependency (project-local)

Add `sysd` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sysd, "~> 0.3.0"}
  ]
end
```

This gives you access to `mix sysd.*` tasks inside your project. App
name and version come from `mix.exs` — no duplication needed.

### Escript (system-wide)

A standalone `sysd` binary installed once per machine. Useful for
deploying third-party applications where a published tarball exists
but the source is not local. The Erlang runtime is the only
dependency.

```
curl -L https://github.com/andyl/sysd/releases/download/v0.3.0/sysd \
  -o ~/.local/bin/sysd
chmod +x ~/.local/bin/sysd
```

## Escript CLI

The escript uses a subcommand structure. Every command is usable with
pure CLI args and no config file.

```
sysd deploy <host> <tarball-ref> --app myapp --user deploy
sysd check <host>
sysd versions <host> <app>
sysd rollback <host> <app> [<version>]
sysd status <host> <app>
sysd start|stop|restart <host> <app>
sysd logs <host> <app>
sysd tail <host> <app>
sysd remove <host> <app>
sysd cleanup <host> <app>
```

### Tarball References

The `<tarball-ref>` argument accepts these schemes:

- `file:///path/to/app-0.2.1.tar.gz` — local file
- `gh://owner/repo@v0.2.1` — fetches via `gh release download`
- `./app-0.2.1.tar.gz` — bare path, treated as `file:`

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

### sysd.deploy

Push a release tarball to every configured server:
- If no local tarball exists for `@version`, build one by running
  `mix assets.deploy` followed by `mix release`
- For each server:
  - Copy the tarball to `/opt/sysd/<appname>/archives/<version>.tar.gz`
  - Extract the release to `/opt/sysd/<appname>/releases/<version>`
  - Update the symlink `/opt/sysd/<appname>/current` to point to the new release
  - Start or restart the systemd service
  - Write `/opt/sysd/<appname>/releases/<version>/RELEASE_INFO` with
    the git sha, build host, and timestamp

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
```

## Typical Flow

```
mix git_ops.release                    # bump version, create v<x.y.z>
MIX_ENV=prod mix sysd.deploy           # build and push to servers
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
