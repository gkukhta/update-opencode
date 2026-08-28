# Update OpenCode CLI and Desktop

This script updates OpenCode CLI and Desktop GUI on Linux while preserving the
installed ECC, OpenViking, provider configuration, and user launchers.

Russian version: [README-ru.md](README-ru.md)

## What is updated

- CLI: `~/.opencode/bin/opencode` from the official OpenCode GitHub release;
- Desktop GUI: the `opencode` Debian package under `/opt/OpenCode`.

The CLI and GUI are installed at the same target version. By default, the
target is the latest GitHub release from `anomalyco/opencode`.

## What is preserved

- `~/.config/opencode/opencode.jsonc`, including models, providers, ECC, and
  the OpenViking MCP entry;
- `~/.opencode/skills`, `plugins`, `commands`, `tools`, `hooks`, `node_modules`,
  and `opencode.json`;
- the OpenViking MCP proxy at
  `~/.config/opencode/plugins/openviking/servers/mcp-proxy.mjs`;
- user `.desktop` launchers under `~/.local/share/applications`;
- a backup of the configuration and launchers before updating.

The script never runs `opencode uninstall`, never deletes `~/.opencode`, and
does not reinstall ECC or OpenViking. If ECC/OpenViking wiring is missing, it
repairs the configuration when the OpenViking proxy is available.

## Requirements

- Linux x86_64 or arm64;
- `curl`, `tar`, `jq`, `python3`, and `node`;
- for the GUI: `dpkg`, `dpkg-query`, and `sudo` access.

Updating the CLI requires access to GitHub. The GUI is installed with
`sudo dpkg -i`.

## Update

```bash
cd ~/src/update-opencode
bash ./update-opencode.sh
```

If the Desktop updater has already downloaded a `.deb`, the script reuses the
matching package from
`~/.cache/@opencode-aidesktop-updater/pending/`.

## Options

```bash
# Preview without changing anything
bash ./update-opencode.sh --dry-run

# Pin a version
bash ./update-opencode.sh --version 1.18.25

# Update only the CLI or only the GUI
bash ./update-opencode.sh --cli-only
bash ./update-opencode.sh --gui-only

# Do not stop a running Desktop
bash ./update-opencode.sh --no-stop

# Do not repair missing ECC/OpenViking entries
bash ./update-opencode.sh --no-repair

# Additionally check OpenViking proxy syntax
bash ./update-opencode.sh --check

# Reinstall even when the requested version is already installed
bash ./update-opencode.sh --force
```

The OpenViking proxy path can be overridden:

```bash
OPENVIKING_PROXY=/path/to/mcp-proxy.mjs bash ./update-opencode.sh
```

## Post-update checks

After updating, the script checks:

- JSON/JSONC configuration syntax;
- the compiled ECC files;
- an enabled `openviking` MCP entry;
- the existence of the OpenViking proxy.

The `--check` option additionally runs `node --check` on the proxy. No live
model request is performed.

## After updating

Restart OpenCode Desktop. If `opencode web` is running, restart it as well so it
loads the new CLI binary.

If the compiled ECC files are missing:

```bash
bash ~/src/install-ecc-opencode/install-ecc-opencode.sh
```

## Backups

The configuration and user launchers are copied to:

```text
~/backup-opencode-update/<timestamp>/
```

This repository contains only the updater and its documentation. Runtime
configuration, credentials, and keys from the home directory are not added to
the repository.
