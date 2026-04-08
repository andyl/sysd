# Global CLI & Executable Split Design

Once release tarballs can be published to GitHub (and later S3, etc.),
the deploy side of relman no longer needs the project source tree.
This opens the door to shipping the deploy/manage side as a
**global, standalone executable** independent of any Elixir project.
This document captures the direction.

## Motivation

Relman today ships as a Mix dependency. Every `mix relman.*` command
requires running from inside a project checkout that lists `:relman`
in `mix.exs`. That made sense when the only way to get a tarball was
to build it locally, but it no longer does:

- `mix relman.deploy --from-release` can fetch a published tarball
  from GitHub without ever touching the source.
- The inputs to a deploy are tiny: a tarball reference, a host, a
  service name, some ssh details. None of that needs `mix.exs`.
- Operators often deploy from laptops, ops boxes, or CI runners
  that don't have — and shouldn't need — the application source.

Forcing a project checkout just to SSH a file onto a server is
artificial coupling. The `sup` script demonstrates the opposite
extreme: a single self-contained Elixir script with zero project
awareness, used successfully in production.

Relman should sit between these two points.

## The Natural Seam

Relman's operations fall into two groups with different requirements:

**Build / publish side — belongs in the project**

- Reads `@version` from `mix.exs`
- Runs `mix assets.deploy` and `MIX_ENV=prod mix release`
- Uses `git_ops` against the project repo
- Uploads tarballs via configured publishers
- Inherently tied to a specific project's source tree

**Deploy / manage side — belongs as a global tool**

- Inputs: tarball reference + host + service name + ssh details
- No project source needed
- Same behavior regardless of which project is being deployed
- Useful from any machine that can SSH the target

This is the seam. The build side stays where it is; the deploy side
lifts out.

## Proposed Split

Two deliverables, one repo:

### 1. `mix relman.*` — project-side Mix tasks

Unchanged in purpose from today. Stays a Mix dep in the consumer
project. Responsible for:

- `mix relman.release` — build + optionally publish tarball
- `mix relman.publish` — publish an already-built tarball (if we
  decide to expose this separately)

These tasks inherently live inside a project. Making them global
buys nothing.

### 2. `relman` — global escript

A standalone executable installed once per machine, usable from
anywhere. Responsible for everything that operates on a *deployed*
application:

- `relman check <host>` — host is deploy-ready (ssh, sudo, systemd)
- `relman deploy <host> <tarball-ref>` — install a release
- `relman versions <host> <app>` — list installed versions
- `relman rollback <host> <app> [<version>]` — flip symlink back
- `relman status <host> <app>` — `systemctl status`
- `relman start|stop|restart <host> <app>`
- `relman logs <host> <app>` / `relman tail <host> <app>`
- `relman remove <host> <app>` — uninstall
- `relman cleanup <host> <app>` — prune old archives

The `<tarball-ref>` is a small scheme for pointing at an artifact:

- `file:///path/to/app-0.2.1.tar.gz`
- `gh://owner/repo@v0.2.1` — fetches via `gh release download`
- `s3://bucket/key/app-0.2.1.tar.gz` — future
- `./app-0.2.1.tar.gz` — bare path, treated as `file:`

The same publisher contract from the publish design (`fetch/4`) can
be reused here: `relman deploy` resolves a tarball ref by delegating
to the matching publisher implementation.

### Naming note: relman vs. sup

The global `relman` CLI will overlap with `sup`. The intended
distinction:

- **sup** — general "run this command as a systemd service" tool.
  One unit, one command, no concept of versions or archives.
- **relman** — Elixir-release-aware. Knows about `archives/`,
  `releases/`, the `current` symlink, version rotation, rollback,
  `RELEASE_INFO`.

If that distinction ever feels thin in practice, merging is easy.
Splitting a merged tool later is harder. Start separate.

## Why Escript (Not Archive, Not Mix.install Script)

Three realistic packaging options exist for the global side:

