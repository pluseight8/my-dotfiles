#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="$ROOT_DIR/dotfiles"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$HOME/.dotfiles-backups/$TIMESTAMP"
INSTALL_PACKAGES=1
DRY_RUN=0
FORCE_LINK=0

packages=(
  driftwm
  waybar
  wofi
  foot
  swaync
  swww
  grim
  slurp
  bibata-cursor-theme
  ttf-jetbrains-mono-nerd
)

usage() {
  cat <<USAGE
Usage: $(basename "$0") [options]

Options:
  --no-packages   Skip pacman package installation
  --dry-run       Print planned actions without changing files
  --force-link     Remove destination before symlink (no backup)
  -h, --help      Show this help message
USAGE
}

log() { echo "==> $*"; }

run() {
  if (( DRY_RUN )); then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

write_file() {
  local dst="$1"
  local content="$2"
  if (( DRY_RUN )); then
    echo "[dry-run] write $dst"
    return 0
  fi
  printf '%s\n' "$content" > "$dst"
}

backup_and_link() {
  local src="$1"
  local dst="$2"

  if [[ ! -e "$src" ]]; then
    echo "ERROR: missing source path: $src" >&2
    exit 1
  fi

  if [[ -L "$dst" ]]; then
    local link_target=""
    link_target="$(readlink "$dst" 2>/dev/null || true)"
    if [[ "$link_target" == "$src" ]]; then
      log "Already linked: $dst -> $src"
      return 0
    fi
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    if (( FORCE_LINK )); then
      log "Removing existing path (force): $dst"
      run rm -rf "$dst"
    else
      log "Backing up $dst"
      run mkdir -p "$BACKUP_DIR/$(dirname "${dst#$HOME/}")"
      run mv "$dst" "$BACKUP_DIR/${dst#$HOME/}"
    fi
  fi

  run mkdir -p "$(dirname "$dst")"
  run ln -s "$src" "$dst"
  log "Linked $dst -> $src"
}

for arg in "$@"; do
  case "$arg" in
    --no-packages) INSTALL_PACKAGES=0 ;;
    --dry-run) DRY_RUN=1 ;;
    --force-link) FORCE_LINK=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ ! -d "$DOTFILES_DIR" ]]; then
  echo "ERROR: dotfiles directory not found: $DOTFILES_DIR" >&2
  exit 1
fi

if (( INSTALL_PACKAGES )); then
  if ! command -v pacman >/dev/null 2>&1; then
    echo "ERROR: pacman not found. This script is intended for CachyOS/Arch-based systems." >&2
    exit 1
  fi
  log "Installing packages for CachyOS (pacman)..."
  run sudo pacman -Syu --needed "${packages[@]}"
else
  log "Skipping package installation (--no-packages)"
fi

run mkdir -p "$BACKUP_DIR"
run mkdir -p "$HOME/.config" "$HOME/.icons/default" "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"

backup_and_link "$DOTFILES_DIR/driftwm" "$HOME/.config/driftwm"
backup_and_link "$DOTFILES_DIR/waybar" "$HOME/.config/waybar"
backup_and_link "$DOTFILES_DIR/wofi" "$HOME/.config/wofi"
backup_and_link "$DOTFILES_DIR/foot" "$HOME/.config/foot"
backup_and_link "$DOTFILES_DIR/swaync" "$HOME/.config/swaync"

write_file "$HOME/.icons/default/index.theme" "[Icon Theme]
Inherits=Bibata-Modern-Classic"

write_file "$HOME/.config/gtk-3.0/settings.ini" "[Settings]
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24"

write_file "$HOME/.config/gtk-4.0/settings.ini" "[Settings]
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24"

echo
log "Done. Backups are in: $BACKUP_DIR"
log "Log out and choose DriftWM session."
