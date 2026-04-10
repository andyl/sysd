# Sysd

Deploy Elixir Releases to bare metal servers over SSH as systemd services.
A minimalist deployment workflow targeting LAN/internal environments, using
YAML configuration, SSHex for SSH connectivity, and systemd for service
management.

Goals

- Provide a complete CLI via Mix tasks and a standalone escript
- Support multi-server deployments configured through a simple YAML file
- Support multiple named instances of the same app on a single host
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
    {:sysd, "~> 0.4.2"}
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

## Configuration

### Project-level config

YAML configuration at `config/sysd.yaml` (or `config/sysd.yml`):

```yaml
servers:
  - host: web1
    instances:
      - instance_name: myapp_prod
        environment_variables:
          PORT: 4001
          DATA_DIR: /data/prod
      - instance_name: myapp_staging
        environment_variables:
          PORT: 4002
          DATA_DIR: /data/staging
  - host: web2
    instances:
      - instance_name: myapp_prod
        environment_variables:
          PORT: 4001
ssh:
  user: deploy
```

Each server entry can define one or more **instances**. An instance is a
named systemd service with its own set of environment variables. All
instances on a host share the same release binary (at
`/opt/sysd/<appname>/current`) but run as independent systemd services.

Single-instance configs without `instances` are also supported:

```yaml
servers:
  - host1
  - host2
ssh:
  user: deploy
```

### System-wide config

For the escript, a system-wide config can live at `~/.config/sysd/config.yml`.
This format wraps server definitions under an `apps:` key so that multiple
applications can be managed from a single file:

```yaml
apps:
  myapp:
    servers:
      - host: web1
        instances:
          - instance_name: app_prod
            environment_variables:
              PORT: 4001
    ssh:
      user: deploy
```

### Config file resolution

Config files are resolved in this order (first match wins):

1. Explicit `--config` / `-c` path (CLI) or `:config_path` option
2. `SYSD_CONFIG_FILE` environment variable
3. Walk up from cwd looking for `sysd.yml`
4. XDG fallback: `~/.config/sysd/config.yml`

## Multi-Instance Deployment

The core idea: a single release tarball is deployed once per host, but
multiple systemd services run against it, each with a unique name and
environment variables.

### How it works

1. Define named instances under each server in `config/sysd.yaml`
2. `mix sysd.setup` (or `sysd setup`) generates one systemd service file per
   instance, installed at `/etc/systemd/system/sysd_<instance_name>.service`
3. `mix sysd.deploy` uploads the tarball once and restarts all instances
4. Each instance gets its own `Environment=` lines in its service file

### Systemd service files

Sysd generates service files from a built-in template. Each instance
produces a service file like this:

```ini
# X-Creator=sysd
[Unit]
Description=myapp_prod
After=network.target

[Service]
Type=simple
User=deploy
WorkingDirectory=/opt/sysd/myapp/current
Environment=PORT=4001
Environment=DATA_DIR=/data/prod
Environment=PHX_SERVER=true
ExecStart=/opt/sysd/myapp/current/bin/myapp start
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Service files are named with a `sysd_` prefix (e.g. `sysd_myapp_prod.service`)
so that Sysd can track which files it manages. `PHX_SERVER=true` is included
by default for Phoenix applications.

### Environment variables

Environment variables are the primary mechanism for configuring
instances. Common uses:

- `PORT` — bind each instance to a different port
- `DATABASE_URL` — point instances at different databases
- `DATA_DIR` — use different data directories
- `PHX_SERVER` — set automatically to `true`

Variables are defined per-instance in the YAML config as key-value pairs
under `environment_variables:`. They appear as `Environment=KEY=VALUE`
lines in the generated systemd service file.

### Targeting a specific instance

Most commands accept `--instance` / `-i` to target a single instance
instead of all instances on a host:

```bash
# Mix tasks
mix sysd.start web1 -i myapp_prod
mix sysd.stop web1 --instance myapp_staging
mix sysd.status web1 -i myapp_prod

# Escript
sysd start -a myapp -i myapp_prod web1
sysd status -a myapp web1              # all instances
```

When `--instance` is omitted, the command operates on all instances
for the given host.

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

### sysd.check

Validate SSH connectivity and permissions on all configured servers:
- Test SSH connection to each server
- Verify the deploy user has sudo access
- Verify the deploy user can create `/opt/sysd/<appname>`

### sysd.setup

Perform first-time server setup and initial deploy for each server:
- Create the `/opt/sysd/<appname>` directory structure
- Generate and install a systemd service file for each instance
  (or a single service file for legacy configs)
- Run the deploy workflow (see sysd.deploy)

### sysd.deploy

Push a release tarball to every configured server:
- If no local tarball exists for `@version`, build one by running
  `mix assets.deploy` followed by `mix release`
- For each server:
  - Copy the tarball to `/opt/sysd/<appname>/archives/<version>.tar.gz`
  - Extract the release to `/opt/sysd/<appname>/releases/<version>`
  - Update the symlink `/opt/sysd/<appname>/current` to point to the new release
  - Start or restart all systemd service instances
  - Write `/opt/sysd/<appname>/releases/<version>/RELEASE_INFO` with
    the git sha, build host, and timestamp

### sysd.versions

List deployed release versions on each configured server by reading `/opt/sysd/<appname>/releases`.

### sysd.rollback

Roll back to a previous release version on all servers:
- Accept a version argument
- Update the symlink `/opt/sysd/<appname>/current` to point to the specified version
- Restart all systemd service instances

### sysd.status

Show the systemd service status on configured servers. Without arguments,
checks all servers. With a server name, checks only that server. Use
`--instance` / `-i` to check a specific instance.

### sysd.start

Start the systemd service. Without arguments, starts on all servers. With
a server name, starts only on that server. Use `--instance` / `-i` to
start a specific instance.

### sysd.stop

Stop the systemd service. Without arguments, stops on all servers. With
a server name, stops only on that server. Use `--instance` / `-i` to
stop a specific instance.

### sysd.restart

Restart the systemd service. Without arguments, restarts on all servers.
With a server name, restarts only on that server. Use `--instance` / `-i`
to restart a specific instance.

### sysd.tail

Tail systemd journal logs from a specific server. A server name is required
because tailing is time-bounded and running sequentially across multiple
servers would not produce useful output.

### sysd.remove

Remove an old release version from all servers:
- Accept a version argument
- Refuse to remove the currently active version
- Remove `/opt/sysd/<appname>/releases/<version>` and `/opt/sysd/<appname>/archives/<version>.tar`

### sysd.cleanup

Fully remove the deployment from a specific server:
- Remove all systemd service files for the app (`sysd_*.service`)
- Remove the `/opt/sysd/<appname>` directory
- Use `--instance` / `-i` to remove only a specific instance's service
  file without deleting the app directory

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

/etc/systemd/system/
  sysd_<instance1>.service
  sysd_<instance2>.service
```

Each application gets its own subdirectory under `/opt/sysd/`, allowing
multiple apps to be deployed on the same server. All instances of the same
app share the release binary via the `current` symlink but run as separate
systemd services, each with its own environment configuration.