| Form                 | Install               | Invocation              | Downsides                                                                        |
|----------------------|-----------------------|-------------------------|----------------------------------------------------------------------------------|
| Mix archive          | `mix archive.install` | `mix relman.deploy ...` | Still feels project-scoped; mix ceremony on every call                           |
| `Mix.install` script | copy file to PATH     | `relman ...`            | Slow cold start; needs `elixir` in PATH; harder to distribute as a release asset |
| **Escript**          | download binary       | `relman ...`            | Needs Erlang runtime (acceptable — target audience has it)                       |

Escript wins:

- Ships as a single file — publishable as a GitHub release asset
  from relman's own build pipeline. (First customer of the new
  publish feature. Very satisfying.)
- Proper `relman` command, not `mix relman.foo`. Feels like a real
  CLI, not a project task masquerading as one.
- Fast startup. No Mix boot.
- Distributable: `curl` the escript off a GitHub release, `chmod +x`,
  put it on `$PATH`. Done.

The Erlang runtime dependency is a non-issue for this audience:
anyone deploying Elixir releases already has Erlang installed.

## CLI Shape

Model on `sup`. Use `Optimus` for parsing. Subcommand structure,
`help <cmd>` for per-command help, sensible defaults, everything
overridable via flags.

Example:

```
relman deploy host1.lan gh://andyl/myapp@v0.2.1 --app myapp --user deploy
relman versions host1.lan myapp
relman rollback host1.lan myapp v0.2.0
relman tail host1.lan myapp
```

Every command should be usable with pure CLI args and no config
file, like `sup`. Config is a convenience layer on top.

## Config Discovery

Three-level precedence, highest wins:

1. **CLI flags** — always override
2. **Project-local `relman.yaml`** — discovered by walking up from
   cwd, same as how git finds `.git`. This is the primary source
   when deploying a known project from its checkout.
3. **User-level `~/.config/relman/config.yaml`** — optional defaults
   (ssh user, default github org, default publisher, etc.)

If none of these exist and required values aren't passed as flags,
fail with a clear message naming the missing input.

The project-local file is the same `relman.yaml` consumed by the
Mix-task side. One config, two consumers — the global CLI reads
the subset relevant to deploy/manage operations (`servers`, `ssh`,
`app`, `release.publish` for fetch-resolution), the Mix tasks read
the build/publish subset. They don't conflict.

A project-local `relman.yaml` should let you skip most flags:

```
cd ~/src/myapp
relman deploy host1.lan gh://andyl/myapp@v0.2.1
# picks up app name, ssh user, servers list from ./relman.yaml
```

## Systemd Service Template

Embed the template inside the escript as a module attribute, the
same way `sup` does with `service_content/3`. Parameterized via
config keys:

- `app` — service name
- `user` — `User=`
- `working_dir` — `WorkingDirectory=`
- `exec_start` — command that launches the release
- `environment` — list of `Environment=KEY=value` lines
- `restart`, `restart_sec` — with sensible defaults

Include an `X-Creator=relman` marker comment in the unit file so
`relman list` can filter out non-relman services (again, copying
the `@marker` pattern from sup). Without this marker, we can't
safely answer "what did relman install on this host?"

**No separate sample `.service` file ships on disk.** It's one more
thing to install, locate, and keep in sync with the code that renders
it. The template lives in the escript. Full stop.

For the rare case that needs full override, allow
`service_template: path/to/file.eex` in `relman.yaml` — but don't
build that escape hatch until someone actually asks for it.

## Bootstrapping the Escript

The relman repo itself builds and publishes the escript:

1. `mix relman.release` builds the escript (via `mix escript.build`
   as part of the release step, or as a dedicated
   `mix relman.escript` task).
2. The resulting `relman` binary is attached to the GitHub release
   for the version tag.
