#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="[${GREEN}✓${NC}]"
FAIL="[${RED}✗${NC}]"
WARN="[${YELLOW}!${NC}]"

ALL_PASSED=true
INSTALL_MODE=false

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Check and optionally install dependencies for monkey-sway.

OPTIONS
  -i, --install    Install missing dependencies
  -h, --help       Show this help

Exit code: 1 if any required dependency is missing, 0 otherwise.
EOF
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-i | --install) INSTALL_MODE=true ;;
	-h | --help) usage ;;
	*)
		echo "Unknown option: $1"
		usage
		;;
	esac
	shift
done

# ──────────────────────────── helpers ────────────────────────────

check_bin() {
	if command -v "$1" &>/dev/null; then
		echo -e "  ${PASS} ${2:-$1}"
		return 0
	else
		echo -e "  ${FAIL} ${2:-$1}"
		return 1
	fi
}

# Same as check_bin but accepts multiple alternatives and falls back to
# /usr/lib and /usr/libexec (D-Bus services such as the desktop portals and
# polkit agents usually live outside PATH).
check_bin_ext() {
	local label="$1"
	shift
	for b in "$@"; do
		if command -v "$b" &>/dev/null ||
			[[ -x "/usr/lib/$b" ]] ||
			[[ -x "/usr/libexec/$b" ]] ||
			[[ -x "/usr/lib/polkit-gnome/$b" ]]; then
			echo -e "  ${PASS} $label ($b)"
			return 0
		fi
	done
	echo -e "  ${FAIL} $label"
	return 1
}

# Pure availability test used after --install: PATH or /usr/lib* lookup.
bin_req_ok() {
	local b="$1"
	if [[ "$b" == "notif" ]]; then
		command -v mako &>/dev/null && return 0
		command -v dunst &>/dev/null && return 0
		return 1
	fi
	if command -v "$b" &>/dev/null; then return 0; fi
	for p in "/usr/lib/$b" "/usr/libexec/$b" "/usr/lib/polkit-gnome/$b"; do
		[[ -x "$p" ]] && return 0
	done
	return 1
}

os_detect() {
	case "$(uname -s)" in
	Linux)
		if [ -f /etc/os-release ]; then
			. /etc/os-release
			case "$ID" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
			opensuse | opensuse-leap | opensuse-tumbleweed | opensuse-microos | suse | sles) echo "opensuse" ;;
			centos | rhel | fedora | rocky | almalinux | ol) echo "centos" ;;
			*) echo "linux-unknown" ;;
			esac
		else
			echo "linux-unknown"
		fi
		;;
	*) echo "unknown" ;;
	esac
}

OS=$(os_detect)

sudo_cmd() {
	if command -v sudo &>/dev/null; then
		sudo "$@"
	else
		"$@"
	fi
}

install_pkg() {
	if ! $INSTALL_MODE; then return 1; fi
	case "$OS" in
	debian) sudo_cmd apt-get install -y "${*}" ;;
	arch) sudo_cmd pacman -S --noconfirm "${@}" ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "${@}" ;;
	centos) sudo_cmd dnf install -y "${@}" ;;
	*) return 1 ;;
	esac
}

get_install_hint() {
	case "$OS" in
	debian) echo "sudo apt-get install ${*}" ;;
	opensuse) echo "sudo zypper install ${*}" ;;
	centos) echo "sudo dnf install ${*}" ;;
	arch) echo "sudo pacman -S ${*}" ;;
	linux-unknown) echo "install ${*} manually" ;;
	*) echo "install ${*} manually" ;;
	esac
}

# ────────────────── dependency definitions ──────────────────

REQUIRED_BINS=(sway swaymsg swaybg swayidle swaylock swaynag waybar wezterm bemenu grim slurp wl-copy wpctl mako)
# D-Bus services that may live outside PATH (/usr/lib, /usr/libexec).
REQUIRED_EXT_BINS=(xdg-desktop-portal-wlr xdg-desktop-portal-gtk polkit-gnome-authentication-agent-1)
RECOMMENDED_BINS=(nm-applet brightnessctl pavucontrol nm-connection-editor hyprpicker wlsunset)

