# Implementation Plan: Release Publish Tasks

**Spec:** `_spec/features/260407_release-publish-tasks.md`
**Design:** `_spec/designs/260407_ReleasePublishDesign.md`
**Generated:** 2026-04-07

---

## Goal

Split `mix sysd.deploy` into `mix sysd.release` (build + publish) and
`mix sysd.deploy` (push existing tarball to servers), and introduce a
pluggable publisher system with two initial implementations: `github`
(via the `gh` CLI) and `file` (filesystem copy).

## Scope

### In scope
- New `mix sysd.release` task (build + optional publish).
- Rework of `mix sysd.deploy` to consume an existing tarball, or
  invoke `mix sysd.release` / fetch from a publisher when absent.
- Publisher contract (behaviour) + dispatcher module.
- `Sysd.Publisher.Github` and `Sysd.Publisher.File` implementations.
- Preflight checks that run before any build work.
- `config/sysd.yaml` schema extension: `release.publish` list, parsed
  into the `%Sysd.Config{}` struct.
- `RELEASE_INFO` file written into each server release dir after deploy.
- `--force`, `--replace`, `--no-publish`, `--from-release` flags.
- Idempotency: tarball existence check, publisher "already exists" check.
- Updates to existing tests, plus new tests for config parsing, publisher
  modules, and task argument parsing.
- README / moduledoc / `mix sysd` help output updates.

### Out of scope
- Publisher types other than `github` and `file` (the behaviour shape
  must leave room for them, but nothing more).
- Git tag creation (stays with `git_ops`).
- Release notes sourcing — auto-title + empty body.
- Signing / checksums.
- Changes to the server-side deploy workflow (upload, extract, symlink,
  restart) beyond the new `RELEASE_INFO` write.
- Zero-downtime deploys.

## Architecture & Design Decisions

1. **Publisher as an Elixir behaviour.** Define `Sysd.Publisher` with
   three callbacks: `preflight/1`, `publish/4`, `fetch/4`. Each publisher
   module implements it. Task code iterates over publisher specs and
   dispatches via a small `Sysd.Publisher.resolve/1` helper mapping
   `type: "github"` → `Sysd.Publisher.Github`, etc. This matches the
   spec's "keep task code free of per-publisher branching" requirement
   and is the idiomatic Elixir pattern.

2. **Preflight before build.** `sysd.release` runs *all* publisher
   preflights up front, before touching `mix assets.deploy` or
   `mix release`. An aggregated failure means no build work at all.
   This matches the "fail fast on misconfig" goal.

3. **Config struct extension.** Add `release: %{publish: [...]}` to
   `%Sysd.Config{}`. Parsed publishers are normalized to plain maps
   with atom keys (`%{type: :github, draft: false, prerelease: false}`,
   `%{type: :file, path: "/mnt/..."}`) so downstream code can pattern
   match on `:type`. The `write/1` function is **not** updated to
   round-trip publishers — `sysd.init` stays minimal and users edit
   `sysd.yaml` by hand to add a `release.publish` block (the existing
   `write/1` only ever rewrites the small set of fields it manages,
   e.g. `remove_server`). Document this limitation.

4. **Shared helpers on `Sysd`.**
   - `Sysd.git_sha/0` — reads `git rev-parse HEAD`.
   - `Sysd.git_tag_exists?/1` — `git rev-parse -q --verify refs/tags/<tag>`.
   - `Sysd.build_host/0` — `:inet.gethostname/0`.
   - `Sysd.version_tag/0` — `"v#{version()}"`.
   - `Sysd.tarball_basename/0` — `"#{app}-#{version}.tar.gz"`.
   These centralize small bits the tasks and publishers share.

5. **`sysd.deploy` default path.** When the local tarball is absent
   and `--from-release` is *not* passed, the task calls
   `Mix.Task.run("sysd.release", [])` (build only — publishing will
   still run per config, which matches the spec's "invoke sysd.release"
   wording). If the user wants to deploy *without* publishing, the
   documented path is `mix sysd.release --no-publish && mix sysd.deploy`.

6. **`RELEASE_INFO` format.** Plain key=value text file, one field per
   line, no YAML/JSON dependency for a tiny debug artifact:
   ```
   app=myapp
   version=0.3.0
   git_sha=abc123...
   build_host=laptop.local
   build_timestamp=2026-04-07T12:34:56Z
   publisher_url=  # blank unless fetched from a publisher
   ```
   Written by uploading a local temp file through `Sysd.SSH.upload/3`,
   then `sudo mv` into the release dir — mirroring the pattern used for
   the systemd service file in `Sysd.Remote.install_service/3`.

