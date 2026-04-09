# Implementation Plan: Escript CLI

**Spec:** `_spec/features/260409_escript-cli.md`
**Generated:** 2026-04-09

---

## Goal

Ship a standalone `sysd` escript binary and refactor all deploy logic into a shared `Sysd.Deploy.*` library layer with a strict no-IO/no-halt rule, so the escript, Mix tasks, and Mix.install scripts are thin wrappers over the same core.

## Scope

### In scope
- Library refactor: extract `Sysd.Deploy.*` modules from existing `Sysd.Remote` + Mix task logic
- `Sysd.TarballRef` module for parsing tarball reference schemes (`file://`, `gh://`, bare paths; `s3://` stub)
- `Sysd.Config.load/1` with four-level precedence chain (CLI flag, env var, project-local walk-up, XDG)
- Systemd template as a module attribute with `X-Creator=sysd` marker
- Escript entry point using Optimus for subcommand parsing
- `mix escript.build` configuration in `mix.exs`
- Refactor existing Mix tasks to delegate to `Sysd.Deploy.*`
- Tests for new library modules

### Out of scope
- `s3://` tarball scheme implementation (placeholder error only)
- Interactive prompts or TUI elements
- Daemon mode or self-update mechanism
- Changes to publisher logic (`Sysd.Publisher.*`)
- GitHub release automation for the escript binary

## Architecture & Design Decisions

1. **Library-first refactor.** All operations move to `Sysd.Deploy` (facade) backed by focused sub-modules. The existing `Sysd.Remote` module stays as the SSH command layer; `Sysd.Deploy.*` composes Remote + Config + TarballRef into high-level operations returning `{:ok, result} | {:error, reason}` tuples.

2. **No IO/halt rule.** `Sysd.Deploy.*` modules must never call `IO.puts`, `Mix.shell()`, `System.halt`, or `Mix.raise`. Errors are returned as `{:error, reason}` tuples. The callers (escript CLI, Mix tasks) handle output and exit codes.

3. **`Sysd.SSH.run!` currently raises `Mix.Error`.** This needs to change: the bang functions in SSH should raise a generic `Sysd.SSH.Error` (or return error tuples used by Deploy), since `Mix.raise` is not available in escript context. Mix tasks can catch and re-raise as `Mix.Error`.

4. **Optimus for CLI parsing.** Optimus provides subcommand support, help text generation, and argument/flag validation out of the box. Each subcommand maps 1:1 to a `Sysd.Deploy` function.

5. **Config precedence chain.** `Sysd.Config.load/1` accepts an optional explicit path (from `--config` flag). When nil, it checks `RELDEP_CONFIG` env var, then walks up from cwd looking for `sysd.yml`, then falls back to `~/.config/sysd/config.yml`. The existing `Sysd.Config.load/0` (hardcoded `config/sysd.yaml`) is preserved for backward compat in Mix tasks but delegates to the new logic.

6. **Tarball ref parsing.** `Sysd.TarballRef.parse/1` returns a tagged struct: `%TarballRef{scheme: :file | :github | :s3, ...}`. A `resolve/2` function materializes the ref to a local file path (downloading if needed). `s3://` returns `{:error, :not_implemented}`.

7. **Systemd template.** Embedded as a module attribute in `Sysd.Systemd`, using EEx compilation. Parameterized by a map of keys. Includes `# X-Creator=sysd` marker comment.

## Implementation Steps

1. **Add `optimus` dependency**
   - Files: `mix.exs`
   - Add `{:optimus, "~> 0.5"}` to deps (all envs, since escript needs it at runtime)

2. **Create `Sysd.SSH.Error` and refactor SSH error handling**
   - Files: `lib/sysd/ssh.ex`
   - Define `defexception` for `Sysd.SSH.Error`
   - Change `SSH.run!/2` to raise `Sysd.SSH.Error` instead of `Mix.raise`
   - Change `SSH.upload/3` to return `{:ok, :uploaded} | {:error, reason}` instead of calling `IO.puts`

