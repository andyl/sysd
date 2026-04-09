# Installation & CLI Design

RelDep ships as both a **Mix dependency** and a **standalone escript**.
Both modes are thin wrappers over the same library core
(`RelDep.Deploy.*`).

## Installation Modes

### Mix dependency (project-local)

Add `:reldep` to `mix.exs` to get `mix reldep.*` tasks inside a
project. For developers who want deploy wired into their Mix workflow:

```elixir
defp aliases do
  [
    "deploy.all": ["release", "release.publish", "reldep.deploy"]
  ]
end
```

App name and version come from `mix.exs` — no duplication needed.

### Escript (system-wide)

A standalone `reldep` binary installed once per machine. For deploying
third-party applications where a published tarball exists but the
source is not local.

```
curl -L https://github.com/andyl/release_deployer/releases/download/v0.3.0/reldep \
  -o ~/.local/bin/reldep
chmod +x ~/.local/bin/reldep
```

The Erlang runtime is the only dependency.

### Mix.install (scripting)

```elixir
Mix.install([{:reldep, "~> 0.3"}])
```

Enables programmatic deploy workflows (canary deploys, multi-host
rollouts) without requiring a full Mix project.

## CLI Shape (Escript)

Subcommand structure. Use `Optimus` for argument parsing. Every
command is usable with pure CLI args and no config file.

```
reldep deploy <host> <tarball-ref> --app myapp --user deploy
reldep check <host>
reldep versions <host> <app>
reldep rollback <host> <app> [<version>]
reldep status <host> <app>
reldep start|stop|restart <host> <app>
reldep logs <host> <app>
reldep tail <host> <app>
reldep remove <host> <app>
reldep cleanup <host> <app>
```

### Tarball References

The `<tarball-ref>` argument accepts these schemes:

- `file:///path/to/app-0.2.1.tar.gz` — local file
- `gh://owner/repo@v0.2.1` — fetches via `gh release download`
- `s3://bucket/key/app-0.2.1.tar.gz` — future
- `./app-0.2.1.tar.gz` — bare path, treated as `file:`

## Library API

The escript, Mix tasks, and `Mix.install` scripts are all thin
wrappers. The library is the source of truth.

```
      ┌─────────────────────────────────────┐
      │      RelDep.Deploy (library)        │
      │  deploy/3, versions/2, rollback/3,  │
      │  status/2, logs/2, remove/2, ...    │
      └──────────────────┬──────────────────┘
                         │
      ┌──────────────────┼──────────────────┐
      │                  │                  │
      ▼                  ▼                  ▼
┌───────────┐      ┌───────────┐     ┌──────────────┐
│ Mix tasks │      │  escript  │     │ Mix.install  │
│ (project) │      │  (global) │     │   scripts    │
└───────────┘      └───────────┘     └──────────────┘
```

### Public Functions

```elixir
RelDep.Deploy.check(host, opts)
RelDep.Deploy.deploy(host, tarball_ref, opts)
RelDep.Deploy.versions(host, app, opts)
RelDep.Deploy.rollback(host, app, version, opts)
RelDep.Deploy.status(host, app, opts)
RelDep.Deploy.start(host, app, opts)
RelDep.Deploy.stop(host, app, opts)
RelDep.Deploy.restart(host, app, opts)
RelDep.Deploy.logs(host, app, opts)
RelDep.Deploy.remove(host, app, opts)
RelDep.Deploy.cleanup(host, app, opts)

RelDep.TarballRef.parse("gh://owner/repo@v0.2.1")
RelDep.Config.load(path_or_discover)
```

Returns are `{:ok, result}` / `{:error, reason}` tuples.

**Hard rule**: no `IO.puts` or `System.halt` in `RelDep.Deploy.*`.
Output and process lifecycle belong to the caller.

## Configuration

### Precedence (highest wins)

1. **CLI flags** — `--config /path/to/config.yml`
2. **Environment variable** — `RELDEP_CONFIG=/path/to/config.yml`
3. **Project-local `reldep.yml`** — discovered by walking up from cwd
4. **User-level** — `~/.config/reldep/config.yml` (XDG)

### Config Shape

```yaml
apps:
  myapp:
    servers:
      - host1.lan
      - host2.lan
    ssh:
      user: deploy
    source:
      type: github
      repo: andyl/myapp

  other_app:
    servers:
      - prod1.lan
    ssh:
      user: admin
    source:
      type: file
      path: /mnt/releases/other_app/
```

## Systemd Service Template

The template is embedded in the escript as a module attribute (same
pattern as `sup`). Parameterized via config keys: `app`, `user`,
`working_dir`, `exec_start`, `environment`, `restart`, `restart_sec`.

Include an `X-Creator=reldep` marker comment so `reldep` can identify
its own services on a host.

No separate `.service` file ships on disk. The template lives in code.

## Implementation Path

1. Refactor deploy internals into `RelDep.Deploy.*` with the
   no-IO/no-halt rule. Existing Mix tasks become thin wrappers.
2. Add `mix escript.build` target.
3. Implement config loading with the precedence chain.
4. Publish the escript as a GitHub release asset.
5. Document `Mix.install` as a supported usage mode.