7. **GitHub publisher uses `System.cmd("gh", ...)`.** No HTTP client
   dependency. Streams output to `Mix.shell().info/1`. Relies on
   `gh` exit code for success/failure detection.

8. **File publisher existence check for fetch.** For the fetch path,
   the file publisher acts as a fallback source when the local tarball
   is missing. `sysd.deploy --from-release` walks publishers in config
   order and uses the first that returns a non-error from
   `fetch_supported?/1` (both shipped publishers return `true`).

9. **Tarball location.** `Sysd.release_tar_path/0` already exists and
   points at `_build/prod/rel/.../<app>-<version>.tar.gz`. Publishers'
   fetch writes into this same location so the normal deploy flow picks
   it up without any glue code.

## Implementation Steps

1. **Extend `Sysd.Config` to parse `release.publish`.**
   - Files: `lib/sysd/config.ex`, `test/sysd/config_test.exs`
   - Add `release: %{publish: []}` to the struct default.
   - In `load/0`, parse `data["release"]["publish"]` into a list of
     normalized maps: `%{type: :github, draft: bool, prerelease: bool}`
     and `%{type: :file, path: String.t()}`. Unknown types raise.
   - `write/1` keeps current responsibilities; add a comment noting
     publishers are not round-tripped.
   - Tests: empty/missing `release` → `[]`; github-only; file-only;
     mixed; unknown `type` raises.

2. **Add `Sysd` helper functions.**
   - Files: `lib/sysd.ex`, `test/sysd_test.exs`
   - Add `version_tag/0`, `tarball_basename/0`, `git_sha/0`,
     `git_tag_exists?/1`, `build_host/0`.
   - `git_sha/0` and `git_tag_exists?/1` wrap `System.cmd/3`.
   - Tests: pure helpers (`version_tag`, `tarball_basename`) asserted
     directly; git-calling helpers tested only by return-type shape to
     avoid depending on repo state.

3. **Define the `Sysd.Publisher` behaviour.**
   - Files: `lib/sysd/publisher.ex` (new)
   - Callbacks:
     - `@callback preflight(spec :: map()) :: :ok | {:error, String.t()}`
     - `@callback publish(spec :: map(), tar :: Path.t(), app :: atom(), version :: String.t()) :: {:ok, String.t() | nil} | {:error, String.t()}` — `{:ok, url}` where `url` is the publisher URL if one exists.
     - `@callback fetch(spec :: map(), app :: atom(), version :: String.t(), dest :: Path.t()) :: {:ok, String.t() | nil} | {:error, String.t()}`
   - Module helpers:
     - `resolve(spec)` → returns the implementation module for a spec map.
     - `preflight_all(specs)` → runs every publisher's preflight, collects errors, returns `:ok | {:error, [reason]}`.
     - `publish_all(specs, tar, app, version, opts)` → runs each publisher in order. Honors `:replace` option.
     - `fetch_first(specs, app, version, dest)` → walks specs, returns first `{:ok, url}`.

4. **Implement `Sysd.Publisher.File`.**
   - Files: `lib/sysd/publisher/file.ex` (new), `test/sysd/publisher/file_test.exs` (new)
   - `preflight/1`: assert `:path` set, absolute, exists, writable.
     If `<path>/<app>-<version>.tar.gz` exists, require `opts[:replace]`.
     (Pass `replace` via the spec map mutated by the task layer, or
     accept a second arg — see design note in step 3.)
   - `publish/4`: `File.cp!/2` the tarball in. Return `{:ok, nil}` (no URL).
   - `fetch/4`: reverse copy, or `{:error, :not_found}`.
   - Tests: use `@tag :tmp_dir` (ExUnit built-in) for the target path;
     cover preflight happy path, non-absolute path, missing dir,
     existing file with and without replace, publish + fetch round-trip.

