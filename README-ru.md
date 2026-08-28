# Обновление OpenCode CLI и Desktop

Скрипт обновляет OpenCode CLI и Desktop GUI в Linux, сохраняя установленный
ECC, OpenViking, конфигурацию провайдеров и пользовательские launchers.

Английская версия: [README.md](README.md)

## Что обновляется

- CLI: `~/.opencode/bin/opencode` из официального GitHub-релиза OpenCode;
- Desktop GUI: Debian-пакет `opencode` в `/opt/OpenCode`.

CLI и GUI устанавливаются на одну и ту же целевую версию. По умолчанию версия
берётся из последнего GitHub-релиза репозитория `anomalyco/opencode`.

## Что сохраняется

- `~/.config/opencode/opencode.jsonc`, включая модели, провайдеров, ECC и MCP
  OpenViking;
- `~/.opencode/skills`, `plugins`, `commands`, `tools`, `hooks`, `node_modules`
  и `opencode.json`;
- OpenViking MCP proxy: `~/.config/opencode/plugins/openviking/servers/mcp-proxy.mjs`;
- пользовательские `.desktop`-launchers из `~/.local/share/applications`;
- резервная копия конфигурации и launchers перед обновлением.

Скрипт не запускает `opencode uninstall`, не удаляет `~/.opencode` и не
переустанавливает ECC или OpenViking. Если в конфигурации отсутствуют записи
ECC/OpenViking, они восстанавливаются при условии, что OpenViking proxy найден.

## Требования

- Linux x86_64 или arm64;
- `curl`, `tar`, `jq`, `python3`, `node`;
- для GUI: `dpkg`, `dpkg-query` и права `sudo`.

Для обновления CLI нужен доступ к GitHub. Для GUI скрипт устанавливает `.deb`
через `sudo dpkg -i`.

## Обновление

```bash
cd ~/src/update-opencode
bash ./update-opencode.sh
```

Если Desktop `.deb` уже скачан встроенным updater’ом, скрипт использует его из
`~/.cache/@opencode-aidesktop-updater/pending/`, если версия совпадает.

## Опции

```bash
# Показать действия без изменений
bash ./update-opencode.sh --dry-run

# Зафиксировать версию
bash ./update-opencode.sh --version 1.18.25

# Обновить только CLI или только GUI
bash ./update-opencode.sh --cli-only
bash ./update-opencode.sh --gui-only

# Не останавливать запущенный Desktop
bash ./update-opencode.sh --no-stop

# Не восстанавливать отсутствующие записи ECC/OpenViking
bash ./update-opencode.sh --no-repair

# Дополнительно проверить синтаксис OpenViking proxy
bash ./update-opencode.sh --check

# Переустановить даже при совпадении версии
bash ./update-opencode.sh --force
```

Путь к OpenViking proxy можно переопределить:

```bash
OPENVIKING_PROXY=/path/to/mcp-proxy.mjs bash ./update-opencode.sh
```

## Проверки после обновления

После обновления скрипт проверяет:

- синтаксис JSON/JSONC-конфигурации;
- наличие скомпилированных файлов ECC;
- включённую MCP-запись `openviking`;
- существование OpenViking proxy.

Опция `--check` дополнительно выполняет `node --check` для proxy. Живой запрос
к модели не выполняется.

## После обновления

Перезапустите OpenCode Desktop. Если запущен `opencode web`, его тоже нужно
перезапустить, чтобы он загрузил новый CLI.

Если отсутствуют скомпилированные файлы ECC:

```bash
bash ~/src/install-ecc-opencode/install-ecc-opencode.sh
```

## Резервные копии

Конфигурация и пользовательские launchers копируются в:

```text
~/backup-opencode-update/<timestamp>/
```

Репозиторий содержит только updater и документацию. Рабочие конфиги,
учётные данные и ключи из домашнего каталога в него не добавляются.
