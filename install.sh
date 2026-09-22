#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-sway one-shot installer
# Usage: curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-sway/master/install.sh | bash
#
# Installs sway + dependencies from the distro repo (via
# checkhealth.sh --install), clones this repo and links the configs, and
# writes a guarded VT autostart block into the shell profile files
# (the meta-installer's dependency order puts the compositor before tmux,
# so the block lands above any tmux auto-start block).
# ──────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-sway}"
SUDOERS_D_DIR="${SUDOERS_D_DIR:-/etc/sudoers.d}"
SUDO_NOPASSWD=0
NOPASSWD_DROPIN="$SUDOERS_D_DIR/zz-monkey-sway-nopasswd"
SUDO_BIN=""
SUDO_KEEPALIVE_PID=""
AUTOSTART_FILES=""

# Never let a missing HOME fail later under `set -u`.
[ -n "${HOME:-}" ] || {
	echo "[FAIL] \$HOME is not set — cannot determine install locations." >&2
	exit 1
}

info() { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok() { echo -e "${GREEN}[  OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail() {
	echo -e "${RED}[FAIL]${NC}  $*"
	exit 1
}

# ────────────────── OS / WSL detection ──────────────────

os_detect() {
	case "$(uname -s)" in
	Linux)
		if [ -f /etc/os-release ]; then
			# shellcheck disable=SC1091
			. /etc/os-release
			case "${ID:-}" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
			opensuse* | suse | sles) echo "opensuse" ;;
			centos | rhel | fedora | rocky | almalinux | ol) echo "centos" ;;
			*) echo "linux-unknown" ;;
			esac
		else
			echo "linux-unknown"
		fi
		;;
	*) echo "non-linux" ;;
	esac
}

