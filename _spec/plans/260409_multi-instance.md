# Implementation Plan: Multi-Instance Services

**Spec:** `_spec/features/260409_multi-instance.md`
**Generated:** 2026-04-09

---

## Goal

Enable deploying multiple named instances of the same application on a single
host, each with its own systemd service file and environment variables,
configured via YAML and managed through existing CLI subcommands with a new
`--instance` flag.

## Scope

### In scope
- Config parsing for per-server instance definitions (`instance_name`, `environment_variables`)
- Systemd service file generation with instance-specific environment variables and `sysd_` prefix naming
- Service file installation/management per instance on remote hosts
- `--instance` flag on service-operating subcommands (escript CLI and Mix tasks)
- Operate on all instances when `--instance` is omitted
- System-wide config with `apps` key containing `tarfile_source` and per-server instances
- `SYSD_CONFIG_DIR` support in config precedence

### Out of scope
- Tarball build/release changes (instances share one release binary)
- Per-instance versioning
- Interactive instance creation
- Dynamic instance discovery

## Architecture & Design Decisions

### 1. Service naming: `sysd_<instance_name>.service`

Currently `Remote` uses `<app_name>.service`. Multi-instance changes this to `sysd_<instance_name>.service`. The `sysd_` prefix enables enumeration of all managed services via glob. The `install_service`, `cleanup`, `start/stop/restart`, `status`, `logs/tail` functions in `Remote` all take an `app_name` that maps to the systemd unit name — this becomes a `service_name` parameter (the instance name) distinct from `app_name` (used for `/opt/sysd/<app>/` paths).

### 2. Backward compatibility

When no instances are defined in config, behavior falls back to the current single-service model using `sysd_<app_name>` as the service name. This keeps existing single-instance deployments working without config changes. The `Remote` module functions gain an optional `service_name` parameter defaulting to `sysd_<app_name>`.

### 3. Config struct changes

`Sysd.Config` struct gains an `:instances` field — a list of `%{instance_name: String.t(), environment_variables: [String.t()]}` maps. When loading config, each server entry is parsed to extract its instance list. If no instances are defined, a default single instance is synthesized from the app name.

### 4. Environment variables in template

`Sysd.Systemd.render/1` currently takes a single `:environment` string param (default `"PHX_SERVER=true"`). For multi-instance, it needs to accept a list of environment variable strings and render multiple `Environment=` lines.

### 5. Deploy flow

`Sysd.Deploy.setup/2` currently installs one service file. With multi-instance, it iterates over instances for the target host, rendering and installing a service file for each. `deploy/3` similarly starts/restarts all relevant instances after uploading the tarball once.

## Implementation Steps

### 1. Extend `Sysd.Systemd.render/1` for multiple environment variables
- Files: `lib/sysd/systemd.ex`, `test/sysd/systemd_test.exs`
- Change `@service_template` to iterate over a list of environment lines using `<%= for env <- @environment_lines do %>Environment=<%= env %>\n<% end %>`
- Accept `:environment_variables` as a list of strings in params; fall back to `["PHX_SERVER=true"]` when absent
- Keep `:environment` as a single-string param for backward compat, converting it to a list internally
- Add `:description` param (defaults to `:app`) so instance name can override the `Description=` field
- Add tests for multi-env rendering

### 2. Add instance struct/type to `Sysd.Config`
- Files: `lib/sysd/config.ex`, `test/sysd/config_test.exs`
- Add `instances` field to `%Sysd.Config{}` struct (default: `[]`)
- Add `SYSD_CONFIG_DIR` to the config precedence chain (check for `config.yml` inside the directory)
- Parse the new YAML shape where each server entry is a map containing a list of instance definitions
- When servers are plain hostname strings (legacy), synthesize a default instance `%{instance_name: app_name, environment_variables: ["PHX_SERVER=true"]}`
- Add a helper `instances_for_host(config, host)` that returns the instance list for a given host
- Add tests for parsing both legacy and multi-instance config shapes

### 3. Change `Sysd.Remote` to use service names distinct from app names
- Files: `lib/sysd/remote.ex`, `test/sysd/remote_test.exs`
- Functions that interact with systemd (`install_service`, `start`, `stop`, `restart`, `status`, `logs`, `tail`, `cleanup`) currently use `app_name` as the systemd unit name. Add an optional `service_name` keyword opt; default to `"sysd_#{app_name}"`.
- `install_service/3` signature becomes `install_service(conn, service_name, service_content)` — the service file path becomes `/etc/systemd/system/#{service_name}.service`
- `deploy/4` stays the same for tarball upload/extraction (uses `app_name` for paths) but the start/restart at the end needs a `service_name` — add it as a 5th arg or keyword opt
- `cleanup/2` needs to handle removing multiple service files; add `cleanup_service(conn, service_name)` for a single service, keep `cleanup/2` for removing the app directory
- Update tests

### 4. Update `Sysd.Deploy` facade for multi-instance
- Files: `lib/sysd/deploy.ex`
- `setup/2`: iterate over instances for the host, render a service file per instance (with instance-specific env vars and description), call `Remote.install_service` for each
- `deploy/3`: after uploading tarball once, start/restart each instance service
- `start/stop/restart/status/logs/tail`: accept optional `:instance` in opts. When set, operate on that single instance. When nil, operate on all instances for the host (from config)
- `cleanup/2`: stop and remove all instance service files, then remove the app directory
- Add `service_name/2` helper: `"sysd_#{instance_name}"`

