#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-sway dependency check
#
# The check framework lives in scripts/ (a `git subtree` of
# github.com/QMonkey/monkey-scripts) — this file only declares WHAT to check.
# ──────────────────────────────────────────────────────────────

. "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/checkhealth.sh" || {
	echo "monkey-scripts not found — update this checkout (git pull / re-clone)," >&2
	echo "or run install.sh, which bootstraps monkey-scripts itself." >&2
	exit 1
}

# ──────────────────────── identity ────────────────────────
PROJECT=monkey-sway

# ──────────────────────── required ────────────────────────
REQUIRED_CHECKS=(
	"@header|Required tools"
	"@note|(compositor/bar/terminal/launcher/screenshot/portals/polkit/audio/idle/wallpaper/lock)"
	"sway|bin|sway (compositor)"
	"swaymsg|bin|swaymsg (ships with sway)"
	"swaybg|bin|swaybg (wallpaper)"
	"swayidle|bin|swayidle (idle management)"
	"swaylock|bin|swaylock (lock screen)"
	"swaynag|bin|swaynag (exit confirm / warning dialog)"
	"waybar|bin|waybar (status bar)"
	"wezterm|bin|wezterm (default terminal)"
	"bemenu|bin|bemenu (app launcher)"
	"grim|bin|grim (screenshot)"
	"slurp|bin|slurp (region select)"
	"wl-copy|bin|wl-clipboard (wl-copy)"
	"wpctl|bin|wireplumber (wpctl)"
	"mako|bin|mako (notification daemon)"
	"xdg-desktop-portal-wlr|anyofext:xdg-desktop-portal-wlr|xdg-desktop-portal-wlr (capture/sharing portal)"
	"xdg-desktop-portal-gtk|anyofext:xdg-desktop-portal-gtk|xdg-desktop-portal-gtk (file-chooser portal)"
	"polkit-gnome-authentication-agent-1|anyofext:polkit-gnome-authentication-agent-1|polkit-gnome (polkit auth agent)"
)

# ──────────────────────── required install ────────────────────────
# The post-install re-probe walks the specs themselves (one "installed" /
# "still missing" line each, anyofext semantics included) instead of
# re-printing the whole section — REQUIRED_REPROBE_LIST with spec entries +
# REQUIRED_MANUAL_HINT reproduce that via the shared install_missing_required
# (monkey-scripts/lib/checks.sh). Package-name mapping lives in the shared
# lib/pkg.sh table.
REQUIRED_REPROBE_LIST=("${REQUIRED_CHECKS[@]}")
REQUIRED_MANUAL_HINT="Not in system repos — install manually: sway(COMBO), xdg-desktop-portal-wlr, xdg-desktop-portal-gtk, polkit-gnome, wezterm (https://wezterm.org/installation)"

# ──────────────────────── recommended ────────────────────────
RECOMMENDED_NOTE="(Missing won't block monkey-sway, but will degrade tray / brightness / tooling experience)"
RECOMMENDED_CHECKS=(
	"nm-applet|bin|nm-applet (tray network manager)"
	"brightnessctl|bin|brightnessctl"
	"pavucontrol|bin|pavucontrol"
	"nm-connection-editor|bin|nm-connection-editor"
	"hyprpicker|bin|hyprpicker (color picker)"
	"wlsunset|bin|wlsunset (color temperature)"
)

# ──────────────────────── advisory ────────────────────────
# title|note|type|params|ok|incomplete|missing — the missing text carries its
# own second line (the nerd-fonts URL).
ADVISORY_SECTIONS=(
	"$ADVISORY_NERDFONT"
)

# ──────────────────────── config ────────────────────────
# src|dst|desc|mode|name|hint — mode "" accepts any existing symlink target
# (sway's own semantics: whatever the link points at is reported, not judged).
REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_LINKS=(
	"$REPO_DIR/config|$HOME/.config/sway/config|sway config|||sway config not found (run: ln -sf $REPO_DIR/config ~/.config/sway/config)"
	"$REPO_DIR/waybar|$HOME/.config/waybar|waybar|||waybar config not found (run: ln -sfn $REPO_DIR/waybar ~/.config/waybar)"
)

checkhealth_main "$@"