3. Users install via:

    ```
    curl -L https://github.com/andyl/relman/releases/download/v0.3.0/relman -o ~/.local/bin/relman
    chmod +x ~/.local/bin/relman
    ```

   A future `relman self-update` subcommand can automate this by
   checking the latest GitHub release and replacing the binary in
   place.

This means relman's *own* release process is the first real user
of the publish feature. Good dogfooding.

## Migration Path

The split doesn't need to happen in one step:

1. **Land the publish design first** (already designed).
2. **Add `mix escript.build` target** to relman. At this point the
   escript exists but only duplicates a subset of the Mix tasks.
3. **Move deploy/manage logic into shared modules** that both the
   Mix tasks and the escript call. No behavior change.
4. **Publish the escript** as an asset on the next relman release.
5. **Deprecate the deploy/manage Mix tasks** in favor of the global
   CLI. Keep them working for a release or two, then remove.
6. **Mix tasks narrow to build/publish only.**

At no point is the user forced to switch. The escript is additive
until the Mix-task side is deliberately trimmed.

## Open Questions

- **Escript + `gh` CLI**: the github publisher currently shells out
  to `gh`. That works fine from the escript too. Confirm `gh` is
  an acceptable runtime dep for the deploy side (likely yes — an
  operator fetching a tarball from GH probably has `gh`).
- **`relman self-update`**: worth building, or leave it to users?
  Lean toward "build it, it's ~30 lines."
- **Config schema versioning**: if both the Mix-task side and the
  escript read `relman.yaml`, we should define the schema once and
  share the loader module between them.
- **Host identity**: does `relman` need any concept of "host
  groups" / "environments" (staging vs prod), or is a flat
  `servers:` list in config enough? Current design says flat list;
  reconsider if it gets painful.
- **Secret handling**: the escript will sometimes need to push
  `Environment=` values containing secrets into a systemd unit
  file. How those get supplied — env vars, a sidecar secrets file,
  `pass`, `op read`, etc. — is deliberately out of scope here but
  worth a follow-up design.

## Out of Scope

- Replacing `sup`. Relman and sup stay separate tools.
- Non-Elixir release support. Relman is Elixir-release-specific by
  design; if you need "run an arbitrary command as a service," use
  sup.
- GUI / TUI. CLI only.
- Multi-host orchestration beyond a simple for-each loop over
  `servers:`. No parallel rollouts, canaries, or health-gated
  promotion in v1.

## Addendum: Library API as the Source of Truth

A constraint surfaced after the initial draft: relman should remain
consumable from **custom Elixir scripts** that use `Mix.install`, so
that users can write bespoke deploy workflows (multi-stage rollouts,
pre/post hooks, cross-service coordination, environment-specific
glue) without being boxed into whatever the CLI exposes.

An escript is a compiled, sealed artifact — it cannot be called from
a `Mix.install` script the way a library can. So if the deploy logic
*only* lives inside the escript, the scripting use case is dead.

The fix is architectural, not packaging: **the escript must be a
thin wrapper around a public library API**, not the home of the
logic. All three consumers then share the same code path.

### Three Consumers, One Library

```
          ┌─────────────────────────────────────┐
          │      Relman.Deploy (library)        │
          │  deploy/3, versions/2, rollback/3,  │
          │  status/2, logs/2, remove/2, ...    │
          └──────────────────┬──────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
  ┌───────────┐        ┌───────────┐       ┌──────────────┐
  │ Mix tasks │        │  escript  │       │ Mix.install  │
  │ (project) │        │  (global) │       │   scripts    │
  └───────────┘        └───────────┘       └──────────────┘
```

The escript's `main/1` does argv parsing → validation → calls into
`Relman.Deploy.*` → formats output. Nothing load-bearing lives in
the escript itself. Same for the Mix tasks: they're translation
layers from `mix` invocation to library calls.

### Public API Shape

A rough sketch of the surface the library must expose. Names are
illustrative; the point is that every CLI subcommand maps to a
library function that a `Mix.install` script could call directly:

