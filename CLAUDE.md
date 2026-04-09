# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

RelDep is a minimalist Elixir tool for deploying Elixir Releases to bare metal servers over SSH. It targets LAN/internal deployments using Mix tasks as the CLI, SSHex for SSH, and systemd for service management on remote servers. Design spec lives in `_spec/designs/`.

## Common Commands

```bash
mix deps.get          # Install dependencies
mix compile           # Compile
mix test              # Run all tests
mix test test/reldep_test.exs   # Run a single test file
mix test --only tag_name        # Run tests by tag
mix format            # Format code
mix format --check-formatted    # Check formatting
```

## Architecture

The project is structured as a Mix library that exposes Mix tasks (`mix reldep.*`) for deployment operations. Key dependencies:

- **SSHex** — SSH connectivity to remote servers
- **git_ops** — version management via conventional commits
- **igniter** — code generation (dev/test only)

Planned Mix tasks (see `_spec/designs/260327_DesignOverview.md`): `reldep.init`, `reldep.sshcheck`, `reldep.setup`, `reldep.deploy`, `reldep.versions`, `reldep.rollback`, `reldep.remove`, `reldep.cleanup`.

Mix tasks should live under `lib/mix/tasks/reldep.*.ex`. Config is YAML-based at `config/reldep.yaml` in consumer projects. Remote server layout uses `/opt/reldep/<appname>/{archives,releases,current}`.

## Git Commits

Use the **Conventional Commits** standard for all commit messages (e.g. `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`). This aligns with the git_ops configuration. Version tag prefix is `v`. Version is in `mix.exs` (`@version`).
