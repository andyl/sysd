# Installation & CLI Design

Sysd ships as both a **Mix dependency** and a **standalone escript**.
Both modes are thin wrappers over the same library core
(`Sysd.Deploy.*`).

## Installation Modes

### Mix dependency (project-local)

Add `:sysd` to `mix.exs` to get `mix sysd.*` tasks inside a
project. For developers who want deploy wired into their Mix workflow:

```elixir
defp aliases do
  [
    "deploy.all": ["release", "release.publish", "sysd.deploy"]
  ]
end
```

App name and version come from `mix.exs` — no duplication needed.

### Escript (system-wide)

A standalone `sysd` binary installed once per machine. For deploying
third-party applications where a published tarball exists but the
source is not local.

```
curl -L https://github.com/andyl/sysd/releases/download/v0.3.0/sysd \
  -o ~/.local/bin/sysd
chmod +x ~/.local/bin/sysd
```

The Erlang runtime is the only dependency.

### Mix.install (scripting)

```elixir
Mix.install([{:sysd, "~> 0.3"}])
```

Enables programmatic deploy workflows (canary deploys, multi-host
rollouts) without requiring a full Mix project.

## CLI Shape (Escript)

Subcommand structure. Use `Optimus` for argument parsing. Every
command is usable with pure CLI args and no config file.

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
- `s3://bucket/key/app-0.2.1.tar.gz` — future
- `./app-0.2.1.tar.gz` — bare path, treated as `file:`

## Library API

The escript, Mix tasks, and `Mix.install` scripts are all thin
wrappers. The library is the source of truth.

```
      ┌─────────────────────────────────────┐
      │      Sysd.Deploy (library)        │
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
Sysd.Deploy.check(host, opts)
Sysd.Deploy.deploy(host, tarball_ref, opts)
Sysd.Deploy.versions(host, app, opts)
Sysd.Deploy.rollback(host, app, version, opts)
Sysd.Deploy.status(host, app, opts)
Sysd.Deploy.start(host, app, opts)
Sysd.Deploy.stop(host, app, opts)
Sysd.Deploy.restart(host, app, opts)
Sysd.Deploy.logs(host, app, opts)
Sysd.Deploy.remove(host, app, opts)
Sysd.Deploy.cleanup(host, app, opts)

Sysd.TarballRef.parse("gh://owner/repo@v0.2.1")
Sysd.Config.load(path_or_discover)
```

Returns are `{:ok, result}` / `{:error, reason}` tuples.

**Hard rule**: no `IO.puts` or `System.halt` in `Sysd.Deploy.*`.
Output and process lifecycle belong to the caller.

## Configuration

### Precedence (highest wins)

1. **CLI flags** — `--config /path/to/config.yml`
2. **Environment variable** — `SYSD_CONFIG_FILE=/path/to/config.yml`
3. **Project-local `sysd.yml`** — discovered by walking up from cwd
4. **User-level** — `~/.config/sysd/config.yml` (XDG)

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

Include an `X-Creator=sysd` marker comment so `sysd` can identify
its own services on a host.

No separate `.service` file ships on disk. The template lives in code.

## Implementation Path

1. Refactor deploy internals into `Sysd.Deploy.*` with the
   no-IO/no-halt rule. Existing Mix tasks become thin wrappers.
2. Add `mix escript.build` target.
3. Implement config loading with the precedence chain.
4. Publish the escript as a GitHub release asset.
5. Document `Mix.install` as a supported usage mode.
