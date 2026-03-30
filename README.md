# Ziprel

Ziprel Tasks are for deploying Elixir Releases to bare metal servers over SSH.
Ziprel provides a minimalist deployment workflow targeting LAN/internal
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
by adding `ziprel` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ziprel, "~> 0.2.0"}
  ]
end
```

## Mix Tasks

### ziprel.init

Generate starter configuration files in the consumer project:
- `config/ziprel.yaml` with default server and SSH settings
- `priv/ziprel/<appname>.service` systemd service file as an EEX template

### ziprel.sshcheck

Validate SSH connectivity and permissions on all configured servers:
- Test SSH connection to each server
- Verify the deploy user has sudo access
- Verify the deploy user can create `/opt/ziprel/<appname>`

### ziprel.setup

Perform first-time server setup and initial deploy for each server:
- Create the systemd service file at `/etc/systemd/services/<appname>.service`
- Create the `/opt/ziprel/<appname>` directory structure
- Run the deploy workflow (see ziprel.deploy)

### ziprel.deploy

Build a release and deploy it to all configured servers:
- Generate a new release with `MIX_ENV=prod mix release`
- For each server:
  - Copy the tar file to `/opt/ziprel/<appname>/archives/<version>.tar`
  - Extract the release to `/opt/ziprel/<appname>/releases/<version>`
  - Update the symlink `/opt/ziprel/<appname>/current` to point to the new release
  - Start or restart the systemd service

### ziprel.versions

List deployed release versions on each configured server by reading `/opt/ziprel/<appname>/releases`.

### ziprel.rollback

Roll back to a previous release version on all servers:
- Accept a version argument
- Update the symlink `/opt/ziprel/<appname>/current` to point to the specified version
- Restart the systemd service

### ziprel.remove

Remove an old release version from all servers:
- Accept a version argument
- Refuse to remove the currently active version
- Remove `/opt/ziprel/<appname>/releases/<version>` and `/opt/ziprel/<appname>/archives/<version>.tar`

### ziprel.cleanup

Fully remove Ziprel from a specific server:
- Remove the server entry from `config/ziprel.yaml`
- Remove the systemd service file
- Remove the `/opt/ziprel/<appname>` directory

## Configuration

YAML configuration at `config/ziprel.yaml`:

```yaml
servers:
  - host1
  - host2
ssh:
  user: <name>
```

## Remote Server Layout

```
/opt/ziprel/<appname>/
  archives/<version>.tar
  releases/<version>/
  current -> releases/<version>
```

Each application gets its own subdirectory under `/opt/ziprel/`, allowing
multiple apps to be deployed on the same server.
