# monkey-sway

## Introduction

The project monkey-sway is a clean, fast and vim-flavored Wayland desktop configuration.

**Features:**

| Feature             | Description                                                                                        |
| ------------------- | -------------------------------------------------------------------------------------------------- |
| Single config file  | Entire compositor config (look, input, autostart, keybindings, window rules) lives in one `config` |
| Sonokai theme       | Colors matched to the sonokai dark scheme                                                          |
| Vim-style bindings  | Focus / move / resize windows with `Super + Ctrl/Shift + h/j/k/l`                                  |
| Auto monitor detect | Monitors are auto-detected at their highest refresh rate; picture wallpaper via swaybg             |
| Laptop aware        | Touchpad natural scrolling and brightness keys work automatically on battery machines              |
| No animations       | Animations/blur/rounding are not configurable on sway by design; performance-first                 |
| waybar status bar   | Paired waybar config (workspaces, clock, tray, network, audio, battery)                            |
| sway-native tools   | swaybg / swayidle / swaylock / swaynag + bemenu, grim, wl-clipboard, wpctl                         |

## Key design decisions

| Hyprland feature            | Sway equivalent / note                                                                                |
| --------------------------- | ----------------------------------------------------------------------------------------------------- |
| `dwindle` layout            | tiling `splith` default; `Super+t` toggles split                                                      |
| Pseudo-tiling (`Super+p`)   | dropped (no sway equivalent)                                                                          |
| Special workspace "magic"   | sway scratchpad (`Super+s` show, `Super+Shift+s` move to scratchpad)                                  |
| `Super+[` / `]` monitor cyc | `focus output left` / `right` (spatial; no cycle prev/next in sway)                                   |
| Rounded corners / blur      | not supported by sway                                                                                 |
| Per-window opacity          | sway has only static `opacity`, so the terminal 0.95 rule is dropped                                  |
| Supress-maximize rule       | not needed on sway                                                                                    |
| 3-finger touchpad swipe     | skipped (sway ≥ 1.10 _does_ support `bindgesture swipe:left workspace next`, add it back if you want) |
| `Super+Shift+hjkl` resize   | `resize shrink \| grow width \| height 20px`, plus a dedicated `Super+r` resize mode                  |
| `Super+Shift+e` exit        | `swaynag` confirmation dialog before `swaymsg exit`                                                   |
| hyprlock / hypridle         | swaylock (sonokai colors) + swayidle (auto-lock after 5 min, dpms off)                                |
| xdg-desktop-portal-hyprland | xdg-desktop-portal-wlr                                                                                |
| hyprpolkitagent             | polkit-gnome-authentication-agent-1                                                                   |
| hyprpaper                   | `output * bg` wallpaper image (swaybg auto-spawned)                                                   |

## Requirements

- Sway (i3-compatible config; the bundled config uses only core commands)
- waybar
- A Wayland session (Wayland-only; no X11 fallback)

## Installation

### 1. Install dependencies

`install.sh` and `checkhealth.sh --install` install these automatically (apt/zypper/dnf/pacman). The table below documents what gets checked and why:

