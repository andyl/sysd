# Release & Publish Design

Splits the current `mix relman.deploy` into two tasks and adds optional
publishing of release tarballs to external artifact stores (GitHub
Releases first, with a pluggable shape for S3/SCP/etc. later).

## Motivation

Today `mix relman.deploy` does two unrelated things: it builds a
release tarball and it pushes that tarball to the configured servers.
Splitting these gives us a clean "produce artifact" vs. "install
artifact" seam, matching standard CI/CD flow. It also opens the door to
deploying from a machine that isn't the build machine, by pulling a
previously published artifact from GitHub Releases.

## Task Split

**`mix relman.release`** — build the tarball, optionally publish it.

1. Verify `v<@version>` git tag exists locally (created by `mix
   git_ops.release`). Fail if not — relman stays out of the versioning
   business.
2. If the tarball for `@version` already exists locally, skip the build
   unless `--force` is passed.
3. Otherwise run `mix assets.deploy` and `MIX_ENV=prod mix release`.
4. For each publisher configured in `relman.yaml`, run its preflight
   checks, then upload the tarball. Fail fast on the first publisher
   error unless `--replace` is passed (see idempotency below).

**`mix relman.deploy`** — push an existing tarball to servers.

1. If the tarball for `@version` is not present locally, invoke
   `mix relman.release` first (i.e. build locally — this is the
   default).
2. With `--from-release`, instead download the tarball for `@version`
   from the first configured publisher that supports fetching (GitHub
   Releases qualifies). This supports deploying from a machine that
   didn't build the artifact.
3. For each server: upload, extract, flip symlink, restart service
   (unchanged from current behavior).
4. Write a `RELEASE_INFO` file into
   `/opt/relman/<app>/releases/<version>/` recording:
   - git sha
   - build host + timestamp
   - publisher URL if the artifact came from one
   This is cheap, and invaluable during incidents.

"Tarball exists for `@version`" is the only staleness check. No mtime
comparisons against source files — that path leads to stale deploys.
To force a rebuild, pass `--force` or delete the tarball.

## Config Shape

Publishing is modeled as a list of publishers, not a single boolean.
Even though only `github` ships first, the shape leaves room for
future publisher types without reworking config.

```yaml
servers:
  - host1
  - host2
ssh:
  user: deploy

release:
  publish:
    - type: github
      draft: false
      prerelease: false
```

Omitting `release.publish` entirely → local build only, no upload.
The simple case stays simple.

Two publisher types ship in the first implementation: `github` and
`file`. Additional types (`s3`, `scp`, `rsync`, ...) can be added
later without reworking config.

```yaml
release:
  publish:
    - type: github
      draft: false
      prerelease: false
    - type: file
      path: /mnt/releases/myapp/
```

## GitHub Publisher

Uses the `gh` CLI rather than a native HTTP client — `gh` handles auth,
retries, and multipart upload, and most users who'd publish to GH
already have it installed.

**Preflight checks**, run *before* building so failures are fast:

1. `gh` executable on `$PATH`.
2. `gh auth status` exits 0.
3. `git remote get-url origin` points at `github.com` — parse
   `owner/repo` from the URL (support both `https://` and `git@` forms).
4. Local git tag `v<@version>` exists.
5. No existing GH release for `v<@version>` — unless `--replace` was
   passed, in which case delete and recreate.

**Upload**: `gh release create v<@version> <tarball> --title ... [--draft] [--prerelease]`.

**Fetch** (for `relman.deploy --from-release`):
`gh release download v<@version> --pattern '<app>-<version>.tar.gz' --dir _build/prod/rel/<app>/`.

**Release notes**: TBD. The two candidates are the `v<@version>` tag's
commit message and an entry pulled from `CHANGELOG.md`. We'll revisit
this after the first implementation lands — for the initial version,
use a minimal auto-generated title (`<app> v<@version>`) and leave the
body empty.

## File Publisher

A trivial publisher that copies the tarball to a local (or mounted)
directory. Useful for publishing to an NFS share, a directory served
by a static web server, or just a local archive folder.

**Config**:

```yaml
- type: file
  path: /mnt/releases/myapp/
```

**Preflight checks**:

1. `path` is set and is an absolute path.
2. `path` exists and is a writable directory (do not auto-create —
   failing loudly is better than silently creating a typo'd path).
3. No file named `<app>-<version>.tar.gz` already exists at `path` —
   unless `--replace` was passed, in which case overwrite.

**Upload**: `File.cp!/2` the tarball to
`<path>/<app>-<version>.tar.gz`. That's the whole thing.

**Fetch** (for `relman.deploy --from-release`): copy the file back
from `<path>/<app>-<version>.tar.gz` into the expected local build
location.

## Publisher Behavior Model

Both publishers implement the same small internal contract — roughly:

- `preflight(config) :: :ok | {:error, reason}`
- `publish(config, tarball_path, app, version) :: :ok | {:error, reason}`
- `fetch(config, app, version, dest_dir) :: :ok | {:error, reason}`

This keeps the `relman.release` / `relman.deploy` task code free of
per-publisher branching and makes adding a third publisher a matter
of implementing the contract.

## Idempotency

- Re-running `relman.release` for the same `@version`:
  - Build step is a no-op if the tarball exists (unless `--force`).
  - Publish step errors if an artifact for `v<@version>` already
    exists at any configured publisher (unless `--replace`, which
    deletes/overwrites).
- Re-running `relman.deploy` for the same `@version` is already
  idempotent at the server level and stays that way.

## Flags Summary

| Task             | Flag             | Effect                                            |
|------------------|------------------|---------------------------------------------------|
| `relman.release` | `--force`        | Rebuild tarball even if one exists for `@version` |
| `relman.release` | `--replace`      | Delete and recreate an existing GH release        |
| `relman.release` | `--no-publish`   | Build only, skip all configured publishers       |
| `relman.deploy`  | `--from-release` | Pull tarball from publisher instead of building   |

## Flow

Typical release cycle:

```
mix git_ops.release     # bump version, create v<x.y.z> tag
mix relman.release      # build tarball, publish to GH Releases
mix relman.deploy       # push to servers (uses local tarball)
```

Deploy from a fresh checkout (no local build artifacts):

```
git checkout v0.3.0
mix relman.deploy --from-release   # fetches from GH, pushes to servers
```

## Out of Scope

- Publisher types beyond `github` and `file` (S3, SCP, rsync, ...) —
  config shape supports them but implementation waits.
- Release notes sourcing (tag message vs. `CHANGELOG.md`) — revisit
  after first implementation. Initial version uses an empty body and
  an auto-generated title.
- Signing / checksums of published tarballs.
- Automatic tag creation — stays with `git_ops`.
- Rollback via publisher (e.g. "deploy v0.2.9 from GH") — already
  works via `--from-release` combined with a version checkout; no
  special support needed.