# Human-readable name for a dependency binary.
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

# Package name for a binary on the detected OS. Only entries that differ
# from the binary name need a case arm; everything else falls through.
pkg_name() {
	local bin="$1"
	case "$OS:$bin" in
	# Debian / apt
	debian:swaymsg) echo "sway" ;;
	debian:swaybg) echo "swaybg" ;;
	debian:swayidle) echo "swayidle" ;;
	debian:swaylock) echo "swaylock" ;;
	debian:swaynag) echo "sway" ;;
	debian:bemenu) echo "bemenu" ;;
	debian:wl-copy) echo "wl-clipboard" ;;
	debian:wpctl) echo "wireplumber" ;;
	debian:nm-applet) echo "network-manager-gnome" ;;
	debian:polkit-gnome-authentication-agent-1) echo "polkit-gnome" ;;
	# openSUSE / zypper
	opensuse:swaymsg) echo "sway" ;;
	opensuse:swaynag) echo "sway" ;;
	opensuse:wl-copy) echo "wl-clipboard" ;;
	opensuse:wpctl) echo "wireplumber" ;;
	opensuse:nm-applet) echo "NetworkManager-applet" ;;
	opensuse:polkit-gnome-authentication-agent-1) echo "polkit-gnome-authentication-agent-1" ;;
	# CentOS-family / dnf
	centos:wl-copy) echo "wl-clipboard" ;;
	centos:wpctl) echo "wireplumber" ;;
	centos:nm-applet) echo "NetworkManager-applet" ;;
	# Arch / pacman (official binary names match; wezterm ships in extra)
	arch:wezterm) echo "wezterm" ;;
	*)
		echo "$bin"
		;;
	esac
}

# ──────────────────── main ────────────────────

echo -e "${BOLD}monkey-sway dependency check${NC}"
echo ""

# Check the OS
echo -e "${BOLD}Platform${NC}"
echo -e "  OS: ${CYAN}$(uname -s)${NC}"
case "$OS" in
debian) echo -e "  Package manager: ${CYAN}apt${NC}" ;;
opensuse) echo -e "  Package manager: ${CYAN}zypper${NC}" ;;
centos) echo -e "  Package manager: ${CYAN}dnf${NC}" ;;
arch) echo -e "  Package manager: ${CYAN}pacman${NC}" ;;
*) echo -e "  ${WARN} Unsupported OS — install dependencies manually" ;;
esac
echo ""

# ──── required tools ────
echo -e "${BOLD}Required tools${NC}"
echo "  (compositor/bar/terminal/launcher/screenshot/portals/polkit/audio/idle/wallpaper/lock)"
MISSING_REQUIRED=()
for bin in "${REQUIRED_BINS[@]}"; do
	if check_bin "$bin" "$(dep_name "$bin")"; then
		:
	else
		MISSING_REQUIRED+=("$bin")
	fi
done
for bin in "${REQUIRED_EXT_BINS[@]}"; do
	if check_bin_ext "$(dep_name "$bin")" "$bin"; then
		:
	else
		MISSING_REQUIRED+=("$bin")
	fi
done
echo ""

