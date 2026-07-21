# terminal-backdrop

*[Read in English](README.md)*

Un script chico para X11 que abre una terminal transparente con **cualquier efecto de terminal en vivo** pegado atrás, a modo de fondo — la lluvia digital de [`cmatrix`](https://github.com/abishekvashok/cmatrix) por defecto, pero funciona con prácticamente cualquier programa de terminal (ver [Usar otra cosa en vez de `cmatrix`](#usar-otra-cosa-en-vez-de-cmatrix) más abajo). Movés, redimensionás, minimizás, maximizás o enfocás la terminal y el efecto de fondo la sigue automáticamente, como si la terminal fuera transparente de verdad.

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
- `xev`, `xprop`, `xwininfo` (de `x11-utils`) — escuchan eventos de mover/redimensionar/enfocar/maximizar en vez de sondear en un bucle, y miden el tamaño real de decoración de cada ventana para autoalinearse.
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

### Bonus: `ghost-bg.sh` — el fantasma animado de Ghostty como fondo

`ghost-bg.sh` es un ejemplo ya armado de justo eso: el mismo script, pero en vez de `cmatrix` reproduce, de fondo, la animación del fantasma que aparece en la home de [Ghostty](https://ghostty.org).

```bash
./ghost-bg.sh
```

No hace falta instalar nada aparte — `ghost-ansi.sh` solo imprime cuadros pregrabados (`assets/ghost-frames.txt.gz`) en bucle, con códigos ANSI comunes.

- Los 235 cuadros de la animación son los datos *reales* que la home de Ghostty le manda al navegador para dibujar ese fantasma (los encontré incrustados en la página como grillas de texto plano) — el mismo arte, la misma animación, solo que reproducida en una terminal real en vez de un bloque `<code>` del navegador.
- Los datos originales no tienen color, solo un flag de negrita (`<span class="b">`) — el degradé de color (de teal oscuro a celeste brillante bien vivo, según la densidad visual de cada carácter) es un agregado mío, no de Ghostty.
- La animación queda centrada automáticamente en la terminal (es una grilla fija de 100×41), y se recentra si redimensionás.
- La velocidad de reproducción (`FRAME_DELAY` en `ghost-ansi.sh`) es una aproximación mía — el FPS original vive en el JS compilado de Ghostty, no en los datos de los cuadros en sí. Ajustalo si se siente mal.
- Este arte y esta animación son del [proyecto Ghostty](https://ghostty.org), extraídos acá solo para este efecto hecho por fan — todo el crédito es de ellos.

## Cómo funciona (versión corta)

- Dos ventanas independientes: la terminal real adelante, un `xterm` decorativo atrás.
- Un listener de `xev` reacciona a `ConfigureNotify` (mover/redimensionar), `UnmapNotify`/`MapNotify` (minimizar/restaurar) y `FocusIn` en la ventana de adelante.
- Un listener de `xprop -spy` sigue el estado de maximizado por separado, para que el manejador de movimiento nunca tenga que forkear `xprop` en cada pixel de un arrastre.
- Al enfocarse, la ventana de adelante se trae de vuelta por encima de lo que la tape (junto con la de atrás) usando `wmctrl -a` — un simple `xdotool windowraise` es ignorado en silencio por gestores de ventanas con protección anti robo-de-foco (como Mutter/GNOME) cuando lo pide una ventana sin foco.

## Ajustes

El desfase en píxeles entre las dos ventanas (necesario porque la ventana de fondo sin bordes y la de adelante con decoraciones se renderizan levemente distinto según sistema/tema/monitor) ya no es una constante calibrada a mano — el script lo mide solo al arrancar, comparando la geometría real que reportan ambas ventanas, y lo vuelve a medir por monitor la primera vez que maximizás en cada pantalla. No hay nada que recalibrar manualmente, y se adapta automáticamente a cualquier cantidad de monitores.

## Licencia

Dominio público / hacé lo que quieras con esto.
