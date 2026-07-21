# terminal-backdrop

*[Leer en español](README.es.md)*

A small X11 script that opens a transparent terminal with **any live terminal effect** glued to it as a background — [`cmatrix`](https://github.com/abishekvashok/cmatrix)'s digital rain by default, but really any terminal program works (see [Using something other than `cmatrix`](#using-something-other-than-cmatrix) below). Move, resize, minimize, maximize or focus the terminal and the background effect follows it automatically — as if your terminal were see-through.

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
- `xev`, `xprop`, `xwininfo` (from `x11-utils`) — listen for window move/resize/focus/maximize events instead of polling, and measure each window's real decoration size for auto-alignment.
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

### Bonus: `ghost-bg.sh` — Ghostty's animated ghost as the background

`ghost-bg.sh` is a ready-to-run example of exactly that: same script, but instead of `cmatrix` it plays the little ghost animation from the [Ghostty](https://ghostty.org) homepage in the background.

```bash
./ghost-bg.sh
```

No extra dependency needed — `ghost-ansi.sh` just prints pre-recorded frames (`assets/ghost-frames.txt.gz`) in a loop with plain ANSI codes.

- The 235 animation frames are the *actual* frame data Ghostty's homepage sends to the browser to draw that ghost (found embedded in its page as plain text grids) — same art, same animation, just played in a real terminal instead of a `<code>` block in the browser.
- The original data has no color, just a `<span class="b">` bold flag — the color gradient (dark teal to bright icy cyan, based on each character's visual density) is my own addition, not Ghostty's.
- The animation is automatically centered in the terminal (it's a fixed 100×41 grid), and re-centers on resize.
- The playback speed (`FRAME_DELAY` in `ghost-ansi.sh`) is a guess on my part — the original frame rate lives in Ghostty's compiled JS, not in the frame data itself. Tune it if it feels off.
- This artwork and animation belong to the [Ghostty project](https://ghostty.org), extracted here only for this fan-made effect — all credit to them.

## How it works (short version)

- Two independent top-level windows: the real terminal in front, a decorative `xterm` behind.
- An `xev` listener reacts to `ConfigureNotify` (move/resize), `UnmapNotify`/`MapNotify` (minimize/restore) and `FocusIn` on the front window.
- An `xprop -spy` listener tracks maximize/restore state separately, so the move handler never has to fork `xprop` on every pixel of a drag.
- On focus, the front window is brought back above anything covering it (and the background window along with it) using `wmctrl -a` — plain `xdotool windowraise` gets silently ignored by window managers with focus-stealing prevention (e.g. Mutter/GNOME) when requested by an unfocused window.

## Tuning

The pixel offset between the two windows (needed because the borderless background window and the decorated front window render slightly differently depending on system/theme/monitor) is no longer a hand-tuned constant — the script measures it itself at startup by comparing both windows' actual reported geometry, and re-measures it per-monitor the first time you maximize on each screen. Nothing to recalibrate manually, and it adapts automatically to any number of monitors.

## License

Public domain / do whatever you want with it.
