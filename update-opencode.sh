#!/usr/bin/env bash
set -Eeuo pipefail

# Update OpenCode CLI (~/.opencode/bin) and the Desktop GUI (.deb) without
# replacing ECC or OpenViking. Only ~/.opencode/bin/opencode and the Debian
# GUI package under /opt/OpenCode are replaced. Config, plugins, skills,
# node_modules, the OpenViking proxy and user Desktop launchers stay in place.

OPENCODE_HOME="${OPENCODE_HOME:-$HOME/.opencode}"
OPENCODE_BIN="${OPENCODE_BIN:-$OPENCODE_HOME/bin/opencode}"
OPENCODE_CONFIG="${OPENCODE_CONFIG:-$HOME/.config/opencode/opencode.jsonc}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backup-opencode-update}"
ECC_INSTALLER="${ECC_INSTALLER:-$HOME/src/install-ecc-opencode/install-ecc-opencode.sh}"
OPENVIKING_PROXY="${OPENVIKING_PROXY:-$HOME/.config/opencode/plugins/openviking/servers/mcp-proxy.mjs}"
GITHUB_REPO="${OPENCODE_GITHUB_REPO:-anomalyco/opencode}"
USER_APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
UPDATER_PENDING="${XDG_CACHE_HOME:-$HOME/.cache}/@opencode-aidesktop-updater/pending"
UPDATER_STATE="$HOME/.config/ai.opencode.desktop/opencode.updater"

TARGET_VERSION=""
DO_CLI=1
DO_GUI=1
DRY_RUN=0
STOP_GUI=1
RUN_CHECK=0
FORCE=0
REPAIR=1
LOCAL_DEB=""

