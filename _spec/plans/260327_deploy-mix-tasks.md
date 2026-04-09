# Implementation Plan: Deploy Mix Tasks

**Spec:** `_spec/features/260327_deploy-mix-tasks.md`
**Generated:** 2026-03-27

---

## Goal

Implement the full set of Sysd Mix tasks (`sysd`, `sysd.init`, `sysd.sshcheck`, `sysd.setup`, `sysd.deploy`, `sysd.versions`, `sysd.rollback`, `sysd.remove`, `sysd.cleanup`) to provide a complete CLI for deploying Elixir Releases to bare metal servers over SSH.

## Scope

### In scope
- All 9 Mix tasks as specified
- YAML config parsing (`config/sysd.yaml`)
- EEX-based systemd service template generation
- SSH connectivity via SSHEx and Erlang `:ssh_sftp` for file transfer
- Remote directory management under `/opt/sysd/<appname>/`
- Symlink-based version switching
- Systemd service management via `sudo systemctl`

### Out of scope
- Zero-downtime / rolling deploys
- SSL/TLS provisioning or reverse proxy
- Container or cloud-native workflows
- Multi-architecture release builds
- Cross-compilation

## Architecture & Design Decisions

1. **Core module `Sysd`** — Replace the placeholder with shared logic: config loading, SSH connection management, remote command execution helpers, and constants (paths, directory layout).

2. **Config module `Sysd.Config`** — Responsible for reading and writing `config/sysd.yaml`. A YAML library dependency is needed (e.g. `yaml_elixir`). The config struct holds `servers` (list of hostnames) and `ssh` (map with `user` key, extensible for port/key options).

3. **SSH module `Sysd.SSH`** — Wraps SSHEx for command execution and Erlang's `:ssh_sftp` for file uploads. SSHEx does not support SCP/SFTP, so file transfer must use `:ssh_sftp.write_file/3` or `:ssh_sftp.start_channel/2` directly. This module provides `connect/2`, `run!/3`, `upload/4` functions.

4. **Remote module `Sysd.Remote`** — Higher-level operations on a connected server: create directories, deploy archives, manage symlinks, control systemd services, list versions. This keeps Mix tasks thin.

5. **Mix tasks under `lib/mix/tasks/`** — Each task is a thin wrapper that loads config, iterates over servers, and delegates to `Sysd.Remote`. Tasks use `Mix.shell().info/1` for output.

6. **EEX template for systemd** — Shipped as `priv/sysd/templates/app.service.eex` within the sysd package itself. `sysd.init` copies a rendered version into the consumer's `priv/sysd/<appname>.service`.

7. **YAML dependency** — Add `yaml_elixir` to `deps` for YAML parsing/encoding. It's lightweight and well-maintained.

8. **Release tar location** — `mix release` produces a tarball at `_build/prod/rel/<app>/<app>-<version>.tar.gz`. The deploy task locates this artifact after building.

## Implementation Steps

1. **Add `yaml_elixir` dependency**
   - Files: `mix.exs`
   - Add `{:yaml_elixir, "~> 2.11"}` to deps

2. **Create `Sysd.Config` module**
   - Files: `lib/sysd/config.ex`
   - Struct: `%Config{servers: [], ssh: %{user: nil}}`
   - `load/0` — reads `config/sysd.yaml` from the consumer project root, parses YAML, returns `%Config{}`
   - `write/1` — writes a `%Config{}` back to YAML
   - `remove_server/2` — removes a server entry and writes back
   - Validate required fields, raise clear errors for missing/malformed config

3. **Create `Sysd.SSH` module**
   - Files: `lib/sysd/ssh.ex`
   - `connect/2` — takes host and ssh config, returns `{:ok, conn}` via `SSHEx.connect/1`
   - `run!/3` — executes a command, raises on non-zero exit
   - `run/3` — executes a command, returns `{:ok, stdout, status}` or `{:error, reason}`
   - `upload/3` — opens an SFTP channel via `:ssh_sftp.start_channel/2` and writes a local file to a remote path

4. **Create `Sysd.Remote` module**
   - Files: `lib/sysd/remote.ex`
   - `setup_dirs/2` — creates `/opt/sysd/<appname>/{archives,releases}` on a connected server
   - `install_service/3` — writes the systemd service file to `/etc/systemd/services/<appname>.service` via sudo
   - `deploy/3` — uploads tar, extracts to releases dir, updates symlink, starts/restarts service
   - `list_versions/2` — `ls /opt/sysd/<appname>/releases` and returns list
   - `current_version/2` — `readlink /opt/sysd/<appname>/current` and extracts version
   - `rollback/2` — updates symlink and restarts service
   - `remove_version/2` — removes release and archive dirs (refuses if current)
   - `cleanup/2` — stops service, removes service file, removes `/opt/sysd/<appname>`

5. **Create systemd service EEX template**
   - Files: `priv/sysd/templates/app.service.eex`
   - Template with bindings for `app_name`, `user`, `release_path` (`/opt/sysd/<appname>/current`)

6. **Refactor `Sysd` root module**
   - Files: `lib/sysd.ex`
   - Remove placeholder `hello/0`
   - Add `app_name/0` — derives app name from Mix project config
   - Add `version/0` — derives version from Mix project config
   - Add `release_tar_path/0` — returns path to built release tarball

7. **Implement `mix sysd` task (help)**
   - Files: `lib/mix/tasks/sysd.ex`
   - Prints usage overview listing all tasks and one-line descriptions