# WSL interop appends the WINDOWS PATH to ours, so tools installed on the
# Windows side appear as /mnt/c/... shims. They are not Linux binaries —
# treat /mnt/* resolutions as "not installed".
have_native_cmd() {
	command -v "$1" &>/dev/null || return 1
	case "$(command -v "$1")" in
	/mnt/*) return 1 ;; # WSL Windows-interop shim
	esac
	return 0
}

# True under WSL (1 or 2): both kernels carry "microsoft" in the release
# string (WSL1 "...-Microsoft", WSL2 "...-microsoft-standard-WSL2").
is_wsl() {
	case "$(uname -r)" in
	*[Mm]icrosoft*) return 0 ;;
	*) return 1 ;;
	esac
}

# Absolute path to a LINUX sudo, or non-zero.
native_sudo() {
	local p
	have_native_cmd sudo || return 1
	p=$(command -v sudo)
	printf '%s' "$p"
}

sudo_cmd() {
	# Lazy re-auth: sudo tickets expire — re-authenticate proactively with
	# an explanatory prompt instead of letting a command fail or spring a
	# context-free password prompt. `-n true` never prompts; the
	# interactive `-v` only runs when the ticket is actually gone.
	local sudo_bin
	sudo_bin=$(native_sudo) || {
		"$@"
		return
	}
	if ! "$sudo_bin" -n true 2>/dev/null; then
		"$sudo_bin" -v -p "[monkey-sway] sudo credentials needed to continue — enter your password: " || return 1
	fi
	"$sudo_bin" "$@"
}

OS=$(os_detect)

# ────────────────── sudo setup (auth + drop-ins + keepalive) ──────────────────

cleanup_sudo() {
	if [ -n "$SUDO_KEEPALIVE_PID" ]; then
		kill "$SUDO_KEEPALIVE_PID" 2>/dev/null
		wait "$SUDO_KEEPALIVE_PID" 2>/dev/null
	fi
	if [ "$SUDO_NOPASSWD" -eq 1 ] && [ -n "$SUDO_BIN" ]; then
		SUDO_NOPASSWD=0
		"$SUDO_BIN" -n rm -f "$NOPASSWD_DROPIN" 2>/dev/null ||
			warn "could not remove the NOPASSWD drop-in — remove it manually: sudo rm $NOPASSWD_DROPIN"
	fi
}

setup_sudo() {
	SUDO_BIN=$(native_sudo) || return 0
	if [ "$(id -u)" -eq 0 ]; then
		return 0
	fi
	# Probe first (`-n true`): a valid grant (a previous stage's drop-in or
	# an outer installer's) skips authentication entirely. Otherwise one
	# `sudo -v` — the only password entry of this run.
	if ! "$SUDO_BIN" -n true 2>/dev/null; then
		"$SUDO_BIN" -v || fail "sudo authorization failed — run this script in an interactive terminal."
	fi
	# GNU sudo resolves conflicting rules last-match-wins, so this drop-in
	# always wins over the distro's password-required rule; removed on exit.
	if printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$(id -un)" |
		"$SUDO_BIN" -n sh -c 'umask 077; cat >"$1" && chmod 0440 "$1" && visudo -c -f "$1" >/dev/null 2>&1 || { rm -f "$1"; exit 1; }' sh "$NOPASSWD_DROPIN" >/dev/null 2>&1; then
		SUDO_NOPASSWD=1
		ok "Temporary NOPASSWD drop-in installed for this run (auto-removed on exit)."
	else
		warn "could not install the temporary NOPASSWD drop-in — falling back to keepalive + lazy re-auth."
	fi
	if [ "$SUDO_NOPASSWD" -eq 0 ]; then
		(
			interval="${SUDO_KEEPALIVE_INTERVAL:-60}"
			trap 'kill $(jobs -p) 2>/dev/null; wait 2>/dev/null; exit 0' TERM
			while true; do
				sleep "$interval" &
				wait "$!" 2>/dev/null || exit 0
				if ! "$SUDO_BIN" -n true 2>/dev/null; then
					exit 0
				fi
			done
		) &
		SUDO_KEEPALIVE_PID=$!
	fi
	trap cleanup_sudo EXIT
	trap 'exit 130' INT
	trap 'exit 143' TERM
}

# ────────────────── package manager helpers ──────────────────

# Refresh the package index before installing (at most once per run;
# never fatal).
PKG_DB_REFRESHED=0
refresh_pkg() {
	[ "$PKG_DB_REFRESHED" -eq 1 ] && return 0
	PKG_DB_REFRESHED=1
	local attempt
	for attempt in 1 2; do
		case "$OS" in
		debian) sudo_cmd apt-get update ;;
		arch) sudo_cmd pacman -Sy ;;
		opensuse) sudo_cmd zypper --non-interactive refresh ;;
		centos) sudo_cmd dnf makecache -q ;;
		*) return 0 ;;
		esac && return 0
		[ "$attempt" -lt 2 ] && sleep 2
	done
	return 0
}

install_pkg() {
	refresh_pkg
	case "$OS" in
	debian) sudo_cmd apt-get install -y "$@" ;;
	arch) sudo_cmd pacman -S --needed --noconfirm "$@" ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "$@" ;;
	centos)
		sudo_cmd dnf install -y epel-release || true
		sudo_cmd dnf install -y "$@"
		;;
	*) return 1 ;;
	esac
	hash -r
}

# ────────────────── Step 1: sway from the distro repo ──────────────────

install_sway() {
	if have_native_cmd sway; then
		ok "sway already installed."
		return 0
	fi
	info "Installing sway from the $OS repository..."
	if ! install_pkg sway; then
		warn "sway install failed — install it manually."
		return 0
	fi
	ok "sway installed."
}

# ────────────────── Step 2: Clone this repo ──────────────────

clone_monkey_sway() {
	if [ -d "$INSTALL_DIR/.git" ]; then
		info "monkey-sway already exists at $INSTALL_DIR — pulling latest..."
		git -C "$INSTALL_DIR" pull --ff-only || warn "git pull failed — keeping existing version."
	elif [ -e "$INSTALL_DIR" ]; then
		fail "$INSTALL_DIR exists but is not a git clone — remove it or set INSTALL_DIR."
	else
		info "Cloning monkey-sway to $INSTALL_DIR..."
		git clone https://github.com/QMonkey/monkey-sway.git "$INSTALL_DIR"
	fi
	ok "monkey-sway ready at $INSTALL_DIR."
}

# ────────────────── Step 3: checkhealth.sh --install ──────────────────

run_checkhealth() {
	info "Running checkhealth.sh --install to install remaining dependencies..."
	# Transient failures (network blips, apt locks) heal on retry; after the
	# first pass everything installed is skipped, so retries are cheap.
	local attempt ok=0
	for attempt in 1 2 3; do
		if bash "$INSTALL_DIR/checkhealth.sh" --install --skip-check-config; then
			ok=1
			break
		fi
		if [ "$attempt" -lt 3 ]; then
			warn "checkhealth attempt $attempt/3 failed — retrying..."
			sleep 2
		fi
	done
	if [ "$ok" = 1 ]; then
		ok "Dependency check complete."
	else
		warn "Some dependencies could not be installed automatically."
		warn "Run 'cd $INSTALL_DIR && ./checkhealth.sh' to review remaining items."
	fi
}

# ────────────────── Step 4: compositor autostart (guarded VT login) ──────────────────

# Print the shell startup files for the login shell — the same profile
# files an `exec tmux` auto-start block occupies:
#   - zsh: profile ONLY (~/.zprofile). .zshrc is repo-managed and sources
#     the profile for non-login shells.
#   - bash: profile AND rc (~/.bash_profile or ~/.profile + ~/.bashrc).
#     Non-login interactive bash (desktop terminal emulators, VS Code
#     terminal) only reads ~/.bashrc.
shell_env_files() {
	local shell_bin=""
	if have_native_cmd getent; then
		shell_bin=$(getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7)
	fi
	shell_bin="${shell_bin:-${SHELL:-bash}}"
	case "${shell_bin##*/}" in
	zsh)
		printf '%s\n' "$HOME/.zprofile"
		;;
	bash)
		if [ -f "$HOME/.bash_profile" ]; then
			printf '%s\n' "$HOME/.bash_profile"
		else
			printf '%s\n' "$HOME/.profile"
		fi
		printf '%s\n' "$HOME/.bashrc"
		;;
	*)
		printf '%s\n' "$HOME/.profile"
		;;
	esac
}