log() { printf '[update-opencode] %s\n' "$*" >&2; }
die() { printf '[update-opencode] ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf '[update-opencode] WARN: %s\n' "$*" >&2; }

usage() {
  cat <<'EOF'
Update OpenCode CLI and Desktop GUI without replacing ECC or OpenViking.

Usage:
  ./update-opencode.sh [options]

Options:
  --version VERSION     Install this version (e.g. 1.18.19 or v1.18.19)
  --cli-only            Update only ~/.opencode/bin/opencode
  --gui-only            Update only the Desktop .deb under /opt/OpenCode
  --deb PATH            Use a local GUI .deb instead of downloading
  --dry-run             Show actions without changing anything
  --no-stop             Do not stop a running Desktop GUI
  --no-repair           Do not restore missing ECC/OpenViking wiring
  --check               Run an extra ECC/OpenViking syntax check
  --force               Reinstall even if the requested version is already present
  --help                Show this help

Preserved by design:
  ~/.config/opencode/opencode.jsonc
  ~/.opencode/{skills,plugins,commands,tools,hooks,node_modules,opencode.json}
  ~/.local/share/applications/*opencode*.desktop
  OpenViking MCP configuration and the configured OpenViking proxy

The script never runs `opencode uninstall` and never deletes ~/.opencode.
CLI is replaced from the GitHub release tarball (same artifact as the
official installer). GUI is installed with `sudo dpkg -i`.
EOF
}

while (($#)); do
  case "$1" in
    --version)
      (($# >= 2)) || die "--version requires a value"
      TARGET_VERSION="$2"
      shift 2
      ;;
    --cli-only) DO_GUI=0; shift ;;
    --gui-only) DO_CLI=0; shift ;;
    --deb)
      (($# >= 2)) || die "--deb requires a path"
      LOCAL_DEB="$2"
      shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-stop) STOP_GUI=0; shift ;;
    --no-repair) REPAIR=0; shift ;;
    --check) RUN_CHECK=1; shift ;;
    --force) FORCE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "Unknown option: $1 (use --help)" ;;
  esac
done

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

need_cmd curl
need_cmd tar
need_cmd jq
need_cmd python3
need_cmd node
if ((DO_GUI)); then
  need_cmd dpkg
  need_cmd dpkg-query
fi

normalize_version() {
  local v="${1:-}"
  v="${v#v}"
  printf '%s' "$v"
}

version_eq() { [[ "$(normalize_version "$1")" == "$(normalize_version "$2")" ]]; }

version_gt() {
  local a b
  a="$(normalize_version "$1")"
  b="$(normalize_version "$2")"
  [[ "$a" != "$b" && "$(printf '%s\n' "$a" "$b" | sort -V | tail -n1)" == "$a" ]]
}

run() {
  if ((DRY_RUN)); then
    printf '[update-opencode] DRY:' >&2
    printf ' %q' "$@" >&2
    printf '\n' >&2
    return 0
  fi
  "$@"
}

current_cli_version() {
  if [[ -x "$OPENCODE_BIN" ]]; then
    OPENCODE_PURE=1 "$OPENCODE_BIN" --version 2>/dev/null | head -n1 || true
  elif command -v opencode >/dev/null 2>&1; then
    OPENCODE_PURE=1 opencode --version 2>/dev/null | head -n1 || true
  fi
}

current_gui_version() {
  dpkg-query -W -f '${Version}' opencode 2>/dev/null || true
}

latest_github_version() {
  curl -fsSL "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" \
    | jq -r '.tag_name // empty'
}

pending_gui_version() {
  [[ -f "$UPDATER_STATE" ]] || return 0
  jq -r '.ready.version // empty' "$UPDATER_STATE" 2>/dev/null || true
}

detect_deb_arch() {
  case "$(dpkg --print-architecture 2>/dev/null || uname -m)" in
    amd64|x86_64) printf 'amd64' ;;
    arm64|aarch64) printf 'arm64' ;;
    *) die "Unsupported architecture for OpenCode Desktop: $(uname -m)" ;;
  esac
}

deb_asset_name() {
  printf 'opencode-desktop-linux-%s.deb' "$(detect_deb_arch)"
}

cli_archive_name() {
  local os arch target is_musl=0 needs_baseline=0
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    linux) ;;
    *) die "This updater currently supports Linux CLI archives only (found: $os)" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) die "Unsupported architecture for OpenCode CLI: $(uname -m)" ;;
  esac
  if [[ -f /etc/alpine-release ]]; then
    is_musl=1
  elif command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
    is_musl=1
  fi
  if [[ "$arch" == "x64" ]] && ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
    needs_baseline=1
  fi
  target="linux-${arch}"
  if ((needs_baseline)); then
    target="${target}-baseline"
  fi
  if ((is_musl)); then
    target="${target}-musl"
  fi
  printf 'opencode-%s.tar.gz' "$target"
}

sudo_cmd() {
  if sudo -n true >/dev/null 2>&1; then
    sudo -n "$@"
  else
    log "sudo password required for: $*"
    sudo "$@"
  fi
}

gui_pids() {
  pgrep -f '/opt/OpenCode/ai.opencode.desktop' || true
}

stop_gui() {
  ((STOP_GUI)) || return 0
  local pids
  pids="$(gui_pids)"
  [[ -n "$pids" ]] || return 0
  log "Stopping OpenCode Desktop: $pids"
  if ((DRY_RUN)); then
    return 0
  fi
  # shellcheck disable=SC2086
  kill $pids 2>/dev/null || true
  local i
  for i in {1..20}; do
    pids="$(gui_pids)"
    [[ -z "$pids" ]] && return 0
    sleep 0.25
  done
  pids="$(gui_pids)"
  if [[ -n "$pids" ]]; then
    warn "Desktop still running, sending SIGKILL"
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
}

backup_state() {
  local backup_dir="$1"
  mkdir -p "$backup_dir/desktop"
  if [[ -f "$OPENCODE_CONFIG" ]]; then
    cp -p "$OPENCODE_CONFIG" "$backup_dir/opencode.jsonc"
  fi
  if [[ -f "$OPENCODE_HOME/opencode.json" ]]; then
    cp -p "$OPENCODE_HOME/opencode.json" "$backup_dir/ecc-opencode.json"
  fi
  shopt -s nullglob
  local desktop
  for desktop in "$USER_APPS/"*opencode*.desktop "$USER_APPS/"*OpenCode*.desktop; do
    cp -p "$desktop" "$backup_dir/desktop/"
  done
  shopt -u nullglob
  {
    printf 'cli=%s\n' "$(current_cli_version)"
    printf 'gui=%s\n' "$(current_gui_version)"
    printf 'date=%s\n' "$(date --iso-8601=seconds)"
  } > "$backup_dir/versions.txt"
  log "Backup: $backup_dir"
}

restore_user_desktop() {
  local backup_dir="$1"
  [[ -d "$backup_dir/desktop" ]] || return 0
  shopt -s nullglob
  local desktop
  local restored=0
  for desktop in "$backup_dir/desktop/"*.desktop; do
    run cp -p "$desktop" "$USER_APPS/$(basename -- "$desktop")"
    restored=1
  done
  shopt -u nullglob
  if ((restored)); then
    log "Restored user Desktop launchers with proxy/env overrides"
    if command -v update-desktop-database >/dev/null 2>&1; then
      run update-desktop-database "$USER_APPS" >/dev/null 2>&1 || true
    fi
  fi
}

fetch_latest_or_die() {
  local latest
  latest="$(latest_github_version || true)"
  latest="$(normalize_version "$latest")"
  if [[ -z "$latest" ]]; then
    latest="$(normalize_version "$(pending_gui_version)")"
    [[ -n "$latest" ]] && warn "GitHub latest release lookup failed; using pending Desktop updater version $latest"
  fi
  [[ -n "$latest" ]] || die "Could not determine the latest OpenCode version"
  printf '%s' "$latest"
}

find_extracted_cli() {
  local root="$1"
  if [[ -f "$root/opencode" ]]; then
    printf '%s' "$root/opencode"
    return 0
  fi
  local found
  found="$(find "$root" -maxdepth 2 -type f -name opencode | head -n1 || true)"
  [[ -n "$found" ]] || return 1
  printf '%s' "$found"
}

upgrade_cli() {
  local version="$1"
  local current archive url tmp extracted
  current="$(normalize_version "$(current_cli_version)")"
  if [[ -z "$current" ]]; then
    warn "OpenCode CLI not found; installing $version into $OPENCODE_HOME/bin"
  elif version_eq "$current" "$version" && ((FORCE == 0)); then
    log "CLI already at $current; skipping"
    return 0
  fi
  archive="$(cli_archive_name)"
  url="https://github.com/${GITHUB_REPO}/releases/download/v${version}/${archive}"
  log "Updating CLI ${current:-missing} -> $version from $archive"
  if ((DRY_RUN)); then
    log "DRY: download $url -> $OPENCODE_BIN"
    return 0
  fi
  mkdir -p "$OPENCODE_HOME/bin"
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/opencode-cli.XXXXXX")"
  curl -fL --progress-bar -o "$tmp/$archive" "$url" || die "Failed to download $url"
  tar -xzf "$tmp/$archive" -C "$tmp"
  extracted="$(find_extracted_cli "$tmp")" \
    || die "Archive $archive does not contain an opencode binary"
  install -m 755 "$extracted" "$OPENCODE_BIN"
  rm -rf "$tmp"
  [[ -x "$OPENCODE_BIN" ]] || die "CLI binary missing after upgrade: $OPENCODE_BIN"
  local now
  now="$(normalize_version "$(OPENCODE_PURE=1 "$OPENCODE_BIN" --version | head -n1)")"
  version_eq "$now" "$version" || die "CLI version is $now, expected $version"
  log "CLI is now $now at $OPENCODE_BIN"
}

sha512_b64() {
  python3 - "$1" <<'PY'
import base64, hashlib, sys
path = sys.argv[1]
digest = hashlib.sha512()
with open(path, "rb") as fh:
    for chunk in iter(lambda: fh.read(1024 * 1024), b""):
        digest.update(chunk)
print(base64.b64encode(digest.digest()).decode("ascii"))
PY
}

select_deb() {
  local version="$1"
  local asset pending pending_ver expected actual url tmp
  asset="$(deb_asset_name)"
  if [[ -n "$LOCAL_DEB" ]]; then
    [[ -f "$LOCAL_DEB" ]] || die "Local GUI package not found: $LOCAL_DEB"
    printf '%s' "$LOCAL_DEB"
    return 0
  fi
  pending="$UPDATER_PENDING/$asset"
  pending_ver="$(normalize_version "$(pending_gui_version)")"
  if [[ -f "$pending" ]] && version_eq "$pending_ver" "$version"; then
    if [[ -f "$UPDATER_PENDING/update-info.json" ]]; then
      expected="$(jq -r '.sha512 // empty' "$UPDATER_PENDING/update-info.json")"
      if [[ -n "$expected" ]]; then
        actual="$(sha512_b64 "$pending")"
        if [[ "$actual" != "$expected" ]]; then
          warn "Pending Desktop .deb checksum mismatch; downloading a fresh copy"
        else
          log "Reusing pending Desktop package: $pending"
          printf '%s' "$pending"
          return 0
        fi
      else
        log "Reusing pending Desktop package: $pending"
        printf '%s' "$pending"
        return 0
      fi
    else
      log "Reusing pending Desktop package: $pending"
      printf '%s' "$pending"
      return 0
    fi
  fi
  url="https://github.com/${GITHUB_REPO}/releases/download/v${version}/${asset}"
  log "Downloading $url"
  if ((DRY_RUN)); then
    printf '%s' "/tmp/${asset}"
    return 0
  fi
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/opencode-gui.XXXXXX")"
  curl -fL --progress-bar -o "$tmp/$asset" "$url" || die "Failed to download $url"
  printf '%s' "$tmp/$asset"
}

cleanup_pending_gui() {
  local asset
  asset="$(deb_asset_name)"
  if [[ -f "$UPDATER_STATE" ]] || [[ -e "$UPDATER_PENDING/$asset" ]]; then
    log "Clearing Desktop updater pending state"
    run rm -f "$UPDATER_STATE" "$UPDATER_PENDING/$asset" "$UPDATER_PENDING/update-info.json"
  fi
}

upgrade_gui() {
  local version="$1"
  local current deb now
  current="$(normalize_version "$(current_gui_version)")"
  if [[ -z "$current" ]]; then
    warn "Desktop package 'opencode' is not installed; installing $version"
  elif version_eq "$current" "$version" && ((FORCE == 0)); then
    log "GUI already at $current; skipping"
    return 0
  fi
  deb="$(select_deb "$version")"
  stop_gui
  log "Installing Desktop package $deb"
  if ((DRY_RUN)); then
    log "DRY: sudo dpkg -i $deb"
    return 0
  fi
  sudo_cmd dpkg -i "$deb"
  now="$(normalize_version "$(current_gui_version)")"
  version_eq "$now" "$version" || die "GUI package version is $now, expected $version"
  [[ -x /opt/OpenCode/ai.opencode.desktop ]] || die "Desktop binary missing after install"
  cleanup_pending_gui
  log "GUI is now $now at /opt/OpenCode/ai.opencode.desktop"
}

config_has() {
  local needle="$1"
  [[ -f "$OPENCODE_CONFIG" ]] || return 1
  grep -Fq -- "$needle" "$OPENCODE_CONFIG"
}

ecc_ok() {
  [[ -f "$OPENCODE_HOME/plugins/ecc-hooks.js" && -f "$OPENCODE_HOME/tools/run-tests.js" ]]
}

openviking_ok() {
  [[ -f "$OPENCODE_CONFIG" ]] || return 1
  python3 - "$OPENCODE_CONFIG" <<'PY'
import json
import re
import sys
from pathlib import Path

path = sys.argv[1]
text = Path(path).read_text(encoding="utf-8")
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
text = re.sub(r",\s*([}\]])", r"\1", text)
config = json.loads(text)
entry = (config.get("mcp") or {}).get("openviking")
command = entry.get("command") if isinstance(entry, dict) else None
if not isinstance(entry, dict) or entry.get("enabled") is not True:
    raise SystemExit(1)
if not isinstance(command, list) or not command:
    raise SystemExit(1)
if not any(isinstance(item, str) and Path(item).is_file() for item in command):
    raise SystemExit(1)
PY
}

parse_config() {
  python3 - "$1" <<'PY'
import json, re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
text = re.sub(r"^\s*//.*$", "", text, flags=re.M)
text = re.sub(r",\s*([}\]])", r"\1", text)
json.loads(text)
PY
}

ensure_config_integrations() {
  config_has 'ecc-universal' && openviking_ok && return 0
  ((REPAIR)) || die "OpenCode config is missing ECC/OpenViking wiring"
  [[ -f "$OPENCODE_CONFIG" ]] || die "OpenCode config not found: $OPENCODE_CONFIG"
  [[ -f "$OPENVIKING_PROXY" ]] || die "OpenViking proxy not found: $OPENVIKING_PROXY"
  log "Repairing ECC/OpenViking entries in $OPENCODE_CONFIG"
  if ((DRY_RUN)); then
    return 0
  fi
  local tmp backup
  tmp="$(mktemp)"
  backup="${OPENCODE_CONFIG}.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$OPENCODE_CONFIG" "$backup"
  CONFIG_FILE="$OPENCODE_CONFIG" OUT_FILE="$tmp" OPENVIKING_PROXY="$OPENVIKING_PROXY" python3 <<'PY'
import json, os, re
from pathlib import Path
path = os.environ["CONFIG_FILE"]
text = open(path, encoding="utf-8").read()
stripped = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
stripped = re.sub(r"^\s*//.*$", "", stripped, flags=re.M)
stripped = re.sub(r",\s*([}\]])", r"\1", stripped)
config = json.loads(stripped)
plugins = list(config.get("plugin") or [])
if "ecc-universal" not in plugins:
    plugins.insert(0, "ecc-universal")
config["plugin"] = plugins
config["mcp"] = config.get("mcp") if isinstance(config.get("mcp"), dict) else {}
entry = config["mcp"].get("openviking")
command = entry.get("command") if isinstance(entry, dict) else None
has_proxy = isinstance(command, list) and any(
    isinstance(item, str) and Path(item).is_file() for item in command
)
if not isinstance(entry, dict) or entry.get("enabled") is not True or not has_proxy:
    config["mcp"]["openviking"] = {
        "type": "local",
        "command": ["node", os.environ["OPENVIKING_PROXY"]],
        "enabled": True,
        "timeout": 15000,
    }
open(os.environ["OUT_FILE"], "w", encoding="utf-8").write(json.dumps(config, indent=2) + "\n")
PY
  mv "$tmp" "$OPENCODE_CONFIG"
  parse_config "$OPENCODE_CONFIG" >/dev/null
  log "ECC/OpenViking entries repaired; backup: $backup"
}

verify_integrations() {
  [[ -f "$OPENCODE_CONFIG" ]] || die "OpenCode config not found: $OPENCODE_CONFIG"
  parse_config "$OPENCODE_CONFIG" >/dev/null \
    || die "OpenCode config is not valid JSON/JSONC"
  ensure_config_integrations
  if openviking_ok; then
    log "OpenViking MCP entry and proxy are present"
  else
    warn "OpenViking MCP entry or proxy is missing from $OPENCODE_CONFIG"
    ((REPAIR)) || die "OpenViking is not configured"
  fi
  if ecc_ok; then
    log "ECC compiled plugins are present"
  else
    warn "ECC compiled files are missing under $OPENCODE_HOME/{plugins,tools}"
    if [[ -x "$ECC_INSTALLER" ]]; then
      warn "Reinstall ECC with: $ECC_INSTALLER"
    fi
    ((REPAIR)) || die "ECC is not installed"
  fi
  log "ECC and OpenViking wiring verified"
}

print_summary() {
  cat <<EOF
CLI: $(OPENCODE_PURE=1 "$OPENCODE_BIN" --version 2>/dev/null | head -n1 || echo missing) ($OPENCODE_BIN)
GUI: $(current_gui_version || echo missing) (/opt/OpenCode/ai.opencode.desktop)
Config: $OPENCODE_CONFIG
ECC: $(ecc_ok && echo ok || echo missing)
OpenViking: $(openviking_ok && echo ok || echo missing)
User Desktop launchers: $USER_APPS
EOF
  if pgrep -a -f 'opencode web' >/dev/null 2>&1; then
    warn "opencode web is still running with the previous CLI binary; restart it to pick up the new version"
  fi
}

main() {
  export PATH="$OPENCODE_HOME/bin:$PATH"

  ((DO_CLI || DO_GUI)) || die "Nothing to do"
  mkdir -p "$OPENCODE_HOME/bin" "$(dirname -- "$OPENCODE_CONFIG")" "$USER_APPS"

  local current_cli current_gui target timestamp backup_dir
  current_cli="$(normalize_version "$(current_cli_version)")"
  current_gui="$(normalize_version "$(current_gui_version)")"
  if [[ -n "$TARGET_VERSION" ]]; then
    target="$(normalize_version "$TARGET_VERSION")"
  else
    target="$(fetch_latest_or_die)"
  fi
  [[ -n "$target" ]] || die "Target version is empty"

  log "Current CLI: ${current_cli:-missing}"
  log "Current GUI: ${current_gui:-missing}"
  log "Target:      $target"
  log "Preserving ECC, OpenViking, OpenCode config and user Desktop files"

  if ((FORCE == 0)); then
    if version_gt "$current_cli" "$target" && ((DO_CLI)); then
      die "Installed CLI $current_cli is newer than $target (pass --force to override)"
    fi
    if version_gt "$current_gui" "$target" && ((DO_GUI)); then
      die "Installed GUI $current_gui is newer than $target (pass --force to override)"
    fi
  fi

  timestamp="$(date +%Y%m%d-%H%M%S)"
  backup_dir="$BACKUP_ROOT/$timestamp"
  if ((DRY_RUN == 0)); then
    mkdir -p "$backup_dir"
    backup_state "$backup_dir"
  else
    log "DRY: backup would be written to $backup_dir"
  fi

  if ((DO_CLI)); then
    upgrade_cli "$target"
  fi
  if ((DO_GUI)); then
    upgrade_gui "$target"
    restore_user_desktop "$backup_dir"
  fi

  if ((DRY_RUN == 0)); then
    verify_integrations
    if ((RUN_CHECK)); then
      log "Running OpenViking proxy syntax check"
      node --check "$OPENVIKING_PROXY"
    fi
    print_summary
  fi

  log "OpenCode update completed"
  log "Restart OpenCode Desktop (and opencode web, if used) to load the new version"
}

main "$@"