8. **Implement `mix sysd.init` task**
   - Files: `lib/mix/tasks/sysd.init.ex`
   - Generates `config/sysd.yaml` with default content if it doesn't exist
   - Generates `priv/sysd/<appname>.service` from EEX template
   - Warns if files already exist (don't overwrite)

9. **Implement `mix sysd.sshcheck` task**
   - Files: `lib/mix/tasks/sysd.sshcheck.ex`
   - Loads config, iterates servers
   - For each: connect via SSH, run `whoami`, run `sudo -n true`, test directory creation under `/opt/sysd/<appname>`
   - Report pass/fail per server

10. **Implement `mix sysd.setup` task**
    - Files: `lib/mix/tasks/sysd.setup.ex`
    - Loads config, iterates servers
    - For each: connect, call `Remote.setup_dirs/1`, call `Remote.install_service/3`
    - Then invoke the deploy workflow

11. **Implement `mix sysd.deploy` task**
    - Files: `lib/mix/tasks/sysd.deploy.ex`
    - Run `MIX_ENV=prod mix release` via `Mix.Task.run("release")`
    - Locate the release tarball
    - Load config, iterate servers
    - For each: connect, call `Remote.deploy/3`

12. **Implement `mix sysd.versions` task**
    - Files: `lib/mix/tasks/sysd.versions.ex`
    - Loads config, iterates servers
    - For each: connect, call `Remote.list_versions/1`, print results

13. **Implement `mix sysd.rollback` task**
    - Files: `lib/mix/tasks/sysd.rollback.ex`
    - Parse version argument from CLI args
    - Loads config, iterates servers
    - For each: connect, call `Remote.rollback/2`

14. **Implement `mix sysd.remove` task**
    - Files: `lib/mix/tasks/sysd.remove.ex`
    - Parse version argument from CLI args
    - Loads config, iterates servers
    - For each: connect, check current version, call `Remote.remove_version/2`

15. **Implement `mix sysd.cleanup` task**
    - Files: `lib/mix/tasks/sysd.cleanup.ex`
    - Parse server argument from CLI args
    - Connect to that server, call `Remote.cleanup/1`
    - Call `Config.remove_server/2` to update YAML

16. **Update tests**
    - Files: `test/sysd_test.exs`, `test/sysd/config_test.exs`
    - Remove placeholder `hello` test
    - Add unit tests for `Sysd.Config` (load/write/remove_server with fixture YAML files)
    - Add unit tests for `Sysd` helper functions (app_name, version, release_tar_path)

## Dependencies & Ordering

- **Step 1** (yaml_elixir dep) must come first — steps 2 and 8 depend on it
- **Steps 2-5** (Config, SSH, Remote, template) are the foundation — all Mix tasks depend on them
- **Step 6** (refactor Sysd module) should precede task implementations
- **Step 7** (help task) is independent of other tasks
- **Steps 8-15** (Mix tasks) depend on steps 2-6 but are independent of each other
- **Step 16** (tests) can be written alongside each step but finalized last

## Edge Cases & Risks

- **SSHEx lacks SFTP/SCP**: File upload must use Erlang's `:ssh_sftp` directly on the same connection. Verify that SSHEx's connection ref is compatible with `:ssh_sftp.start_channel/1` (it should be, since SSHEx wraps `:ssh.connect`)
- **sudo without password**: `sshcheck` should verify passwordless sudo (`sudo -n`). If password-based sudo is needed, this is currently out of scope
- **Release tarball path**: The tar location varies by Elixir version and release config. Need to reliably locate `_build/prod/rel/<app>/<app>-<version>.tar.gz` and handle the case where `mix release` doesn't produce a tarball (tarball generation must be enabled in release config)
- **Config file not found**: Tasks that require config should print a clear error suggesting `mix sysd.init`
- **Removing current version**: `sysd.remove` must check the symlink target before deleting
- **Cleanup of running service**: `sysd.cleanup` should stop the service before removing files
- **YAML formatting**: `yaml_elixir` encoding should produce clean, readable YAML matching the spec format

## Testing Strategy

- **Unit tests** for `Sysd.Config`: read/write/parse YAML fixtures, test validation errors, test `remove_server`
- **Unit tests** for `Sysd` helpers: verify app name, version, tarball path derivation
- **Unit tests** for `Sysd.Remote` command building: verify the SSH commands generated for each operation (mock the SSH layer)
- **Integration testing** is manual: requires a real SSH target server. Document a manual test checklist covering the full `init → sshcheck → setup → deploy → versions → rollback → remove → cleanup` lifecycle
- **Mix task tests**: verify task modules exist and have `@shortdoc` set, verify help task output

## Open Questions

- [x] Should `yaml_elixir` be a runtime dependency or should we consider a lighter alternative (e.g. hand-rolled YAML for the simple config format)? Answer: runtime is OK 
- [x] Should the SSH user's private key path be configurable in `sysd.yaml` or rely on the system SSH agent?  Answer: rely on SSH agent.  We assume that user has already setup SSH keys on remote servers.
- [x] Should `sysd.deploy` build the release itself or expect a pre-built tarball? (Spec says build, but some users may want to separate build and deploy steps)  Answer: build the release as part of the deploy process.
- [x] Should `sysd.setup` automatically run `sysd.deploy` or keep them as separate manual steps?  Answer: just do the setup steps, then end with a message telling the user to run `mix sysd.deploy`
- [x] What should the systemd service `ExecStart` command look like? Typically `/opt/sysd/<appname>/current/bin/<app> start` — confirm this matches the Elixir Release binary convention Answer: `PHX_SERVER=true /opt/sysd/<appname>/current/bin/<app> start`
