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
#
# The shared installer (sudo, packages, clone, checkhealth, symlinks,
# completion) lives in scripts/ — a `git subtree` of
# github.com/QMonkey/monkey-scripts. On the curl|bash path there is no
# checkout at all, so install.sh clones THIS repo and runs the copy of
# install.sh inside it — that copy carries its own scripts/, so the
# installer and the framework it loads are always the same revision.
# ──────────────────────────────────────────────────────────────

# ──────────────────────── repository identity ────────────────────────
# Declared before the framework is sourced: the bootstrap below needs both
# values, and clones into the very directory clone_monkey_project would
# have used — one clone per run, not two.
PROJECT=monkey-sway
PROJECT_REPO=https://github.com/QMonkey/monkey-sway.git
INSTALL_DIR="${INSTALL_DIR:-$HOME/Documents/monkey-sway}"

# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on) or `curl | bash`, which has no checkout
# at all. The latter clones THIS project and runs the install.sh from that
# checkout, so installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		git -C "$_monkey_dir" pull --ff-only || true
		_monkey_scripts="$_monkey_dir/scripts"
		if [ ! -f "$_monkey_scripts/install.sh" ]; then
			echo "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			echo "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
	else
		# curl|bash: no checkout at all. Get one that carries scripts/ and
		# hand over to its installer, so install.sh and scripts/ can never be
		# different revisions. clone_monkey_project cannot do this job — it
		# lives in the very scripts/ being fetched. INSTALL_DIR is where the
		# framework's clone step would have put the checkout too, so that step
		# only confirms it.

		if ! command -v git >/dev/null 2>&1; then
			echo "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
			exit 1
		fi
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# No retry() available yet — the framework loads only after this
		# clone succeeds — so inline the standard 3 attempts. A failed clone
		# leaves a partial directory behind; remove it so the next attempt
		# cannot trip over "already exists". This branch only runs on a
		# fresh install (INSTALL_DIR did not exist or was empty), so the rm
		# can never delete pre-existing data.
		_monkey_rc=1
		for _monkey_attempt in 1 2 3; do
			if git clone "$PROJECT_REPO" "$INSTALL_DIR"; then
				_monkey_rc=0
				break
			fi
			rm -rf "$INSTALL_DIR"
			if [ "$_monkey_attempt" -lt 3 ]; then
				sleep 2
			fi
		done
		[ "$_monkey_rc" -eq 0 ] || exit 1
		fi
		# </dev/null: on the curl|bash path stdin is the script pipe, and the
		# inner installer must not read what is left of the outer one.
		exec bash "$INSTALL_DIR/install.sh" "$@" </dev/null
	fi
fi
# shellcheck source=/dev/null
. "$_monkey_scripts/install.sh"

# ──────────────────────── layout & data ────────────────────────
LINUX_ONLY=1
FINISH_INJECT=0 # the original writes no TIOCSTI hint — just the summary
SUMMARY_LINES=(
	"  Config: ${CYAN}$INSTALL_DIR${NC} → ${CYAN}~/.config/sway (+pictures) + ~/.config/waybar${NC}"
	"  Start sway from a TTY (never under sudo/root): ${CYAN}sway${NC}"
	"  Update: ${CYAN}cd $INSTALL_DIR && git pull && swaymsg reload${NC}"
)

# ──────────────────────── project steps ────────────────────────

# Sway ships --needed semantics in the upstream installer: skip packages the
# system already has instead of re-installing them. Overrides the shared
# install_pkg for this script only (checkhealth.sh runs in its own process).
install_pkg() {
	refresh_pkg
	local rc=0
	case "$OS" in
	debian | ubuntu) retry -t 1800 -s "apt-get install" sudo_cmd apt-get install -y "$@" ;;
	arch) retry -t 1800 -s "pacman install" sudo_cmd pacman -S --needed --noconfirm "$@" ;;
	opensuse) retry -t 1800 -s "zypper install" sudo_cmd zypper --non-interactive install -y "$@" ;;
	centos)
		sudo_cmd dnf install -y epel-release || true
		retry -t 1800 -s "dnf install" sudo_cmd dnf install -y "$@"
		;;
	fedora)
		retry -t 1800 -s "dnf install" sudo_cmd dnf install -y "$@"
		;;
	*) rc=1 ;;
	esac || rc=$?
	hash -r
	return "$rc"
}

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

# A hook prints its own trailing blank line when it produced output; the
# upstream separates setup_sudo from the first step with its own blank.
install_step_prepare() {
	echo ""
	install_sway
	echo ""
}

# The compositor autostart line of the summary depends on what
# write_tty_autostart did — slot it in before "Update:".
install_step_autostart() {
	if [ -n "$KMSCON_TTYS" ]; then
		if is_wsl; then
			warn "WSL detected — skipping kmscon setup (no VT login)."
		else
			ensure_kmscon "$KMSCON_TTYS" || warn "kmscon setup failed — continuing without it."
			KMSCON_DONE=1
		fi
	fi
	write_tty_autostart sway sway
	echo ""
	if [ -n "$AUTOSTART_FILES" ]; then
		SUMMARY_LINES=(
			"${SUMMARY_LINES[0]}"
			"${SUMMARY_LINES[1]}"
			"  Autostart: a VT login execs ${CYAN}sway${NC} unless sway is already running (block in:${CYAN}$AUTOSTART_FILES${NC})"
			"${SUMMARY_LINES[2]}"
		)
	fi
	if [ -n "$KMSCON_DONE" ]; then
		SUMMARY_LINES=(
			"${SUMMARY_LINES[@]:0:${#SUMMARY_LINES[@]}-1}"
			"  kmscon: fallback console on ${CYAN}${KMSCON_TTYS}${NC} — switch with chvt N"
			"${SUMMARY_LINES[-1]}"
		)
	fi
}

# sway's links are reported with the full destination path and never
# re-created under an existing entry — the original's own helpers, kept
# verbatim (they override the shared setup_symlinks / link_config).
link_config() {
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

# ──────────────────────── optional kmscon takeover ────────────────────────
# --with-kmscon [tty[,tty...]] hands the listed VTs to kmscon (default
# tty2) and masks the matching getty instances — ensure_kmscon in
# scripts/lib/kmscon.sh does the work. The flag stays local to this
# installer: it is parsed out here and never reaches install_main. The
# parser runs in the current shell (a subshell would drop KMSCON_TTYS):
# it fills _INSTALL_ARGS directly instead of printing through a pipe.
parse_install_args() {
	KMSCON_TTYS=""
	KMSCON_DONE=""
	_INSTALL_ARGS=()
	while [[ $# -gt 0 ]]; do
		case "$1" in
		--with-kmscon)
			KMSCON_TTYS=tty2
			if [[ $# -gt 1 && "$2" != --* ]]; then
				KMSCON_TTYS=$2
				shift
			fi
			;;
		*) _INSTALL_ARGS+=("$1") ;;
		esac
		shift
	done
}

parse_install_args "$@"
install_main "${_INSTALL_ARGS[@]+"${_INSTALL_ARGS[@]}"}"
