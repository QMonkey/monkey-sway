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
# No scripts/ next to this file: either a checkout predating the subtree
# commit (pull it in and carry on), a .git-less directory (zip/tarball),
# or `curl | bash`, which has no checkout at all. The latter two bootstrap
# through INSTALL_DIR and run the install.sh from that checkout, so
# installer and scripts/ always come from the same revision.
_monkey_scripts="$(dirname "${BASH_SOURCE[0]:-$0}")/scripts"
if [ ! -f "$_monkey_scripts/install.sh" ]; then
	_monkey_self="${BASH_SOURCE[0]:-$0}"
	_monkey_dir="$(dirname "$_monkey_self")"
	if [ -f "$_monkey_self" ] && [ -d "$_monkey_dir/.git" ]; then
		# Outdated checkout: update it in place and keep running from it.
		git -C "$_monkey_dir" pull --ff-only || true
		if [ ! -f "$_monkey_dir/scripts/install.sh" ]; then
			echo "monkey-scripts missing from $_monkey_dir (no scripts/ subtree)." >&2
			echo "  git -C $_monkey_dir pull    # outdated checkout — or the repo never added the subtree" >&2
			exit 1
		fi
		_monkey_scripts="$_monkey_dir/scripts"
	else
		# curl|bash or a .git-less directory: the only path to a
		# same-revision scripts/ is the INSTALL_DIR checkout.
		# clone_monkey_project cannot do this job — it lives in the very
		# scripts/ being fetched. INSTALL_DIR is where the framework's clone
		# step would have put the checkout too, so that step only confirms it.
		if [ -d "$INSTALL_DIR/.git" ]; then
			# An install already lives here: update it, then run that one.
			git -C "$INSTALL_DIR" pull --ff-only || true
		elif [ -d "$INSTALL_DIR" ] && [ -n "$(ls -A "$INSTALL_DIR")" ]; then
			# git clone would refuse too, so say why in our own words.
			echo "$INSTALL_DIR is not empty and is not a git clone." >&2
			echo "  move it aside, delete it, or set INSTALL_DIR elsewhere." >&2
			exit 1
		else
			# Fresh clone — the ONLY sub-branch where git is hard-required:
			# the pull sub-branch above degrades gracefully without it, and
			# a zip/tarball must not fail here just for a missing git.
			if ! command -v git >/dev/null 2>&1; then
				echo "git is required to clone $PROJECT — install it first (e.g. sudo apt-get install git), then re-run." >&2
				exit 1
			fi
			# No retry() available yet — the framework loads only after this
			# clone succeeds — so inline the standard 3 attempts. A failed
			# clone leaves a partial directory behind; remove it so the next
			# attempt cannot trip over "already exists". This branch only
			# runs on a fresh install (INSTALL_DIR did not exist or was
			# empty), so the rm can never delete pre-existing data.
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
# sway's links are reported with the full destination path and never
# re-created under an existing entry — that is the shared link_config's own
# behaviour (lib/config.sh), so the links are plain SYMLINKS data.
SYMLINKS=(
	"$INSTALL_DIR/config|$HOME/.config/sway/config"
	"$INSTALL_DIR/pictures|$HOME/.config/sway/pictures"
	"$INSTALL_DIR/waybar|$HOME/.config/waybar"
)

# ──────────────────────── project steps ────────────────────────

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
		# The WSL / non-Linux / no-KMS guards live in ensure_kmscon itself.
		if ensure_kmscon "$KMSCON_TTYS"; then
			KMSCON_DONE=1
		else
			warn "kmscon setup failed — continuing without it."
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
