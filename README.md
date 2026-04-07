# Relman

Relman Tasks are for deploying Elixir Releases to bare metal servers over SSH.
Relman provides a minimalist deployment workflow targeting LAN/internal
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
by adding `relman` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:relman, "~> 0.2.1"}
  ]
end
```

## Mix Tasks

### relman.init

Generate starter configuration files in the consumer project:
- `config/relman.yaml` with default server and SSH settings
- `priv/relman/<appname>.service` systemd service file as an EEX template

### relman.sshcheck

Validate SSH connectivity and permissions on all configured servers:
- Test SSH connection to each server
- Verify the deploy user has sudo access
- Verify the deploy user can create `/opt/relman/<appname>`

### relman.setup

Perform first-time server setup and initial deploy for each server:
- Create the systemd service file at `/etc/systemd/services/<appname>.service`
- Create the `/opt/relman/<appname>` directory structure
- Run the deploy workflow (see relman.deploy)

### relman.deploy

Build a release and deploy it to all configured servers:
- Generate a new release with `MIX_ENV=prod mix release`
- For each server:
  - Copy the tar file to `/opt/relman/<appname>/archives/<version>.tar`
  - Extract the release to `/opt/relman/<appname>/releases/<version>`
  - Update the symlink `/opt/relman/<appname>/current` to point to the new release
  - Start or restart the systemd service

### relman.versions

List deployed release versions on each configured server by reading `/opt/relman/<appname>/releases`.

### relman.rollback

Roll back to a previous release version on all servers:
- Accept a version argument
- Update the symlink `/opt/relman/<appname>/current` to point to the specified version
- Restart the systemd service

### relman.remove

Remove an old release version from all servers:
- Accept a version argument
- Refuse to remove the currently active version
- Remove `/opt/relman/<appname>/releases/<version>` and `/opt/relman/<appname>/archives/<version>.tar`

### relman.cleanup

Fully remove Relman from a specific server:
- Remove the server entry from `config/relman.yaml`
- Remove the systemd service file
- Remove the `/opt/relman/<appname>` directory

## Configuration

YAML configuration at `config/relman.yaml`:

```yaml
servers:
  - host1
  - host2
ssh:
  user: <name>
```

## Remote Server Layout

```
/opt/relman/<appname>/
  archives/<version>.tar
  releases/<version>/
  current -> releases/<version>
```

Each application gets its own subdirectory under `/opt/relman/`, allowing
multiple apps to be deployed on the same server.
