# cmatrix-background

*[Leer en español](README.es.md)*

A small X11 script that opens a transparent terminal with a live [`cmatrix`](https://github.com/abishekvashok/cmatrix) "digital rain" effect glued to it as a background. Move, resize, minimize, maximize or focus the terminal and the matrix effect follows it automatically — as if your terminal were see-through.

It's event-driven (no polling loop), so it sits at ~0% CPU while idle and reacts instantly via X11 events.

## Preview

Front: a normal, fully usable, semi-transparent terminal (`alacritty`).
Back: a borderless `xterm` running `cmatrix`, perfectly synced to the front window's position, size, and stacking order.

## Requirements

Debian/Ubuntu:

```bash
sudo apt install xterm alacritty wmctrl xdotool x11-utils cmatrix
```

- `xterm` — hosts the `cmatrix` background window.
- `alacritty` — the actual, usable transparent terminal in front.
- `wmctrl`, `xdotool` — reposition/resize/restack the background window.
- `xev`, `xprop` (from `x11-utils`) — listen for window move/resize/focus/maximize events instead of polling.
- `cmatrix` — the digital rain effect itself.

Works on X11 (or XWayland). The script forces `alacritty` off native Wayland (`env -u WAYLAND_DISPLAY`) since it needs to query/move the window with X11 tools.

## Usage

```bash
./cmatrix-bg.sh [opacity]
```

- `opacity` (optional): front terminal transparency, `0.0`–`1.0`. Default `0.55`.

```bash
./cmatrix-bg.sh          # default opacity
./cmatrix-bg.sh 0.4      # more transparent
```

Close the front (transparent) window to end everything — the background window and all helper processes are cleaned up automatically.

## Bind it to a keyboard shortcut

A nice way to use this is to replace your desktop's default "open terminal" shortcut with it. On GNOME:

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]"
```

Then add a custom shortcut (Settings → Keyboard → Custom Shortcuts) running:

```bash
bash -c '/path/to/cmatrix-bg.sh >/dev/null 2>&1'
```

bound to whatever key combo you like (e.g. `Ctrl+Alt+T`).

## Using something other than `cmatrix`

The background window doesn't have to run `cmatrix` — swap the `xterm ... -e cmatrix` line near the top of the script for any other terminal program you want running behind your real terminal (e.g. `-e htop`, `-e /some/animation.sh`, `-e neofetch --loop`, etc). Everything else (positioning, focus, stacking) keeps working the same way.

### Bonus: `ghost-bg.sh` — Ghostty's ghost as the background

`ghost-bg.sh` is a ready-to-run example of exactly that: same script, but instead of `cmatrix` it shows [Ghostty](https://ghostty.org)'s ghost mascot rendered as ANSI art with [`chafa`](https://hpjansson.org/chafa/).

```bash
sudo apt install chafa
./ghost-bg.sh
```

- `ghost-ansi.sh` draws `assets/ghost.png` full-screen with `chafa` and only redraws on an actual terminal resize (`SIGWINCH` — the same signal the kernel already sends on every pty resize, no polling added).
- The ghost artwork (`assets/ghost.png`) belongs to the [Ghostty project](https://ghostty.org), included here just for this fan-made effect — all credit to them.

## How it works (short version)

- Two independent top-level windows: the real terminal in front, a decorative `xterm` behind.
- An `xev` listener reacts to `ConfigureNotify` (move/resize), `UnmapNotify`/`MapNotify` (minimize/restore) and `FocusIn` on the front window.
- An `xprop -spy` listener tracks maximize/restore state separately, so the move handler never has to fork `xprop` on every pixel of a drag.
- On focus, the front window is brought back above anything covering it (and the background window along with it) using `wmctrl -a` — plain `xdotool windowraise` gets silently ignored by window managers with focus-stealing prevention (e.g. Mutter/GNOME) when requested by an unfocused window.

## Tuning

A few constants near the top of the script may need recalibrating for your setup:

- `OFFSET_X` / `OFFSET_Y` — pixel offset between the two windows so the background exactly matches the front window's content area (varies per system/theme).
- `OFFSET_X_MAX` / `OFFSET_Y_MAX` — offset used while maximized.
- `MONITOR3_X_MIN` — used to pick a different maximized offset on very wide/high-DPI monitors.

## License

Public domain / do whatever you want with it.
