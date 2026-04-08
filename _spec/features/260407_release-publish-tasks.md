# Release Publish Tasks

## Summary

Split the existing `mix relman.deploy` task into two distinct Mix tasks —
`mix relman.release` for producing a release tarball and optionally publishing
it to an external artifact store, and `mix relman.deploy` for pushing a
tarball to configured servers. Introduce a pluggable publisher system, with
two publisher types shipping in the first implementation: `github` (via the
`gh` CLI) and `file` (copy to a local or mounted directory).

## Goals

- Separate artifact production from artifact installation for a cleaner
  CI/CD seam.
- Allow deploying from a machine that did not build the artifact, by
  fetching a previously published tarball.
- Provide a pluggable publisher shape in `config/relman.yaml` that supports
  multiple publishers simultaneously and leaves room for future types.
- Ship two publisher types: `github` and `file`.
- Record deploy provenance on the remote server for incident debugging.
- Fail fast on publisher misconfiguration before any build work happens.

## Non-Goals

- Publisher types beyond `github` and `file` (S3, SCP, rsync, etc.).
- Automatic git tag creation — tag management remains with `git_ops`.
- Release notes sourcing (tag message vs. `CHANGELOG.md`). The first
  implementation uses an auto-generated title and an empty body; the notes
  source will be revisited after the feature lands.
- Signing or checksum verification of published tarballs.
- Zero-downtime deploys or any change to the existing per-server deploy
  behavior (upload, extract, symlink, restart).

## Mix Tasks

### relman.release

Build the release tarball and optionally publish it to each configured
publisher.

Behavior:

- Verify that the git tag `v<@version>` exists locally. Fail if not.
- If a tarball for the current `@version` already exists locally, skip the
  build step unless `--force` is passed.
- Otherwise run `mix assets.deploy` followed by `MIX_ENV=prod mix release`.
- Run preflight checks for every configured publisher *before* building, so
  misconfiguration fails fast.
- After the build succeeds, invoke each configured publisher in order.
- If any publisher reports that an artifact for the current version already
  exists, fail unless `--replace` was passed.

Flags:

- `--force` — rebuild the tarball even if one already exists for `@version`.
- `--replace` — delete and recreate an existing published artifact.
- `--no-publish` — build only; skip all configured publishers.

### relman.deploy

Push an existing release tarball to each configured server. This replaces
the current `relman.deploy` behavior of unconditionally building a release
before deploying.

Behavior:

- If no local tarball exists for `@version`, invoke `mix relman.release` to
  build one. This is the default path.
- If `--from-release` is passed, instead fetch the tarball for `@version`
  from the first configured publisher that supports fetching. This enables
  deploying from a machine that did not build the artifact.
- For each configured server, perform the existing deploy workflow: upload
  the tarball, extract it, flip the `current` symlink, restart the systemd
  service.
- After a successful deploy on each server, write a `RELEASE_INFO` file
  into `/opt/relman/<app>/releases/<version>/` containing:
  - git sha
  - build host and timestamp
  - publisher URL (if the tarball was fetched from a publisher)

Flags:

- `--from-release` — fetch the tarball from the first fetch-capable
  publisher instead of building locally.

## Publisher System

Publishing is modeled as an ordered list of publishers in
`config/relman.yaml`. Omitting the `release.publish` key entirely results in
a local build with no upload, keeping the simple case simple.

Each publisher type implements the same internal contract covering three
operations:

- **Preflight** — validate configuration and environment before any build
  work runs.
- **Publish** — upload or copy the tarball to the destination.
- **Fetch** — retrieve a previously published tarball for a given version
  into the local build location (used by `relman.deploy --from-release`).

This contract keeps the task code free of per-publisher branching and makes
adding a future publisher type (S3, SCP, rsync, ...) a matter of
implementing the contract.

### GitHub Publisher

Config:

```yaml
release:
  publish:
    - type: github
      draft: false
      prerelease: false
```

Preflight checks:

- `gh` executable is on `$PATH`.
- `gh auth status` exits successfully.
- `git remote get-url origin` points at `github.com`. Both `https://` and
  `git@` URL forms are supported, and `owner/repo` is parsed from the URL.
- The git tag `v<@version>` exists locally.
- No existing GitHub release exists for `v<@version>`, unless `--replace`
  was passed (in which case the existing release is deleted first).

Publish behavior:

- Uses `gh release create` to create a new release attached to the
  `v<@version>` tag, uploading the tarball as a release asset.
- Honors the `draft` and `prerelease` config options.
- Uses an auto-generated title (`<app> v<@version>`) and an empty body in
  the first implementation. Release notes sourcing is deferred.

Fetch behavior:

- Uses `gh release download` to retrieve the tarball asset for `v<@version>`
  into the expected local build directory.

### File Publisher

Copies the tarball to a local or mounted filesystem directory. Useful for
publishing to an NFS share, a directory served by a static web server, or
just a local archive folder.

Config:

```yaml
release:
  publish:
    - type: file
      path: /mnt/releases/myapp/
```

Preflight checks:

- `path` is set and is an absolute path.
- `path` exists and is a writable directory. The path is not auto-created —
  failing loudly is preferred over silently creating a typo'd directory.
- No file named `<app>-<version>.tar.gz` already exists at `path`, unless
  `--replace` was passed (in which case the existing file is overwritten).

Publish behavior:

- Copies the tarball to `<path>/<app>-<version>.tar.gz`.

Fetch behavior:

- Copies the file back from `<path>/<app>-<version>.tar.gz` into the
  expected local build location.

## Configuration

The `release.publish` key is added to `config/relman.yaml`. A config using
both shipping publisher types:

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
    - type: file
      path: /mnt/releases/myapp/
```

Omitting `release.publish` results in a local build only, with no upload.

## Idempotency

- Re-running `relman.release` for the same `@version`:
  - The build step is a no-op if a tarball already exists, unless `--force`
    is passed.
  - The publish step errors if an artifact for `v<@version>` already exists
    at any configured publisher, unless `--replace` is passed (which
    deletes or overwrites the existing artifact).
- Re-running `relman.deploy` for the same `@version` remains idempotent at
  the server level. The existing per-server deploy behavior is unchanged.

## Typical Flow

Standard release cycle:

```
mix git_ops.release     # bump version, create v<x.y.z> tag
mix relman.release      # build tarball, publish to configured targets
mix relman.deploy       # push to servers (uses local tarball)
```

Deploying from a fresh checkout with no local build artifacts:

```
git checkout v0.3.0
mix relman.deploy --from-release
```