| Tool                                        | Purpose                                                       | Required |
| ------------------------------------------- | ------------------------------------------------------------- | -------- |
| sway                                        | The compositor (ships swaymsg / swaybar / swaynag)            | Yes      |
| swaybg                                      | Wallpaper (auto-spawned by `output * bg`)                     | Yes      |
| swayidle                                    | Idle daemon (auto lock + dpms off)                            | Yes      |
| swaylock                                    | Screen locker (`Super+Escape`)                                | Yes      |
| swaynag                                     | Exit confirmation dialog (`Super+Shift+e`)                    | Yes      |
| [waybar](https://github.com/Alexays/Waybar) | Status bar                                                    | Yes      |
| wezterm                                     | Default terminal emulator (`Super+Enter`)                     | Yes      |
| bemenu                                      | Application launcher (`Super+d`, `bemenu-run`)                | Yes      |
| grim + slurp                                | Screenshot region (`Super+,`) / full screen (`Super+Shift+,`) | Yes      |
| wl-clipboard (`wl-copy`)                    | Screenshots pipe to the clipboard                             | Yes      |
| wireplumber (`wpctl`)                       | Volume / mute keys and waybar audio module                    | Yes      |
| mako                                        | Notification daemon (waybar notification backend)             | Yes      |
| xdg-desktop-portal-wlr                      | Screen capture / screen sharing portal backend                | Yes      |
| xdg-desktop-portal-gtk                      | File chooser portal for GTK/Flatpak apps                      | Yes      |
| polkit-gnome                                | Polkit authentication agent for GUI privilege prompts         | Yes      |

#### Recommended tools

| Tool                 | Purpose                                    | Required    |
| -------------------- | ------------------------------------------ | ----------- |
| nm-applet            | Tray network manager applet (auto-started) | Recommended |
| brightnessctl        | Brightness keys                            | Recommended |
| pavucontrol          | Audio mixer (waybar pulseaudio click)      | Recommended |
| nm-connection-editor | Network settings (waybar network click)    | Recommended |
| gnome-calendar       | Calendar (waybar clock right-click)        | Optional    |
| hyprpicker           | Color picker                               | Optional    |
| wlsunset             | Color temperature                          | Optional    |

```bash
# Arch
sudo pacman -S sway swaybg swayidle swaylock waybar bemenu grim slurp wl-clipboard \
    wireplumber mako xdg-desktop-portal-wlr xdg-desktop-portal-gtk polkit-gnome \
    network-manager-applet brightnessctl pavucontrol nm-connection-editor gnome-calendar \
    wlsunset hyprpicker
# wezterm: https://wezterm.org/installation (or: sudo pacman -S wezterm)

# Debian (openSUSE/DNF analogous; package names may differ, e.g. polkit-gnome)
sudo apt-get install sway swaybg swayidle swaylock waybar bemenu grim slurp wl-clipboard \
    wireplumber mako xdg-desktop-portal-wlr xdg-desktop-portal-gtk polkit-gnome \
    network-manager-gnome brightnessctl pavucontrol nm-connection-editor gnome-calendar
```

#### Environment variables (single-file note)

sway cannot export environment variables from its config. The recommended variables
(Qt/GTK/Electron Wayland hints, `XDG_CURRENT_DESKTOP=sway`, etc.) are listed as a
comment block at the top of `config`. Two ways to apply them:

- **TTY launch** (recommended): add the `export` lines to your shell rc before `exec sway`.
- **systemd-managed session / display manager**: put the same `K=V` lines into
  `~/.config/environment.d/90-monkey-sway.conf`.

### 2. Health check

```bash
./checkhealth.sh          # report only
./checkhealth.sh --install  # auto-install what's missing (apt/zypper/dnf/pacman)
```

### 3. Install monkey-sway

One-liner (installs deps, clones this repo and links the configs):

```bash
curl -fsSL https://raw.githubusercontent.com/QMonkey/monkey-sway/master/install.sh | bash
```

The installer also writes a **guarded autostart block** to your shell profile files (`~/.zprofile` for zsh; `~/.bash_profile` or `~/.profile` plus `~/.bashrc` for bash):

```bash
# monkey-sway autostart (remove these lines to disable)
# Keep this block ABOVE any "exec tmux" auto-start block: on a bare TTY
# exec replaces the login shell with the compositor, so the tmux
# auto-start line is never reached and the desktop never runs inside a
# tmux pane. Inside a desktop terminal the env guards short-circuit and
# the tmux auto-start runs normally.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
    case "$(tty 2>/dev/null)" in
    /dev/tty[0-9]*) pgrep -x sway >/dev/null 2>&1 || exec sway ;;
    esac
fi
```

> If the install was chained from an outer meta-installer, its terminal-activation step may `source` your rc file right after the install — on a bare-TTY bash machine (where `.bash_profile` sources `.bashrc`) this can start the compositor immediately.

Prefer manual setup? Clone and link:

```bash
git clone https://github.com/QMonkey/monkey-sway.git
cd monkey-sway
mkdir -p ~/.config/sway
ln -sfn $(pwd)/config ~/.config/sway/config
ln -sfn $(pwd)/pictures ~/.config/sway/pictures
ln -sfn $(pwd)/waybar ~/.config/waybar
```

Then start (or restart) sway. waybar, mako, the polkit agent and nm-applet are
launched automatically on startup. The `pictures` link is required — the
wallpaper in the config is referenced as `~/.config/sway/pictures/...`.

### 4. Start sway

#### From a TTY (manual)

Log in on a TTY, make sure you are not root, and run `sway`. Never run it under
`sudo`/`root`. If the session ends (Super+Shift+e) you are dropped back to the TTY.

#### Alongside an existing desktop (display manager)

If another desktop environment is already installed (started by GDM, SDDM, etc.), there are two ways to get into sway:

**Via the display manager** — log out to the login screen and pick sway from the session menu. sway ships its own desktop entry in `/usr/share/wayland-sessions/`; if it is missing, create it:

```ini
# /usr/share/wayland-sessions/sway.desktop
[Desktop Entry]
Name=Sway
Comment=i3-compatible Wayland compositor
Exec=sway
Type=Application
```

**From a TTY** (recommended when the DM handles non-default sessions poorly) — log out (the DM returns to its greeter on its own VT), switch to a free virtual console (`Ctrl+Alt+F2`~`F6`), log in and launch sway directly:

```bash
sway
```

No need to stop the display manager: logind hands the seat (DRM master + input devices) to whichever VT session is active, and the parked greeter is harmless. Optionally stop it first (`sudo systemctl stop display-manager`) to free its resources; this is a per-boot change and the DM comes back on reboot (`sudo systemctl disable display-manager.service` makes TTY launch permanent).

> Stopping the DM terminates every session it manages — save unsaved work first.

**Multiple desktops coexist by design.** logind arbitrates the seat per session (fast-user-switching), so an X11 desktop from the DM, sway, and Hyprland can all live on different VTs at once — switch between them with Ctrl+Alt+FN. Trade-offs worth knowing:

- Clipboards do not cross session boundaries — each graphical session owns its selections.
- Both sessions pay memory/GPU while alive.
- NVIDIA proprietary drivers remain the fragile exception for VT switching; AMD/Intel are unaffected.
- Duplicate instances of the _same_ compositor are still blocked: the autostart guard's `pgrep -x sway` enforces a single sway. Once it is running, tty logins on other VTs fall through to a plain console shell — your escape hatch instead of a second compositor.

#### Auto-start on boot

`install.sh` writes the block below into your shell profile files (see §3 for the exact file set). To add it manually:

Add the following to the profile (`~/.zprofile` for zsh, `~/.bash_profile`/`~/.profile` + `~/.bashrc` for bash):

```bash
# monkey-sway autostart (remove these lines to disable)
# Keep this block ABOVE any "exec tmux" auto-start block: on a bare TTY
# exec replaces the login shell with the compositor, so the tmux
# auto-start line is never reached and the desktop never runs inside a
# tmux pane. Inside a desktop terminal the env guards short-circuit and
# the tmux auto-start runs normally.
if [ -z "${WAYLAND_DISPLAY:-}" ] && [ -z "${DISPLAY:-}" ]; then
    case "$(tty 2>/dev/null)" in
    /dev/tty[0-9]*) pgrep -x sway >/dev/null 2>&1 || exec sway ;;
    esac
fi
```

- Guards run cheapest-first: inside a desktop terminal or tmux pane the `$WAYLAND_DISPLAY`/`$DISPLAY` check short-circuits with zero forks; `tty` then excludes ssh (`/dev/pts/N`), tmux panes and desktop terminals in one check — immune to inherited environment (unlike `XDG_VTNR`, which a TTY-started tmux server passes down to its panes); `pgrep` enforces the single-instance policy last.
- Once sway runs, tty logins on other VTs give a plain console shell — the escape hatch. Before that, logging in on any VT starts it.
- `exec` replaces the shell, so logging out of sway returns to the login prompt.

##### Ordering: this block MUST run before any `exec tmux` auto-start block

An `exec tmux` auto-start block may live in the same profile files. `exec` replaces the shell process and the matching guard wins, so the relative order decides who owns a bare TTY:

- **Compositor first (correct)**: a TTY login exec's straight into sway — the `exec tmux` line is never reached, the desktop never lives inside a tmux pane, and a tmux server restart (`tmux kill-server`, config upgrades) can never take the session down. Inside the desktop, each terminal spawns a fresh shell: the env guards short-circuit the compositor block, and `exec tmux` starts the server with the desktop environment as its baseline — new tmux panes inherit `WAYLAND_DISPLAY`/`XDG_CURRENT_DESKTOP`, so `wl-clipboard`, portals and desktop detection all work.
- **tmux first (not so good)**: this case mainly applies to machines that do not auto-start a desktop environment — sway is launched manually on demand from a TTY. There a TTY login lands in tmux instead; the server's baseline environment is the TTY's, so panes opened later from the desktop lack `WAYLAND_DISPLAY` (wl-clipboard etc. break), and starting the compositor from a pane couples the graphical session to the tmux server — see the next section. On machines where the auto-start block above is in place, a TTY login exec's straight into the compositor and never reaches the tmux block, so this ordering issue does not arise.

The block only needs to end up above the tmux auto-start block. When installed via the meta-installer, the compositor is installed before tmux, so the appended blocks naturally land in the right order. For manual setups, paste the compositor block above the tmux block in the same file.

#### Starting sway from inside tmux

With the ordering rule above in place, a TTY login never reaches tmux — the scenarios below only apply when you deliberately start the compositor from inside a tmux pane (e.g. a TTY where you attached manually).

If tmux auto-starts on shell login (e.g. from your shell rc), you may land in
tmux first on a bare TTY — and if you then start sway (manually or via the
auto-start block above), the compositor runs inside a tmux pane with the tmux
server as its ancestor. Restarting the tmux server (`tmux kill-server`, config
upgrades, etc.) tears down every pane process with it, taking the desktop down
with the session.

Whether sway survives a server restart depends on how it was launched
(verified empirically):

| Launch command  | Survives `tmux kill-server`?                                 |
| --------------- | ------------------------------------------------------------ |
| `sway`          | No                                                           |
| `sway &`        | No — the pane shell forwards SIGHUP to its jobs when it dies |
| `nohup sway &`  | Yes                                                          |
| `setsid sway &` | Yes (recommended)                                            |

- `nohup ... &` makes the process ignore SIGHUP; output is redirected to
  `nohup.out`.
- `setsid ... &` is the most robust: the process moves into a brand-new
  session with no controlling terminal at all, so no HUP can ever reach it.

`setsid sway &` keeps the officially recommended "run it directly" semantics
intact — logind still hands over the seat; only HUP immunity is added. Two
things to know:

- The desktop inherits the environment of the tmux pane it was started from.
- Exiting sway (Super+Shift+e) drops you back into the tmux pane's shell
  prompt rather than the login prompt, because the `exec` in the auto-start
  block no longer applies.

### 5. Update project

```bash
cd monkey-sway
git pull
```

Reload with `swaymsg reload` (or restart sway) and restart waybar for bar changes.

## Keybindings

```text
The "Super" key below means the Windows/Command key.
```

### 1. Window management

#### Focus / Move / Resize (vim-style)

```text
Super+h / Super+j / Super+k / Super+l     Focus left / down / up / right
Super+Ctrl+h/j/k/l                        Move window left / down / up / right
Super+Shift+h/j/k/l                       Resize window (20px step)
Super+r                                   Enter resize mode (h/j/k/l, arrows; Esc/Return to leave)
```

Arrow key alternatives exist for all of the above (`Super`, `Super+Ctrl`, `Super+Shift` + arrow keys).

#### Actions

```text
Super+c        Close window
Super+v        Toggle floating
Super+t        Toggle split layout
Super+f        Fullscreen
Super+Ctrl+p   Pin window (sticky, stays on all workspaces of this output)
```

#### Mouse

```text
Super+left button     (hold) drag floating window     (from anywhere: `floating_modifier`)
Super+right button    (hold) resize floating window
Super+scroll          Switch workspace (down = next, up = previous)
```

### 2. Workspaces

```text
Super+1~9             Switch to workspace 1~9
Super+Shift+1~9       Move active window to workspace 1~9
Super+s               Show scratchpad (sway equivalent of "magic"; press again to cycle)
Super+Shift+s         Move active window to scratchpad
Super+[               Focus output to the left
Super+]               Focus output to the right
Super+Shift+[         Move window to left output
Super+Shift+]         Move window to right output
```

### 3. Applications & system

```text
Super+Return          Terminal (wezterm)
Super+d               Application launcher (bemenu-run)
Super+Escape          Lock screen (swaylock)
Super+Shift+e         Exit sway (swaynag confirmation)
```

### 4. Media & brightness keys

```text
XF86AudioRaiseVolume   Volume up 5% (capped at 150% by default; tune `$vol_cap`)
XF86AudioLowerVolume   Volume down 5%
XF86AudioMute          Toggle sink mute
XF86AudioMicMute       Toggle microphone mute
XF86MonBrightnessUp    Brightness up 5%
XF86MonBrightnessDown  Brightness down 5%
```

### 5. Screenshots

```text
Super+,          Select a region with slurp, screenshot with grim, copy to clipboard
Super+Shift+,    Screenshot the full screen, copy to clipboard
```

> Note: the upstream config this was ported from bound the bare `,` key for
> screenshots instead of `Super+,` in its lua file (its README documented
> `Super+,`); monkey-sway follows the documented `Super+,` behavior.

## Window rules

- Utility apps (calculator, pavucontrol, settings dialogs, etc.) open floating and centered — see the `for_window` list in `config`
- `Picture-in-Picture` windows float and stay pinned to the output (`sticky`)
- Blank XWayland drag shadows (`class`/`title` empty) are never auto-focused
- sway has no per-window opacity/blur/rounding, so the Hyprland decoration rules are dropped

## Laptop extras

The config detects nothing explicitly — natural scrolling is enabled on all
touchpads and brightness keys are always bound (harmless on desktops). No manual
setup is needed.

## waybar

```text
modules-left:    sway/workspaces  (click to activate, scroll to switch)
modules-center:  clock            (click for full date, right-click gnome-calendar)
modules-right:   tray, network, pulseaudio, battery
```

- Exit is `Super+Shift+e` (swaynag), so there is no power module
- Battery warning (30%) / critical (15%) states; hidden on desktops without a battery
- Same sonokai palette as `config`

## Precautions

- **Single-file config** — the sway config is one file; edit `config` and `swaymsg reload`
- **Resize step** — `$resize_step` (default `20px`) controls both direct resize and the `Super+r` mode
- **`$lock`** — swaylock options are inlined in `config` so keep the whole string on reload
- **Window-rule case** — sway criteria are case-sensitive and split between `app_id`
  (Wayland-native) and `class` (XWayland); both rules are emitted, non-matches are silent
- **Path differences** — `polkit-gnome-authentication-agent-1` and the `xdg-desktop-portal-*`
  backends are assumed under `/usr/lib` (Arch). On Fedora/Debian they live in `/usr/libexec`;
  adjust the `exec_always` lines in `config` if the autostart doesn't fire
