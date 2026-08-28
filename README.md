# Update OpenCode CLI + Desktop without replacing ECC or TencentDB

This updates:

- CLI binary: `~/.opencode/bin/opencode` from the GitHub release tarball
- Desktop GUI: Debian package `opencode` (`/opt/OpenCode/ai.opencode.desktop`)

[Русская версия README](README-ru.md)

It does **not** replace ECC, TencentDB, provider catalogs, or user Desktop launchers.

## What is preserved

- `~/.config/opencode/opencode.jsonc` (ECC + TencentDB plugin list, OpenCodex models, MCP `memory_tencentdb`)
- `~/.opencode/skills`, `plugins`, `commands`, `tools`, `hooks`
- `~/.opencode/opencode.json` and `~/.opencode/node_modules` including `@tencentdb-agent-memory/memory-tencentdb`
- `~/.local/share/applications/*opencode*.desktop` (proxy/env overrides)
- TencentDB Docker containers and `~/src/TencentDB-Agent-Memory*`

The script never runs `opencode uninstall` and never deletes `~/.opencode`.

## Update

```bash
cd ~/src/update-opencode
bash ./update-opencode.sh
```

Current machine layout this was written for:

```text
CLI  ~/.opencode/bin/opencode          (GitHub release tarball)
GUI  dpkg package opencode             (/opt/OpenCode)
ECC  ecc-universal under ~/.opencode
TencentDB  npm package + MCP from ~/src/TencentDB-Agent-Memory-opencode
```

## Useful options

```bash
bash ./update-opencode.sh --help

# Preview without changing anything
bash ./update-opencode.sh --dry-run

# Pin a version
bash ./update-opencode.sh --version 1.18.19

# CLI or GUI only
bash ./update-opencode.sh --cli-only
bash ./update-opencode.sh --gui-only

# After update, run the TencentDB/ECC checker (no live model request)
bash ./update-opencode.sh --check
```

If a Desktop `.deb` was already downloaded by the GUI updater, the script reuses
`~/.cache/@opencode-aidesktop-updater/pending/` when the version matches.

## After update

Restart OpenCode Desktop. If `opencode web` is running, restart that too: the
old process keeps the previous CLI binary mapped.

If ECC compiled files are missing, reinstall with:

```bash
bash ~/src/install-ecc-opencode/install-ecc-opencode.sh
```

If the TencentDB adapter needs a full refresh:

```bash
bash ~/src/install-TencentDB/install-tencentdb-opencode.sh
```

## Backups

Config and user `.desktop` files are copied to:

```text
~/backup-opencode-update/<timestamp>/
```
