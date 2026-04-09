# Multi-Instance Services

## Summary

Add support for deploying multiple service instances of the same application
to one or more hosts, each with its own systemd service file and unique
environment variable configuration. Instances are defined in YAML config
(project-level or system-wide) and result in distinct `sysd_<instance>.service`
files on the target host. This enables running the same app binary with
different configurations (port, data path, title, etc.) side by side.

## Goals

- Allow a single application to have multiple named instances per host, each
  with its own systemd service file and environment variables.
- Support instance configuration at both the project level (`config/sysd.yml`)
  and the system-wide level (`~/.config/sysd/config.yml`), plus an override
  via `SYSD_CONFIG_DIR`.
- Generate systemd service files named `sysd_<instance_name>.service` on the
  target host, using a shared template parameterized per instance.
- Prefix all managed service files with `sysd_` so they can be enumerated
  for auditing, cleanup, and recovery.
- Support a server-to-instances hierarchy: a server lists one or more instance
  definitions, each carrying a unique `instance_name` and a set of
  `environment_variables`.
- Extend existing subcommands (status, start, stop, restart, logs, tail,
  remove) to target a specific instance by name or all instances of an app.
- Support system-wide config that maps multiple apps, each with its own
  `tarfile_source` and per-server instance definitions.

## Non-Goals

- Changes to the tarball build or release process; instances share the same
  release binary.
- Interactive instance creation or wizard-style prompts.
- Dynamic instance discovery or auto-scaling; instances are statically
  defined in config.
- Per-instance release versioning; all instances of an app share the same
  release directory under `/opt/sysd/<app>/`.

## Config Structure

### Project-level (`config/sysd.yml`)

A `servers` key holds a list of host entries. Each host entry contains a list
of instance definitions with `instance_name` and `environment_variables`.

### System-wide (`~/.config/sysd/config.yml`)

An `apps` key holds a list of app entries. Each app entry includes a
`tarfile_source` and a `servers` list identical in structure to the
project-level format.

### Precedence

Order of precedence (highest wins):
1. `SYSD_CONFIG_DIR` environment variable.
2. `~/.config/sysd/config.yml`.
3. `config/sysd.yml`.

## Instance Naming

Each instance has a unique `instance_name` used as:
- The systemd service file name: `sysd_<instance_name>.service`.
- The `Description` field in the `[Unit]` section.
- The identifier for CLI subcommands targeting a specific instance.

## Host Artifacts

For an app `docpub` with instances `docpub1` and `docpub2` on `host1`:

- Shared release directory: `/opt/sysd/docpub/releases/...`
- Shared current symlink: `/opt/sysd/docpub/current`
- Instance service files:
  - `/etc/systemd/system/sysd_docpub1.service`
  - `/etc/systemd/system/sysd_docpub2.service`

Each service file contains instance-specific `Environment=` directives and
shares the same `ExecStart` and `ExecStop` paths pointing to the app binary.

## Subcommand Changes

Existing subcommands that operate on a service (status, start, stop, restart,
logs, tail, remove) accept an optional `--instance` flag to target a specific
instance by name. Without `--instance`, the command operates on all instances
of the app on the given host.

## Template Storage

- Project-specific: `priv/sysd/templates/application.service`.
- System-wide: `~/.config/sysd/templates/`.

Templates are parameterized with instance-specific values (name, environment
variables) at deploy time.