if $INSTALL_MODE && [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
	echo -e "${YELLOW}Installing: ${MISSING_REQUIRED[*]}...${NC}"
	pkgs=()
	for b in "${MISSING_REQUIRED[@]}"; do pkgs+=("$(pkg_name "$b")"); done
	if install_pkg "${pkgs[@]}"; then
		MISSING_REQUIRED=()
		for bin in "${REQUIRED_BINS[@]}" "${REQUIRED_EXT_BINS[@]}"; do
			if bin_req_ok "$bin"; then
				echo -e "  ${PASS} $(dep_name "$bin") installed"
			else
				MISSING_REQUIRED+=("$bin")
				echo -e "  ${FAIL} $(dep_name "$bin") still missing"
			fi
		done
		if [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
			echo -e "${GREEN}All required tools now available.${NC}"
		else
			echo -e "${RED}Not in system repos — install manually: sway(COMBO), xdg-desktop-portal-wlr, xdg-desktop-portal-gtk, polkit-gnome, wezterm (https://wezterm.org/installation)${NC}"
		fi
	else
		echo -e "${RED}Install command failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
	fi
	echo ""
fi

if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
	ALL_PASSED=false
fi

# ──── recommended tools ────
echo -e "${BOLD}Recommended tools${NC}"
echo "  (Missing won't block monkey-sway, but will degrade tray / brightness / tooling experience)"
MISSING_RECOMMENDED=()
for bin in "${RECOMMENDED_BINS[@]}"; do
	if ! check_bin "$bin" "$(dep_name "$bin")"; then
		MISSING_RECOMMENDED+=("$bin")
	fi
done
echo ""

if $INSTALL_MODE && [[ ${#MISSING_RECOMMENDED[@]} -gt 0 ]]; then
	echo -e "${YELLOW}Installing: ${MISSING_RECOMMENDED[*]}...${NC}"
	pkgs=()
	for b in "${MISSING_RECOMMENDED[@]}"; do pkgs+=("$(pkg_name "$b")"); done
	if install_pkg "${pkgs[@]}"; then
		echo -e "${GREEN}Done.${NC}"
	else
		echo -e "${RED}Failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
	fi
	echo ""
fi

# ──── fonts ────
echo -e "${BOLD}Fonts (optional)${NC}"
echo "  (waybar icons use Nerd Font glyphs)"
if fc-list 2>/dev/null | grep -qi "nerd"; then
	echo -e "  ${PASS} Nerd Font found"
else
	echo -e "  ${WARN} No Nerd Font detected — waybar icons may render as boxes"
	echo -e "    https://github.com/ryanoasis/nerd-fonts"
fi
echo ""

# ──── config files ────
echo -e "${BOLD}Config files${NC}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

SWAY_CONFIG="${HOME}/.config/sway/config"
if [[ -L "$SWAY_CONFIG" ]]; then
	TARGET=$(readlink -f "$SWAY_CONFIG" 2>/dev/null || readlink "$SWAY_CONFIG")
	echo -e "  ${PASS} sway config → ${TARGET}"
elif [[ -f "$SWAY_CONFIG" ]]; then
	if [[ "$SWAY_CONFIG" -ef "${SCRIPT_DIR}/config" ]]; then
		echo -e "  ${PASS} sway config → ${SCRIPT_DIR}/config"
	else
		echo -e "  ${WARN} config exists but is not a symlink to ${SCRIPT_DIR}/config"
	fi
else
	echo -e "  ${FAIL} sway config not found (run: ln -sf ${SCRIPT_DIR}/config ~/.config/sway/config)"
	ALL_PASSED=false
fi

WAYBAR_DIR="${HOME}/.config/waybar"
if [[ -L "$WAYBAR_DIR" ]]; then
	TARGET=$(readlink -f "$WAYBAR_DIR" 2>/dev/null || readlink "$WAYBAR_DIR")
	echo -e "  ${PASS} waybar → ${TARGET}"
elif [[ -f "$WAYBAR_DIR/config.jsonc" && -f "$WAYBAR_DIR/style.css" ]]; then
	if [[ -f "${SCRIPT_DIR}/waybar/config.jsonc" && "$WAYBAR_DIR/config.jsonc" -ef "${SCRIPT_DIR}/waybar/config.jsonc" ]]; then
		echo -e "  ${PASS} waybar → ${SCRIPT_DIR}/waybar"
	else
		echo -e "  ${WARN} waybar is a plain directory (not a symlink to ${SCRIPT_DIR}/waybar)"
	fi
else
	echo -e "  ${FAIL} waybar config not found (run: ln -sf ${SCRIPT_DIR}/waybar ~/.config/waybar)"
	ALL_PASSED=false
fi
echo ""

# ──── summary ────
if $ALL_PASSED; then
	echo -e "${GREEN}${BOLD}All required dependencies satisfied.${NC}"
	exit 0
else
	echo -e "${RED}${BOLD}Some required dependencies are missing.${NC}"
	if ! $INSTALL_MODE; then
		echo -e "Run ${CYAN}$0 --install${NC} to install them automatically."
	fi
	exit 1
fi