5. **Implement `Sysd.Publisher.Github`.**
   - Files: `lib/sysd/publisher/github.ex` (new), `test/sysd/publisher/github_test.exs` (new)
   - Private helpers:
     - `gh_installed?/0` — `System.find_executable("gh")`.
     - `gh_authed?/0` — `System.cmd("gh", ["auth", "status"])` exit 0.
     - `origin_repo/0` — parse `git remote get-url origin` into
       `owner/repo` for both `https://github.com/O/R(.git)?` and
       `git@github.com:O/R(.git)?`.
     - `release_exists?(tag)` — `gh release view <tag>` exit 0.
   - `preflight/1`: run all five checks from the spec; return the
     first failure as `{:error, human_reason}`.
   - `publish/4`: `gh release create <tag> <tar> --title "<app> v<ver>"
     [--draft] [--prerelease]`. On success return
     `{:ok, "https://github.com/<owner>/<repo>/releases/tag/<tag>"}`.
     When `opts[:replace]`: `gh release delete <tag> --yes` first,
     swallowing "not found".
   - `fetch/4`: `gh release download <tag> --pattern '<tar>' --dir <dest dir>`.
   - Tests: focus on pure helpers — origin URL parsing (both forms,
     with and without `.git`), and argv construction. Calls into `gh`
     itself are not exercised in unit tests; leave those to manual
     verification (noted in Testing Strategy). Extract argv builders
     into private functions that tests can reach via
     `@moduledoc false` + small public testing shims, or via module
     attributes.