3. **Create `Sysd.TarballRef` module**
   - Files: `lib/sysd/tarball_ref.ex`
   - Struct: `%TarballRef{scheme: atom, path: String.t(), owner: String.t(), repo: String.t(), tag: String.t()}`
   - `parse/1` — pattern-match on scheme prefixes, return `{:ok, ref}` or `{:error, reason}`
   - `resolve/2` — given a ref and a destination dir, return `{:ok, local_path}` or `{:error, reason}`
   - `file://` and bare paths: validate file exists, return path
   - `gh://` : shell out to `gh release download`
   - `s3://` : return `{:error, {:not_implemented, "s3:// scheme"}}`

4. **Refactor config loading with precedence chain**
   - Files: `lib/sysd/config.ex`
   - Add `load/1` that accepts `opts` keyword list with optional `:config_path`
   - Implement precedence: explicit path → `RELDEP_CONFIG` env → walk-up discovery of `sysd.yml` → XDG `~/.config/sysd/config.yml`
   - Keep existing `load/0` working by delegating to `load/1` with empty opts
   - Parse the new config shape (multi-app `apps:` key) alongside the existing single-app shape for backward compat

5. **Create `Sysd.Systemd` module**
   - Files: `lib/sysd/systemd.ex`
   - Module attribute `@service_template` with EEx template string including `# X-Creator=sysd`
   - `render/1` — accepts a map of params (`app`, `user`, `working_dir`, `exec_start`, `environment`, `restart`, `restart_sec`), returns rendered service file string

6. **Create `Sysd.Deploy` facade module**
   - Files: `lib/sysd/deploy.ex`
   - Public functions: `check/2`, `deploy/3`, `versions/2`, `rollback/3`, `status/2`, `start/2`, `stop/2`, `restart/2`, `logs/2`, `tail/2`, `remove/2`, `cleanup/2`
   - Each takes `(host, opts)` or `(host, app, opts)` and returns `{:ok, result}` / `{:error, reason}`
   - Composes `Sysd.SSH`, `Sysd.Remote`, `Sysd.Config`, `Sysd.TarballRef`
   - `deploy/3` signature: `deploy(host, tarball_ref_string, opts)` — parses ref, resolves to local path, then delegates to Remote
   - `opts` includes `:app`, `:user`, `:config` (pre-loaded config struct or nil)
   - Add missing Remote operations: `status`, `start`, `stop`, `restart`, `logs`, `tail` (these are new SSH commands against systemd/journalctl)

7. **Add missing remote operations to `Sysd.Remote`**
   - Files: `lib/sysd/remote.ex`
   - `status/2` — `systemctl is-active <app>`
   - `start/2`, `stop/2`, `restart/2` — `systemctl start|stop|restart <app>`
   - `logs/2` — `journalctl -u <app> -n 50 --no-pager`
   - `tail/2` — `journalctl -u <app> -f` (streaming; return the command string or handle via SSH exec)

8. **Refactor existing Mix tasks to use `Sysd.Deploy`**
   - Files: `lib/mix/tasks/sysd.deploy.ex`, `sysd.sshcheck.ex`, `sysd.versions.ex`, `sysd.rollback.ex`, `sysd.remove.ex`, `sysd.cleanup.ex`, `sysd.setup.ex`
   - Each task becomes: parse args → call `Sysd.Deploy.<function>` → pattern-match result → print output or raise
   - This validates the library API before building the escript

9. **Create escript entry point with Optimus**
   - Files: `lib/sysd/cli.ex`
   - `main/1` — parse argv with Optimus, dispatch to `Sysd.Deploy.*`, format output, set exit code
   - Define all subcommands with their arguments and flags
   - Handle `--config` global flag for config path override

10. **Configure `mix escript.build` in mix.exs**
    - Files: `mix.exs`
    - Add `escript: [main_module: Sysd.CLI, name: "sysd"]` to project config
    - Ensure `:yaml_elixir` and `:sshex` are included in the escript

