# Обновление OpenCode CLI + Desktop без замены ECC и TencentDB

Скрипт обновляет:

- CLI: `~/.opencode/bin/opencode` из GitHub-релиза (тот же архив, что ставит официальный installer)
- Desktop GUI: пакет `opencode` (`/opt/OpenCode/ai.opencode.desktop`) через `sudo dpkg -i`

Он **не** заменяет ECC, TencentDB, каталог провайдеров/моделей и пользовательские `.desktop`-файлы.

[English version](README.md)

## Что сохраняется

- `~/.config/opencode/opencode.jsonc` (плагины ECC + TencentDB, модели OpenCodex, MCP `memory_tencentdb`)
- `~/.opencode/skills`, `plugins`, `commands`, `tools`, `hooks`
- `~/.opencode/opencode.json` и `~/.opencode/node_modules`, включая `@tencentdb-agent-memory/memory-tencentdb`
- `~/.local/share/applications/*opencode*.desktop` (прокси и переменные окружения)
- контейнеры TencentDB и репозитории `~/src/TencentDB-Agent-Memory*`

Скрипт никогда не запускает `opencode uninstall` и не удаляет `~/.opencode`. CLI меняется только файлом `~/.opencode/bin/opencode`.

## Обновление

```bash
cd ~/src/update-opencode
bash ./update-opencode.sh
```

Текущая раскладка, под которую написан скрипт:

```text
CLI  ~/.opencode/bin/opencode          (официальный curl/tarball)
GUI  пакет dpkg opencode               (/opt/OpenCode)
ECC  ecc-universal в ~/.opencode
TencentDB  npm-пакет + MCP из ~/src/TencentDB-Agent-Memory-opencode
```

## Полезные опции

```bash
bash ./update-opencode.sh --help

# Показать действия без изменений
bash ./update-opencode.sh --dry-run

# Зафиксировать версию
bash ./update-opencode.sh --version 1.18.19

# Только CLI или только GUI
bash ./update-opencode.sh --cli-only
bash ./update-opencode.sh --gui-only

# После обновления прогнать проверку TencentDB/ECC (без живого запроса к модели)
bash ./update-opencode.sh --check
```

Если Desktop `.deb` уже скачал встроенный updater GUI, скрипт повторно использует
`~/.cache/@opencode-aidesktop-updater/pending/`, когда версия совпадает.

Для GUI нужен `sudo` (`dpkg -i`). Пользовательские launcher-ы с HTTP-прокси
восстанавливаются после установки пакета.

## После обновления

Перезапустите OpenCode Desktop. Если запущен `opencode web`, его тоже нужно
перезапустить: старый процесс продолжает работать со старым CLI.

Если пропали скомпилированные файлы ECC:

```bash
bash ~/src/install-ecc-opencode/install-ecc-opencode.sh
```

Если нужен полный refresh адаптера TencentDB:

```bash
bash ~/src/install-TencentDB/install-tencentdb-opencode.sh
```

## Резервные копии

Конфиг и пользовательские `.desktop` копируются в:

```text
~/backup-opencode-update/<timestamp>/
```