### 5. Add `--instance` flag to escript CLI
- Files: `lib/sysd/cli.ex`
- Add `instance` to `common_options/0`:
  ```
  instance: [short: "-i", long: "--instance", help: "Instance name", required: false]
  ```
- Thread `instance` through `base_opts/1` into the opts passed to `Sysd.Deploy.*`
- Update `run_status`, `run_start`, `run_stop`, `run_restart`, `run_tail`, `run_logs`, `run_cleanup`, `run_remove` to pass instance opt
- Update `run_setup` to handle instance-aware setup
- Update output formatting to show instance names when operating on multiple instances

### 6. Add `--instance` flag to Mix tasks
- Files: `lib/mix/tasks/sysd.status.ex`, `lib/mix/tasks/sysd.start.ex`, `lib/mix/tasks/sysd.stop.ex`, `lib/mix/tasks/sysd.restart.ex`, `lib/mix/tasks/sysd.tail.ex`, `lib/mix/tasks/sysd.remove.ex`, `lib/mix/tasks/sysd.cleanup.ex`, `lib/mix/tasks/sysd.setup.ex`
- Parse `--instance` from args using `OptionParser`
- Pass `:instance` through to `Sysd.Deploy.*` calls
- Update output to show per-instance results

### 7. Update `Sysd.Deploy.setup` to generate `sysd_` prefixed service files
- Files: `lib/sysd/deploy.ex`, `lib/sysd/remote.ex`
- Ensure all new service files use the `sysd_<instance_name>` naming convention
- The `sysd systemd` subcommand should also respect instance naming when generating to stdout

### 8. Add integration/unit tests for multi-instance flows
- Files: `test/sysd/config_test.exs`, `test/sysd/systemd_test.exs`, `test/sysd/deploy_test.exs`
- Config parsing with instance definitions
- Systemd template rendering with multiple env vars
- Default instance synthesis for legacy configs
- `instances_for_host/2` helper

## Dependencies & Ordering

1. **Step 1 (Systemd template)** and **Step 2 (Config parsing)** are independent — do them first in parallel.
2. **Step 3 (Remote service name)** depends on Step 1 for the template changes.
3. **Step 4 (Deploy facade)** depends on Steps 1, 2, and 3.
4. **Steps 5 and 6 (CLI flags)** depend on Step 4.
5. **Step 7 (naming convention)** is woven into Steps 3 and 4.
6. **Step 8 (tests)** should be written alongside each step, not deferred.

## Edge Cases & Risks

- **Backward compatibility**: Existing single-instance configs have no `instances` key. The default-instance synthesis (Step 2) must produce identical behavior to today, including service file naming. Migration path: old `<app>.service` files won't be auto-renamed to `sysd_<app>.service`. Consider documenting a manual migration or adding a one-time migration command.
- **Service file naming collision**: If an instance is named the same as another app's instance, service files collide. Validate uniqueness within a host during config parsing.
- **Partial failure on multi-instance operations**: Starting 3 instances where 1 fails. Return per-instance results, not a single ok/error.
- **SYSD_CONFIG_DIR vs SYSD_CONFIG_FILE**: The spec mentions `SYSD_CONFIG_DIR` but the existing code uses `SYSD_CONFIG_FILE`. Clarify whether both should be supported or if DIR replaces FILE.
- **Environment variable escaping**: Values with spaces or special chars (e.g. `TITLE="Joe's Docs"`) must be properly escaped in the systemd service file. Systemd uses its own escaping rules.

## Testing Strategy

- **Unit tests**: Config parsing (legacy shape, multi-instance shape, default synthesis, `instances_for_host`), Systemd rendering (single env, multi env, special chars), service name generation.
- **Integration tests**: Full `Deploy.setup` flow with multi-instance config producing correct service files. Mock SSH layer to verify correct commands are issued per instance.
- **Manual verification**: Deploy to a test host with a two-instance config, confirm both service files exist and contain correct env vars, start/stop individual instances via `--instance`.

## Open Questions

- [x] Should old `<app>.service` files be auto-migrated to `sysd_<app>.service`, or is this a breaking change requiring manual cleanup?  Answer: breaking change requiring manual cleanup.
- [x] Should `SYSD_CONFIG_DIR` coexist with `SYSD_CONFIG_FILE` or replace it? The spec says `SYSD_CONFIG_DIR`, current code has `SYSD_CONFIG_FILE`.  Answer: Chose one - either is ok with me, as long as we have just one.
- [x] When `--instance` is omitted and multiple instances exist, should destructive commands (stop, remove, cleanup) require confirmation or `--all`?  Answer: no confirmation needed - stop or destroy them all.
- [x] Should `sysd deploy` also install/update service files, or only `sysd setup`? Currently `deploy` doesn't touch service files — but adding instances might require updating env vars at deploy time.  Answer: only setup should touch service files.  Probably we should have a preflight check on the deploy phase to validate the correct presence of the service files.
- [x] What happens when config defines instances but the host still has an old single `<app>.service` file? Should setup detect and clean up stale service files?  Answer: don't worry about that - we'll do manual cleanup.
