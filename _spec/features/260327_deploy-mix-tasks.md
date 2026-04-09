# Deploy Mix Tasks

## Summary

Implement the full set of Sysd Mix tasks for deploying Elixir Releases to
bare metal servers over SSH. Sysd provides a minimalist deployment workflow
targeting LAN/internal environments, using YAML configuration, SSHex for SSH
connectivity, and systemd for service management.

## Goals

- Provide a complete CLI via Mix tasks for the full deployment lifecycle
- Support multi-server deployments configured through a simple YAML file
- Use systemd for reliable service management on remote servers
- Keep the tool minimal with no proxy, SSL provisioning, or complex orchestration

## Non-Goals

- Zero-downtime or rolling deployments (service goes offline during deploy)
- SSL/TLS provisioning or reverse proxy configuration
- Container-based or cloud-native deployments
- Multi-architecture release builds

## Mix Tasks

### sysd

Print a help overview listing all available sysd Mix tasks with a short
description of each.

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

Build a release and deploy it to all configured servers:
- Generate a new release with `MIX_ENV=prod mix release`
- For each server:
  - Copy the tar file to `/opt/sysd/<appname>/archives/<version>.tar`
  - Extract the release to `/opt/sysd/<appname>/releases/<version>`
  - Update the symlink `/opt/sysd/<appname>/current` to point to the new release
  - Start or restart the systemd service

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

Fully remove Sysd from a specific server:
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

## Remote Server Layout

```
/opt/sysd/<appname>/
  archives/<version>.tar
  releases/<version>/
  current -> releases/<version>
```
