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
# Binary lists kept alongside the specs: the post-install re-probe below
# walks them (not the spec list) and prints one line per binary.
REQUIRED_BINS=(sway swaymsg swaybg swayidle swaylock swaynag waybar wezterm bemenu grim slurp wl-copy wpctl mako)
# D-Bus services that may live outside PATH (/usr/lib, /usr/libexec,
# /usr/lib/polkit-gnome).
REQUIRED_EXT_BINS=(xdg-desktop-portal-wlr xdg-desktop-portal-gtk polkit-gnome-authentication-agent-1)

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

# Human-readable name for a dependency binary (used by the re-probe below).
dep_name() {
	case "$1" in
	sway) echo "sway (compositor)" ;;
	swaymsg) echo "swaymsg (ships with sway)" ;;
	swaybg) echo "swaybg (wallpaper)" ;;
	swayidle) echo "swayidle (idle management)" ;;
	swaylock) echo "swaylock (lock screen)" ;;
	swaynag) echo "swaynag (exit confirm / warning dialog)" ;;
	waybar) echo "waybar (status bar)" ;;
	wezterm) echo "wezterm (default terminal)" ;;
	bemenu) echo "bemenu (app launcher)" ;;
	grim) echo "grim (screenshot)" ;;
	slurp) echo "slurp (region select)" ;;
	wl-copy) echo "wl-clipboard (wl-copy)" ;;
	wlogout) echo "wlogout (power menu)" ;;
	wpctl) echo "wireplumber (wpctl)" ;;
	mako) echo "mako (notification daemon)" ;;
	xdg-desktop-portal-wlr) echo "xdg-desktop-portal-wlr (capture/sharing portal)" ;;
	xdg-desktop-portal-gtk) echo "xdg-desktop-portal-gtk (file-chooser portal)" ;;
	polkit-gnome-authentication-agent-1) echo "polkit-gnome (polkit auth agent)" ;;
	nm-applet) echo "nm-applet (tray network manager)" ;;
	hyprpicker) echo "hyprpicker (color picker)" ;;
	wlsunset) echo "wlsunset (color temperature)" ;;
	*) echo "$1" ;;
	esac
}

# Pure availability test used after --install: PATH or /usr/lib* lookup.
bin_req_ok() {
	local b="$1" p
	if have_native_cmd "$b"; then return 0; fi
	for p in "/usr/lib/$b" "/usr/libexec/$b" "/usr/lib/policykit-1-gnome/$b" "/usr/lib/polkit-gnome/$b"; do
		[ -x "$p" ] && return 0
	done
	return 1
}


# ──────────────────────── required install ────────────────────────
# Upstream re-probes EVERY binary after the batch install (one "installed" /
# "still missing" line each) instead of re-printing the whole section —
# REQUIRED_REPROBE_LIST + REQUIRED_NAME_FN + REQUIRED_MANUAL_HINT reproduce
# that via the shared install_missing_required (monkey-scripts/lib/checks.sh).
# Package-name mapping lives in the shared lib/pkg.sh table.
REQUIRED_REPROBE_LIST=("${REQUIRED_BINS[@]}" "${REQUIRED_EXT_BINS[@]}")
REQUIRED_REPROBE_FN=bin_req_ok
REQUIRED_NAME_FN=dep_name
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
	"Fonts (optional)|(waybar icons use Nerd Font glyphs)|nerdfont||Nerd Font found||No Nerd Font detected — waybar icons may render as boxes\n    https://github.com/ryanoasis/nerd-fonts"
)

# ──────────────────────── config ────────────────────────
# sway's config check is its own: ANY symlink is accepted, and a plain file
# that is -ef the repo copy counts as linked too. Overrides the shared
# check_config_files after sourcing.
check_config_files() {
	if $SKIP_CONFIG_CHECKS; then
		warn "config checks skipped (handled by the installer)"
		return 0
	fi
	echo -e "${BOLD}Config files${NC}"
	local script_dir
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

	local sway_config="${HOME}/.config/sway/config"
	if [ -L "$sway_config" ]; then
		local target
		target=$(readlink -f "$sway_config" 2>/dev/null || readlink "$sway_config")
		ok "sway config → ${target}"
	elif [ -f "$sway_config" ]; then
		if [ "$sway_config" -ef "${script_dir}/config" ]; then
			ok "sway config → ${script_dir}/config"
		else
			warn "config exists but is not a symlink to ${script_dir}/config"
		fi
	else
		fail "sway config not found (run: ln -sf ${script_dir}/config ~/.config/sway/config)"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi

	local waybar_dir="${HOME}/.config/waybar"
	if [ -L "$waybar_dir" ]; then
		local target
		target=$(readlink -f "$waybar_dir" 2>/dev/null || readlink "$waybar_dir")
		ok "waybar → ${target}"
	elif [ -f "$waybar_dir/config.jsonc" ] && [ -f "$waybar_dir/style.css" ]; then
		if [ -f "${script_dir}/waybar/config.jsonc" ] && [ "$waybar_dir/config.jsonc" -ef "${script_dir}/waybar/config.jsonc" ]; then
			ok "waybar → ${script_dir}/waybar"
		else
			warn "waybar is a plain directory (not a symlink to ${script_dir}/waybar)"
		fi
	else
		fail "waybar config not found (run: ln -sfn ${script_dir}/waybar ~/.config/waybar)"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi
	echo ""
}

checkhealth_main "$@"