# The guarded autostart block. POSIX sh: it lands in ~/.profile too, which
# display managers may source with a minimal shell. Guards, cheapest first,
# so shells inside a desktop terminal or tmux pane short-circuit with zero
# forks:
#   1. $WAYLAND_DISPLAY / $DISPLAY both unset — one of them is set in any
#      desktop session (Wayland or X11).
#   2. stdin is a real VT (/dev/ttyN) — excludes ssh (/dev/pts/N), tmux
#      panes and desktop terminals in one check. Immune to inherited env:
#      a TTY-started tmux server passes XDG_VTNR down to its panes, but
#      their stdin stays a pty.
#   3. no sway running — single-instance policy: once sway owns a session,
#      VT logins on other consoles fall through to a plain shell (the
#      escape hatch instead of a second compositor).
# Other desktops (X11 or Wayland) are deliberately NOT checked: logind
# arbitrates the seat per session, so sway coexists with them.
autostart_block() {
	local exec_cmd="$1" pgrep_name="$2"
	cat <<EOF
# monkey-sway autostart (remove these lines to disable)
# Keep this block ABOVE any "exec tmux" auto-start block: on a bare TTY
# exec replaces the login shell with the compositor, so the tmux
# auto-start line is never reached and the desktop never runs inside a
# tmux pane. Inside a desktop terminal the env guards short-circuit and
# the tmux auto-start runs normally.
if [ -z "\${WAYLAND_DISPLAY:-}" ] && [ -z "\${DISPLAY:-}" ]; then
    case "\$(tty 2>/dev/null)" in
    /dev/tty[0-9]*) pgrep -x $pgrep_name >/dev/null 2>&1 || exec $exec_cmd ;;
    esac
