# cmatrix-background

*[Read in English](README.md)*

Un script chico para X11 que abre una terminal transparente con el efecto "lluvia digital" de [`cmatrix`](https://github.com/abishekvashok/cmatrix) pegado atrás, a modo de fondo. Movés, redimensionás, minimizás, maximizás o enfocás la terminal y el efecto matrix la sigue automáticamente, como si la terminal fuera transparente de verdad.

Es enteramente por eventos (sin bucle de sondeo), así que queda en ~0% de CPU en reposo y reacciona al instante ante eventos de X11.

## Vista previa

Adelante: una terminal normal, totalmente usable, semitransparente (`alacritty`).
Atrás: un `xterm` sin bordes corriendo `cmatrix`, sincronizado perfectamente en posición, tamaño y orden de apilado con la ventana de adelante.

## Requisitos

Debian/Ubuntu:

```bash
sudo apt install xterm alacritty wmctrl xdotool x11-utils cmatrix
```

- `xterm` — aloja la ventana de fondo con `cmatrix`.
- `alacritty` — la terminal transparente real y usable, adelante.
- `wmctrl`, `xdotool` — reposicionan/redimensionan/reordenan la ventana de fondo.
- `xev`, `xprop` (de `x11-utils`) — escuchan eventos de mover/redimensionar/enfocar/maximizar en vez de sondear en un bucle.
- `cmatrix` — el efecto de lluvia digital en sí.

Funciona en X11 (o XWayland). El script fuerza a `alacritty` a salir de Wayland nativo (`env -u WAYLAND_DISPLAY`) porque necesita consultar/mover la ventana con herramientas de X11.

## Uso

```bash
./cmatrix-bg.sh [opacidad]
```

- `opacidad` (opcional): transparencia de la terminal de adelante, `0.0`–`1.0`. Por defecto `0.55`.

```bash
./cmatrix-bg.sh          # opacidad por defecto
./cmatrix-bg.sh 0.4      # más transparente
```

Cerrá la ventana de adelante (la transparente) para terminar todo — la ventana de fondo y todos los procesos auxiliares se limpian automáticamente.

## Asignarlo a un atajo de teclado

Una buena forma de usarlo es reemplazar el atajo "abrir terminal" por defecto del escritorio con este script. En GNOME:

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys terminal "[]"
```

Después agregá un atajo personalizado (Configuración → Teclado → Atajos personalizados) que ejecute:

```bash
bash -c '/ruta/a/cmatrix-bg.sh >/dev/null 2>&1'
```

asignado a la combinación de teclas que prefieras (por ejemplo `Ctrl+Alt+T`).

## Usar otra cosa en vez de `cmatrix`

La ventana de fondo no tiene por qué correr `cmatrix` — cambiá la línea `xterm ... -e cmatrix` cerca del principio del script por cualquier otro programa de terminal que quieras tener corriendo detrás de tu terminal real (por ejemplo `-e htop`, `-e /algun/script-de-animacion.sh`, `-e neofetch --loop`, etc). Todo lo demás (posición, foco, orden de apilado) sigue funcionando igual.

### Bonus: `ghost-bg.sh` — el fantasma de Ghostty como fondo

`ghost-bg.sh` es un ejemplo ya armado de justo eso: el mismo script, pero en vez de `cmatrix` muestra la mascota fantasma de [Ghostty](https://ghostty.org) renderizada como arte ANSI con [`chafa`](https://hpjansson.org/chafa/).

```bash
sudo apt install chafa
./ghost-bg.sh
```

- `ghost-ansi.sh` dibuja `assets/ghost.png` ocupando toda la terminal con `chafa`, y solo la vuelve a dibujar cuando la terminal realmente cambia de tamaño (`SIGWINCH` — la misma señal que el kernel ya manda en cada resize de una pty, sin agregar sondeo).
- El arte del fantasma (`assets/ghost.png`) es del [proyecto Ghostty](https://ghostty.org), incluido acá solo para este efecto hecho por fan — todo el crédito es de ellos.

## Cómo funciona (versión corta)

- Dos ventanas independientes: la terminal real adelante, un `xterm` decorativo atrás.
- Un listener de `xev` reacciona a `ConfigureNotify` (mover/redimensionar), `UnmapNotify`/`MapNotify` (minimizar/restaurar) y `FocusIn` en la ventana de adelante.
- Un listener de `xprop -spy` sigue el estado de maximizado por separado, para que el manejador de movimiento nunca tenga que forkear `xprop` en cada pixel de un arrastre.
- Al enfocarse, la ventana de adelante se trae de vuelta por encima de lo que la tape (junto con la de atrás) usando `wmctrl -a` — un simple `xdotool windowraise` es ignorado en silencio por gestores de ventanas con protección anti robo-de-foco (como Mutter/GNOME) cuando lo pide una ventana sin foco.

## Ajustes

Algunas constantes cerca del principio del script pueden necesitar recalibrarse según tu equipo:

- `OFFSET_X` / `OFFSET_Y` — desfase en píxeles entre las dos ventanas para que el fondo coincida exactamente con el área de contenido de la de adelante (varía según sistema/tema).
- `OFFSET_X_MAX` / `OFFSET_Y_MAX` — desfase usado mientras está maximizada.
- `MONITOR3_X_MIN` — se usa para elegir un desfase de maximizado distinto en monitores muy anchos o de alta densidad de píxeles.

## Licencia

Dominio público / hacé lo que quieras con esto.
