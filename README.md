# DriftWM dotfiles (End-4 inspired)

Набор дотфайлов в стиле **end-4** для **DriftWM** под **CachyOS** с курсором **Bibata Modern Classic**.

## Что внутри
- `dotfiles/driftwm` — WM-конфиг
- `dotfiles/waybar` — верхняя панель
- `dotfiles/wofi` — launcher
- `dotfiles/foot` — терминал
- `dotfiles/swaync` — уведомления
- `scripts/install-dotfiles.sh` — установка и создание symlink

## Установка
```bash
cd /path/to/my-dotfiles
./scripts/install-dotfiles.sh
```

## Режимы скрипта
```bash
# Только показать, что будет сделано
./scripts/install-dotfiles.sh --dry-run

# Не ставить пакеты, только разложить конфиги
./scripts/install-dotfiles.sh --no-packages

# Если ругается на конфликты существующих путей в ~/.config
./scripts/install-dotfiles.sh --no-packages --force-link
```

Скрипт:
1. Ставит нужные пакеты через `pacman` (если не указан `--no-packages`).
2. Делает бэкап существующих конфигов в `~/.dotfiles-backups/<timestamp>`.
3. Ставит симлинки на конфиги из репозитория.
4. Применяет курсор Bibata Modern Classic для GTK и default cursor.
