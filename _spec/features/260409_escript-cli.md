# Escript CLI

## Summary

Add a standalone escript binary (`sysd`) that exposes all deployment
operations as CLI subcommands. The escript, Mix tasks, and Mix.install scripts
all become thin wrappers over a shared library core (`Sysd.Deploy.*`),
enforcing a hard no-IO/no-halt rule in the library layer. The escript uses
Optimus for argument parsing and supports a subcommand structure with tarball
reference schemes for flexible artifact sourcing.

## Goals

- Ship a standalone `sysd` escript installable system-wide, requiring only
  the Erlang runtime.
- Refactor deploy internals into `Sysd.Deploy.*` modules with a strict
  no-IO/no-halt rule so the library is reusable across all three caller modes.
- Support a subcommand CLI structure: deploy, check, versions, rollback,
  status, start, stop, restart, logs, tail, remove, cleanup.
- Accept tarball references in multiple schemes: `file://`, `gh://`, bare
  paths, and a placeholder for future `s3://`.
- Support a four-level configuration precedence chain: CLI flags, environment
  variable, project-local `sysd.yml`, user-level XDG config.
- Embed a systemd service template as a module attribute with an
  `X-Creator=sysd` marker comment.
- Enable `Mix.install` as a supported usage mode for programmatic deploy
  workflows.

## Non-Goals

- S3 tarball scheme implementation (reserved for a future feature).
- Interactive prompts or TUI elements in the escript.
- Daemon mode or background process management in the escript itself.
- Automatic escript update or self-update mechanism.
- Changes to existing Mix task behavior beyond making them thin wrappers over
  the refactored library core.

## Subcommands

### sysd deploy

Deploy a tarball to a remote host.

Arguments: `<host>`, `<tarball-ref>`.
Flags: `--app`, `--user`.

### sysd check

Verify SSH connectivity and host readiness.

Arguments: `<host>`.

### sysd versions

List installed versions of an app on a host.

Arguments: `<host>`, `<app>`.

### sysd rollback

Roll back to a previous version.

Arguments: `<host>`, `<app>`, optional `<version>`.

### sysd status

Show the running status of an app on a host.

Arguments: `<host>`, `<app>`.

### sysd start / stop / restart

Manage the systemd service for an app on a host.

Arguments: `<host>`, `<app>`.

### sysd logs

Show recent logs for an app on a host.

Arguments: `<host>`, `<app>`.

### sysd tail

Stream live logs for an app on a host.

Arguments: `<host>`, `<app>`.

### sysd remove

Remove an app and its systemd service from a host.

Arguments: `<host>`, `<app>`.

### sysd cleanup

Remove old release versions from a host, keeping the current version.

Arguments: `<host>`, `<app>`.

## Tarball Reference Schemes

The `<tarball-ref>` argument to `sysd deploy` accepts:

- `file:///path/to/app-0.2.1.tar.gz` — local file.
- `gh://owner/repo@v0.2.1` — fetch via `gh release download`.
- `./app-0.2.1.tar.gz` — bare path, treated as `file:`.
- `s3://bucket/key/app-0.2.1.tar.gz` — reserved for future implementation.

Parsing is handled by a dedicated `Sysd.TarballRef` module.

## Configuration

A four-level precedence chain (highest wins):

1. CLI flags (`--config /path/to/config.yml`).
2. Environment variable (`RELDEP_CONFIG=/path/to/config.yml`).
3. Project-local `sysd.yml` discovered by walking up from cwd.
4. User-level `~/.config/sysd/config.yml` (XDG).

Config loading is handled by `Sysd.Config.load/1`.

## Library Refactor

All deploy operations move into `Sysd.Deploy.*` modules with a public API
returning `{:ok, result}` / `{:error, reason}` tuples. No `IO.puts` or
`System.halt` calls are permitted in `Sysd.Deploy.*`. Output formatting and
process lifecycle belong exclusively to the caller (escript, Mix task, or
Mix.install script).

## Systemd Template

The systemd service template is embedded in the escript as a module attribute.
It is parameterized via config keys: `app`, `user`, `working_dir`,
`exec_start`, `environment`, `restart`, `restart_sec`. An `X-Creator=sysd`
marker comment identifies services managed by sysd.