11. **Write tests for new modules**
    - Files: `test/sysd/tarball_ref_test.exs`, `test/sysd/deploy_test.exs`, `test/sysd/systemd_test.exs`, `test/sysd/config_test.exs` (extend)
    - `TarballRef.parse/1` — test all scheme variants and error cases
    - `Systemd.render/1` — test template output includes marker and correct params
    - `Deploy.*` — test with mocked SSH (these are unit tests for the orchestration layer)
    - `Config.load/1` — test precedence chain with temp files and env vars

12. **Verify escript builds and runs**
    - Run `mix escript.build` and test `./sysd --help`, `./sysd deploy --help`, etc.
    - Verify subcommands dispatch correctly

## Dependencies & Ordering

- **Step 1** (add optimus dep) must come first since later steps depend on it
- **Step 2** (SSH error refactor) must precede Step 6 (Deploy facade) since Deploy relies on non-Mix error handling
- **Step 3** (TarballRef) and **Step 4** (Config) and **Step 5** (Systemd) are independent of each other, can be done in parallel
- **Step 6** (Deploy facade) depends on Steps 2–5
- **Step 7** (new Remote operations) can happen in parallel with Steps 3–5, but must precede Step 6
- **Step 8** (Mix task refactor) depends on Step 6
- **Step 9** (CLI entry point) depends on Steps 1, 6
- **Step 10** (escript config) depends on Step 9
- **Step 11** (tests) should be written alongside each step, listed last for clarity
- **Step 12** (verification) is the final step

## Edge Cases & Risks

- **`Mix.raise` in escript context**: Mix is not available when running as escript. All library code must avoid Mix-specific functions. The SSH module currently uses `Mix.raise` — Step 2 fixes this.
- **`Sysd.app_name/0` and `Sysd.version/0` call `Mix.Project.config`**: These won't work in escript mode. The escript must get app name from CLI args or config, not from Mix. The Deploy facade should accept app/version as explicit params.
- **Streaming tail**: `journalctl -f` is a long-running command. SSHEx may not support streaming well. May need to use raw Erlang `:ssh_connection.exec` with async message handling. Could be deferred or simplified to a timed tail.
- **Config backward compatibility**: Existing projects use `config/sysd.yaml` with a flat structure. The new multi-app config shape (`apps:` key) is different. Config parsing must handle both formats.
- **`gh` CLI dependency**: The `gh://` scheme requires the `gh` CLI to be installed. `TarballRef.resolve/2` should return a clear error if `gh` is not on PATH.
- **Escript size**: Including `:sshex` and Erlang SSH in the escript may result in a large binary. Monitor and document the expected size.

## Testing Strategy

- **Unit tests** for `TarballRef.parse/1` — pure parsing, no side effects
- **Unit tests** for `Systemd.render/1` — template rendering
- **Unit tests** for `Config.load/1` precedence — use temp dirs and `System.put_env`
- **Integration-style tests** for `Sysd.Deploy.*` — mock SSH at the `Sysd.SSH` boundary using a behaviour + test double
- **Escript smoke test** — `mix escript.build && ./sysd --help` returns 0 with expected output
- **Mix task regression** — existing Mix task tests still pass after refactor

## Open Questions

- [x] Should the escript embed the Erlang `:ssh` application, or require it on the host? (Likely must embed since escript runs on bare Erlang runtime)  Answer: embed erlang ssh
- [x] What is the exact Optimus version constraint? Need to verify compatibility with OTP/Elixir versions in use.  Answer: use a most-recent version, one that works
- [x] Should `tail` be included in v1 of the escript given the streaming complexity, or deferred?  Answer: includ tail in V1
- [x] Does the new multi-app config shape (`apps:` key) replace the existing flat shape, or do both coexist permanently?  Answer: replace
- [x] Should the escript be published as a GitHub release asset as part of this feature, or is that a separate task?  Answer: separate task 
