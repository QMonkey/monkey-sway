# monkey-sway

## Introduction

The project monkey-sway is a clean, fast and vim-flavored Wayland desktop configuration.

**Features:**

| Feature             | Description                                                                                        |
| ------------------- | -------------------------------------------------------------------------------------------------- |
| Single config file  | Entire compositor config (look, input, autostart, keybindings, window rules) lives in one `config` |
| Sonokai theme       | Colors matched to the sonokai dark scheme (same palette as monkey-vim)                             |
| Vim-style bindings  | Focus / move / resize windows with `Super + Ctrl/Shift + h/j/k/l`                                  |
| Auto monitor detect | Monitors are auto-detected at their highest refresh rate; solid-color wallpaper                    |
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
| `Super+Shift+hjkl` resize   | `resize shrink                                                                                        | grow width | height 20px`, plus a dedicated `Super+r` resize mode |
| `Super+Shift+e` exit        | `swaynag` confirmation dialog before `swaymsg exit`                                                   |
| hyprlock / hypridle         | swaylock (sonokai colors) + swayidle (auto-lock after 5 min, dpms off)                                |
| xdg-desktop-portal-hyprland | xdg-desktop-portal-wlr                                                                                |
| hyprpolkitagent             | polkit-gnome-authentication-agent-1                                                                   |
| hyprpaper                   | `output * bg` solid sonokai color (swaybg auto-spawned)                                               |

## Requirements

- Sway (i3-compatible config; the bundled config uses only core commands)
- waybar
- A Wayland session (Wayland-only; no X11 fallback)

## Installation

### 1. Install dependencies

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

```bash
cd monkey-sway
ln -sf $(pwd)/config ~/.config/sway/config
ln -sf $(pwd)/waybar ~/.config/waybar
```

Then start (or restart) sway. waybar, mako, the polkit agent and nm-applet are
launched automatically on startup.

### 4. Start sway

#### From a TTY (manual)

Log in on a TTY, make sure you are not root, and run `sway`. Never run it under
`sudo`/`root`. If the session ends (Super+Shift+e) you are dropped back to the TTY.

#### Auto-start on boot

Add the following to your shell rc (`~/.zshrc` or `~/.bashrc`):

```bash
# Start sway on tty1 login only, and only outside of an existing session
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec sway
fi
```

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