6. **Write `mix sysd.release`.**
   - Files: `lib/mix/tasks/sysd.release.ex` (new), `test/mix/tasks/sysd_release_test.exs` (new)
   - Argv parsing with `OptionParser`: `--force`, `--replace`,
     `--no-publish` (all boolean).
   - Flow:
     1. Load config, app, version.
     2. `Sysd.git_tag_exists?(version_tag)` — raise if not.
     3. If `--no-publish` is false, run `Publisher.preflight_all(specs)` —
        raise on any failure *before* building.
     4. If the local tarball exists and not `--force`, skip build.
        Otherwise `Mix.Task.run("assets.deploy", [])` then
        `Mix.Task.run("release", [])`. Ensure `MIX_ENV=prod`; either
        re-run under the right env or document as a precondition —
        the existing `deploy` task does not set it, so match current
        behavior (document, don't set).
     5. Assert the tarball exists after build.
     6. If `--no-publish` is false, call
        `Publisher.publish_all(specs, tar, app, version, replace: replace?)`.
        Raise on error.
   - Tests: argv parsing, flag → option mapping. Full flow tested
     manually / via a stub publisher module in tests (see Testing
     Strategy).

7. **Rework `mix sysd.deploy`.**
   - Files: `lib/mix/tasks/sysd.deploy.ex`, `test/mix/tasks/sysd_deploy_test.exs` (new or extended)
   - Argv parsing: `--from-release` boolean.
   - Flow:
     1. Load config, app, version.
     2. Determine tarball presence.
     3. If missing and `--from-release`: call
        `Publisher.fetch_first(specs, app, version, dest_dir)`. Raise
        on failure; remember the publisher URL for `RELEASE_INFO`.
     4. If missing and not `--from-release`: `Mix.Task.run("sysd.release", [])`.
     5. For each server: existing deploy steps, then write
        `RELEASE_INFO` via `Remote.write_release_info/4`.
   - Update the `@moduledoc` to reflect the new behavior and flags.

8. **Add `Remote.write_release_info/4`.**
   - Files: `lib/sysd/remote.ex`, `test/sysd/...` (existing tests
     may not cover this module; skip if not)
   - Signature: `(conn, app_name, version, info_map) :: :ok`.
   - Builds the key=value body, uploads via `SSH.upload/3` to a tmp
     path, `sudo mv` into `<releases_path>/<version>/RELEASE_INFO`.
   - Called by `sysd.deploy` after `Remote.deploy/4`.

9. **Update `Mix.Tasks.Sysd` help text.**
   - Files: `lib/mix/tasks/sysd.ex`, `test/mix/tasks/sysd_test.exs`
   - Add `mix sysd.release` to the task list and flag summary. Update
     the existing test assertions to cover the new task name.

10. **Update docs.**
    - Files: `README.md`, `RELEASE.md` (if relevant), `CLAUDE.md`
      task list section.
    - Document the new tasks, flags, publisher config shape, and the
      `RELEASE_INFO` file. Add a minimal example `release.publish`
      block.

11. **Refresh `sysd.init` template (optional).**
    - Files: `lib/mix/tasks/sysd.init.ex`
    - Add a commented-out `release.publish` example block in the
      generated `config/sysd.yaml`, so users discover the feature.
      Only if `sysd.init` already writes a template; otherwise skip.

## Dependencies & Ordering

- Step 1 (config parsing) and step 2 (helpers) are prerequisites for
  everything else and can land together.
- Step 3 (behaviour) must precede steps 4 and 5.
- Steps 4 and 5 (publisher implementations) can proceed in parallel
  once 3 is in place.
- Step 6 (`sysd.release`) depends on 3, 4, 5.
- Step 7 (`sysd.deploy` rework) depends on 6 and on step 8
  (`RELEASE_INFO` writer).
- Steps 9–11 (docs/help) come last so they describe settled behavior.

## Edge Cases & Risks

- **Missing `@version` git tag.** Must raise early with a clear
  message pointing at `mix git_ops.release`.
- **`git` not on `$PATH`.** `git_sha/0` / `git_tag_exists?/1` should
  raise a descriptive error rather than an ErlangError.
- **`gh` exits 0 but prints to stderr.** Trust the exit code; log
  stderr for visibility.
- **Origin URL variants.** Handle `https://github.com/O/R`,
  `https://github.com/O/R.git`, `git@github.com:O/R`,
  `git@github.com:O/R.git`, and fail cleanly on non-GitHub origins.
- **Tarball exists but is truncated / stale.** Spec explicitly says
  presence is the only check — do not add mtime/hash logic. Document
  `--force` as the escape hatch.
- **Publisher order matters for fetch.** `fetch_first` must honor
  config order; document this.
- **Spec vs. callback arity.** Publisher `publish` / `fetch` need
  access to the `--replace` flag. Resolve by passing it as part of the
  spec map (task layer merges `Map.put(spec, :replace, true)`) so the
  behaviour stays at 4 args. Decide in step 3 and apply consistently.
- **`RELEASE_INFO` with shell metacharacters.** The values (git sha,
  hostname, timestamp, URL) are controlled, but quote defensively when
  building the heredoc.
- **File publisher path with trailing slash.** Normalize with
  `Path.expand/1` or strip trailing `/` before building the target.
- **Parallel publisher failures.** Run sequentially; collect all
  preflight errors but stop on the first publish error. Revisit if
  users complain.

## Testing Strategy

- **Unit-testable modules** — config parser, pure helpers on `Sysd`,
  file publisher (using `tmp_dir`), argv parsers for the new tasks,
  GitHub publisher's URL parsing and argv construction. Aim for high
  coverage here since these are the brittle bits.
- **Stubbed publisher for task tests.** Add a tiny `TestPublisher`
  module in `test/support/` that implements the behaviour and records
  calls in an Agent. Register it via an application env override so
  `Sysd.Publisher.resolve/1` can pick it up when a `type: :test`
  spec appears. Use it to drive end-to-end tests of `sysd.release`
  and `sysd.deploy` without touching `gh` or SSH.
- **SSH / server-side behavior** — continue to be exercised manually,
  matching current test coverage. Do not add SSH mocks in this PR.
- **Manual verification checklist** (to run before merging):
  1. `mix sysd.release` with no `release.publish` — builds only.
  2. `mix sysd.release` with `type: file` — copy lands in target dir.
  3. `mix sysd.release` with `type: github` against a scratch repo.
  4. `mix sysd.release --force` after a successful build.
  5. `mix sysd.release --replace` against an existing GH release.
  6. `mix sysd.deploy` with a pre-built tarball.
  7. `mix sysd.deploy` with no tarball (falls through to release).
  8. `git checkout <tag>` in a fresh worktree →
     `mix sysd.deploy --from-release` fetches from file publisher.
  9. Inspect `RELEASE_INFO` on the server.
- **Formatting/CI** — `mix format --check-formatted` and `mix test`
  must pass.

## Open Questions

- [x] Should `sysd.deploy` (no flag) propagate `--no-publish` when
      it invokes `sysd.release`, or should it always publish?
      Current plan: always publish (matches the spec's literal wording
      "invoke `mix sysd.release`"). Confirm this is the intended UX.  Answer: always publish
- [x] Should `sysd.init` grow a commented publisher example now or
      wait? (Step 11 is optional.)  Answer: yes insert a commented publish section 
- [x] For the `RELEASE_INFO` `build_timestamp`, UTC ISO8601 is assumed.
      Acceptable?  Answer: sure 
- [x] `MIX_ENV=prod` — the existing `sysd.deploy` task does not set
      it explicitly. Keep parity (document precondition) or set it
      inside the new `sysd.release` task? Plan currently keeps parity.  Answer: good question.  I'll use "MIX_ENV=prod mix sysd.release; MIX_ENV=prod mix sysd.deploy"
- [x] For the `gh release create` title, spec says `<app> v<version>`.
      Should `<app>` be the Mix `:app` atom (`myapp`) or a configurable
      display name? Plan assumes the atom, stringified.  Answer: do whatever is simplest.  Probably we'll tweak this after hands-on experience.
