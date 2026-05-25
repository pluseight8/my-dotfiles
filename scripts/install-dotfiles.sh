#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES_DIR="$ROOT_DIR/dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backups/$(date +%Y%m%d-%H%M%S)"

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

echo "==> Installing packages for CachyOS (pacman)..."
sudo pacman -S --needed "${packages[@]}"

mkdir -p "$BACKUP_DIR"
mkdir -p "$HOME/.config"

backup_and_link() {
  local src="$1"
  local dst="$2"

  if [[ -e "$dst" || -L "$dst" ]]; then
    echo "==> Backing up $dst"
    mkdir -p "$BACKUP_DIR/$(dirname "${dst#$HOME/}")"
    mv "$dst" "$BACKUP_DIR/${dst#$HOME/}"
  fi

  mkdir -p "$(dirname "$dst")"
  ln -s "$src" "$dst"
  echo "==> Linked $dst -> $src"
}

backup_and_link "$DOTFILES_DIR/driftwm" "$HOME/.config/driftwm"
backup_and_link "$DOTFILES_DIR/waybar" "$HOME/.config/waybar"
backup_and_link "$DOTFILES_DIR/wofi" "$HOME/.config/wofi"
backup_and_link "$DOTFILES_DIR/foot" "$HOME/.config/foot"
backup_and_link "$DOTFILES_DIR/swaync" "$HOME/.config/swaync"

mkdir -p "$HOME/.icons/default"
cat > "$HOME/.icons/default/index.theme" <<THEME
[Icon Theme]
Inherits=Bibata-Modern-Classic
THEME

cat > "$HOME/.config/gtk-3.0/settings.ini" <<GTK
[Settings]
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
GTK

cat > "$HOME/.config/gtk-4.0/settings.ini" <<GTK
[Settings]
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
GTK

echo ""
echo "Done. Backups are in: $BACKUP_DIR"
echo "Log out and choose DriftWM session."