fi
EOF
}

write_tty_autostart() {
	local exec_cmd="$1" pgrep_name="$2"
	local marker="# monkey-sway autostart" f
	# WSL has no VT login — stdin never resolves to /dev/ttyN, so the
	# guarded block would be dead code. WSLg renders single GUI apps
	# without a compositor.
	if is_wsl; then
		info "WSL detected — skipping autostart setup (no VT login; WSLg covers GUI apps)."
		return 0
	fi
	while IFS= read -r f; do
		[ -n "$f" ] || continue
		[ -f "$f" ] || touch "$f"
		if grep -qF -- "$marker" "$f"; then
			ok "autostart block already present in $f."
		else
			# Ordering vs a tmux auto-start block needs no insert logic:
			# the meta-installer installs compositor repos before the tmux
			# repo, so this block is always appended first.
			printf '\n%s\n' "$(autostart_block "$exec_cmd" "$pgrep_name")" >>"$f"
			ok "Added autostart block to $f."
		fi
		AUTOSTART_FILES="$AUTOSTART_FILES $f"
	done < <(shell_env_files)
}

# ────────────────── Step 5: symlinks ──────────────────

link_config() {
	# Usage: link_config <src> <dst>. Never overwrites an existing target
	# that is not this repo's link (ln -sfn into a real directory would
	# create the link INSIDE it).
	local src="$1" dst="$2"
	if [ -e "$dst" ] || [ -L "$dst" ]; then
		if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
			ok "$(basename "$dst") already linked."
		else
			warn "$dst exists and is not this repo's link — skipping."
			echo -e "    re-link manually with: ${CYAN}ln -sfn $src $dst${NC}"
		fi
		return 0
	fi
	ln -sfn "$src" "$dst"
	ok "$dst → $src"
}

setup_symlinks() {
	info "Setting up configuration symlinks..."
	mkdir -p "$HOME/.config/sway"
	link_config "$INSTALL_DIR/config" "$HOME/.config/sway/config"
	link_config "$INSTALL_DIR/pictures" "$HOME/.config/sway/pictures"
	link_config "$INSTALL_DIR/waybar" "$HOME/.config/waybar"
}

# ──────────────────── main ────────────────────

main() {
	echo ""
	echo -e "${BOLD}╔══════════════════════════════════════════╗${NC}"
	echo -e "${BOLD}║       monkey-sway installer              ║${NC}"
	echo -e "${BOLD}╚══════════════════════════════════════════╝${NC}"
	echo ""

	if [ "$OS" = "non-linux" ]; then
		warn "Current system is not Linux — monkey-sway is Wayland/Linux-only, skipping."
		exit 0
	fi

	info "Detected OS: ${CYAN}${OS}${NC}"
	info "monkey-sway: ${CYAN}${INSTALL_DIR}${NC}"
	echo ""

	setup_sudo
	echo ""

	install_sway
	echo ""

	clone_monkey_sway
	echo ""

	run_checkhealth
	echo ""

	write_tty_autostart sway sway
	echo ""

	setup_symlinks
	echo ""

	cleanup_sudo

	echo -e "${GREEN}${BOLD}monkey-sway installation complete!${NC}"
	echo ""
	echo -e "  Config: ${CYAN}$INSTALL_DIR${NC} → ${CYAN}~/.config/sway + ~/.config/waybar${NC}"
	echo -e "  Start sway from a TTY (never under sudo/root): ${CYAN}sway${NC}"
	if [ -n "$AUTOSTART_FILES" ]; then
		echo -e "  Autostart: a VT login execs ${CYAN}sway${NC} unless sway is already running (block in:${CYAN}$AUTOSTART_FILES${NC})"
	fi
	echo -e "  Update: ${CYAN}cd $INSTALL_DIR && git pull && swaymsg reload${NC}"
	echo ""
}

main "$@"