```elixir
Relman.Deploy.check(host, opts)
Relman.Deploy.deploy(host, tarball_ref, opts)
Relman.Deploy.versions(host, app, opts)
Relman.Deploy.rollback(host, app, version, opts)
Relman.Deploy.status(host, app, opts)
Relman.Deploy.start(host, app, opts)
Relman.Deploy.stop(host, app, opts)
Relman.Deploy.restart(host, app, opts)
Relman.Deploy.logs(host, app, opts)   # stream
Relman.Deploy.remove(host, app, opts)
Relman.Deploy.cleanup(host, app, opts)

Relman.TarballRef.parse("gh://owner/repo@v0.2.1")
Relman.Config.load(path_or_discover)
```

`opts` is a plain keyword list. Returns are `{:ok, result}` /
`{:error, reason}` tuples — no `System.halt` inside the library.
The escript translates errors into exit codes; a `Mix.install`
script can match on them and decide what to do.

**Design rule**: no `IO.puts` or `System.halt` in `Relman.Deploy.*`.
User-facing output and process lifecycle belong to the caller (the
escript, the Mix task, or the user's script). The library emits
structured results, optionally with a logger/telemetry hook for
progress events, and lets the caller decide how to present them.

This is the single most important rule in the library/CLI split.
Violating it is what turns "library with a CLI wrapper" into
"CLI with library pretensions."

### `Mix.install` Consumer Example

What a user's custom deploy script should look like:

```elixir
#!/usr/bin/env elixir

Mix.install([
  {:relman, "~> 0.3"}
])

alias Relman.Deploy

hosts = ["host1.lan", "host2.lan", "host3.lan"]
ref = Relman.TarballRef.parse!("gh://andyl/myapp@v0.3.0")

# Canary first
[canary | rest] = hosts
{:ok, _} = Deploy.deploy(canary, ref, app: "myapp")
:timer.sleep(30_000)
{:ok, status} = Deploy.status(canary, "myapp")
unless String.contains?(status.output, "active (running)") do
  IO.puts(:stderr, "Canary failed, aborting")
  System.halt(1)
end

# Then the rest
for host <- rest do
  {:ok, _} = Deploy.deploy(host, ref, app: "myapp")
end
```

Nothing about that example requires relman's CLI to exist. It only
requires the library API. Meanwhile, the exact same functions power
`relman deploy host1.lan gh://andyl/myapp@v0.3.0` from the shell.

### Implications for the Migration Path

The migration steps from the main design update slightly:

1. Publish design lands (unchanged).
2. **Refactor deploy/manage internals into `Relman.Deploy.*`
   with the no-`IO`/no-`halt` rule.** Existing Mix tasks become
   thin wrappers. This is the load-bearing step — do it first,
   before touching packaging.
3. Add `mix escript.build` that produces a `relman` escript which
   is *also* a thin wrapper over `Relman.Deploy.*`.
4. Publish the escript as a GH release asset.
5. Document `Mix.install({:relman, ...})` as a supported usage
   mode for custom deploy scripts, with an example script in
   the repo (`examples/custom_deploy.exs` or similar).
6. Deprecate the deploy/manage Mix tasks in favor of (a) the
   escript for ad-hoc use and (b) `Mix.install` scripts for
   programmatic use.

Step 2 is where all the value is created. Steps 3–6 are packaging.

### Does This Change the Escript Decision?

No. Escript is still the right packaging for the global CLI —
library consumers go through `Mix.install`, not through the
escript. The two delivery modes are complementary:

| Use case                              | Delivery                  |
|---------------------------------------|---------------------------|
| Ad-hoc ops from a shell               | Escript: `relman ...`     |
| Custom programmatic deploy workflow   | `Mix.install({:relman})`  |
| Mix-task-style project integration    | Mix dep (build/publish)   |

The common substrate under all three is `Relman.Deploy.*`. Get that
layer right and the packaging choices stop mattering much — you can
add, change, or drop any of the three wrappers without rewriting
the engine.
