#!/usr/bin/env bash
# Igual que cmatrix-bg.sh, pero de fondo en vez de "cmatrix" muestra el
# fantasma de Ghostty (https://ghostty.org) como arte ANSI (ver ghost-ansi.sh
# y assets/ghost.png). Al mover/redimensionar la de adelante, la de atrás la
# sigue automáticamente.
#
# Uso: ./ghost-bg.sh [opacidad 0.0-1.0]
#   ./ghost-bg.sh          # opacidad por defecto 0.55
#   ./ghost-bg.sh 0.4      # más transparente

set -uo pipefail

OPACITY="${1:-0.55}"
TAG=$$
BACK_TITLE="ghost-bg-$TAG"
FRONT_TITLE="ghost-front-$TAG"
SELF_DIR="$(dirname "$(readlink -f "$0")")"

# Posición inicial explícita e IGUAL para ambas ventanas: así ninguna
# depende del "cascade placement" del WM (que las abre en esquinas
# distintas) mientras arranca el bucle de sincronización.
START_X=250
START_Y=400

# Corrección empírica: en este equipo la ventana de atrás termina
# renderizada un poco más a la derecha y más abajo de lo que reportan
# wmctrl/xdotool, y el desfase cambia según el monitor y según si la
# ventana está maximizada o no. Calibrado a mano por pantalla.
# Monitor grande (x >= 3200) maximizado necesita un offset propio.
OFFSET_X=27
OFFSET_Y=63
OFFSET_X_MAX=3
OFFSET_Y_MAX=44
OFFSET_X_MAX_M3=-1
OFFSET_Y_MAX_M3=37
MONITOR3_X_MIN=3200

BACK_PID=""
FRONT_PID=""
EVENT_PID=""
XEV_PID=""
SPY_PID=""
SPY_SRC_PID=""
MAX_FLAG="/tmp/.ghost-max-$TAG"
XEV_FIFO="/tmp/.ghost-xev-$TAG"
SPY_FIFO="/tmp/.ghost-spy-$TAG"

# "cmd1 | cmd2 &" solo da el PID de cmd2 (el lector): cmd1 (xev/xprop -spy)
# queda huérfano si no se lo mata aparte. Por eso cada pipeline se arma con
# un FIFO en vez de un "|" directo, para poder guardar y matar los dos PIDs.
cleanup() {
    [[ -n "$EVENT_PID" ]] && kill "$EVENT_PID" 2>/dev/null
    [[ -n "$XEV_PID" ]] && kill "$XEV_PID" 2>/dev/null
    [[ -n "$SPY_PID" ]] && kill "$SPY_PID" 2>/dev/null
    [[ -n "$SPY_SRC_PID" ]] && kill "$SPY_SRC_PID" 2>/dev/null
    [[ -n "$BACK_PID" ]] && kill "$BACK_PID" 2>/dev/null
    [[ -n "$FRONT_PID" ]] && kill "$FRONT_PID" 2>/dev/null
    rm -f "$MAX_FLAG" "$XEV_FIFO" "$SPY_FIFO"
}
trap cleanup EXIT INT TERM

for bin in xterm alacritty wmctrl xdotool xev chafa; do
    command -v "$bin" >/dev/null || { echo "Falta '$bin'. Instalalo con: sudo apt install $bin" >&2; exit 1; }
done

# Ventana de atrás: el fantasma de Ghostty en ANSI, en xterm (X11 nativo).
xterm -title "$BACK_TITLE" -bg black -geometry "+$((START_X-OFFSET_X))+$((START_Y-OFFSET_Y))" -e "$SELF_DIR/ghost-ansi.sh" &
BACK_PID=$!

# Ventana de adelante: shell normal, forzada a X11 (para poder moverla/medirla)
# y con opacidad real para dejar ver al fantasma detrás.
env -u WAYLAND_DISPLAY alacritty \
    -o "window.opacity=$OPACITY" \
    -o "window.position.x=$START_X" \
    -o "window.position.y=$START_Y" \
    --title "$FRONT_TITLE" &
FRONT_PID=$!

find_wid() {
    local title="$1" hexid=""
    for _ in $(seq 1 50); do
        hexid=$(wmctrl -l | awk -v t="$title" '$0 ~ t {print $1; exit}')
        if [[ -n "$hexid" ]]; then
            printf "%d\n" "$hexid"
            return 0
        fi
        sleep 0.1
    done
    return 1
}

BACK_WID=$(find_wid "$BACK_TITLE") || { echo "No encontré la ventana de fondo" >&2; exit 1; }
FRONT_WID=$(find_wid "$FRONT_TITLE") || { echo "No encontré la ventana de adelante" >&2; exit 1; }

# Sacarle la barra de título/bordes a la de atrás para que su geometría
# coincida exactamente con el área de contenido de la de adelante.
xprop -id "$BACK_WID" -f _MOTIF_WM_HINTS 32c -set _MOTIF_WM_HINTS "0x2, 0x0, 0x0, 0x0, 0x0" 2>/dev/null

# Sacarla del taskbar/alt-tab.
wmctrl -i -r "$BACK_WID" -b add,skip_taskbar,skip_pager 2>/dev/null

# El dash/dock de Ubuntu muestra un ícono por app (xterm y alacritty son
# apps distintas) e ignora skip_taskbar. Marcarla como tipo UTILITY hace
# que el dock no le ponga ícono.
xprop -id "$BACK_WID" -f _NET_WM_WINDOW_TYPE 32a \
    -set _NET_WM_WINDOW_TYPE _NET_WM_WINDOW_TYPE_UTILITY 2>/dev/null

# xterm redondea su tamaño a la grilla de caracteres (resize increment) y
# siempre redondea hacia abajo, lo que deja un borde fino sin fondo.
# Le sumamos ese margen para que la de atrás siempre quede igual o más
# grande que la de adelante, nunca más chica.
HINTS="$(xprop -id "$BACK_WID" WM_NORMAL_HINTS 2>/dev/null)"
INC_W="$(grep -oP 'resize increment: \K[0-9]+' <<< "$HINTS")"
INC_H="$(grep -oP 'resize increment: [0-9]+ by \K[0-9]+' <<< "$HINTS")"
PAD_W=$(( ${INC_W:-1} > 0 ? ${INC_W:-1} - 1 : 0 ))
PAD_H=$(( ${INC_H:-1} > 0 ? ${INC_H:-1} - 1 : 0 ))

echo "Listo. Mueve o redimensiona la ventana transparente y el fantasma la va a seguir."
echo "Cierra esa ventana (la de adelante) para terminar todo."

# Estado inicial de maximizado (0/1), cacheado en un archivo para no forkear
# xprop en cada movimiento: solo cambia en el raro caso de maximizar/restaurar.
STATE0="$(xprop -id "$FRONT_WID" _NET_WM_STATE 2>/dev/null)"
if [[ "$STATE0" == *MAXIMIZED_VERT* && "$STATE0" == *MAXIMIZED_HORZ* ]]; then
    echo 1 > "$MAX_FLAG"
else
    echo 0 > "$MAX_FLAG"
fi

# Reubica la de atrás según la geometría actual de la de adelante y el flag
# de maximizado cacheado (evita forkear xprop en cada evento de movimiento).
reposition() {
    local GEO OX OY MAXIMIZED
    GEO="$(xdotool getwindowgeometry --shell "$FRONT_WID" 2>/dev/null)" || return 1
    eval "$GEO"
    read -r MAXIMIZED < "$MAX_FLAG"
    if [[ "$MAXIMIZED" == "1" ]]; then
        if (( X >= MONITOR3_X_MIN )); then
            OX=$OFFSET_X_MAX_M3; OY=$OFFSET_Y_MAX_M3
        else
            OX=$OFFSET_X_MAX; OY=$OFFSET_Y_MAX
        fi
    else
        OX=$OFFSET_X; OY=$OFFSET_Y
    fi
    wmctrl -i -r "$BACK_WID" -e "0,$((X-OX)),$((Y-OY)),$((WIDTH+PAD_W)),$((HEIGHT+PAD_H))"
}

# ¿La de atrás ya está justo debajo de la de adelante en el orden de apilado?
back_is_right_below_front() {
    local ids tok prev=""
    ids="$(xprop -root _NET_CLIENT_LIST_STACKING 2>/dev/null)"
    ids="${ids#*# }"
    for tok in ${ids//,/ }; do
        tok=$((tok))
        [[ "$prev" == "$BACK_WID" && "$tok" == "$FRONT_WID" ]] && return 0
        prev=$tok
    done
    return 1
}

# Cuando la de adelante se enfoca, la sube junto con la de atrás por encima
# de lo que sea que las tapara. "xdotool windowraise" no sirve: Mutter ignora
# los raise de una ventana sin foco (anti robo-de-foco); en cambio "activar"
# (wmctrl -a, lo mismo que hace un click real) sí lo respeta. Solo lo hacemos
# si hace falta, porque activar genera un FocusIn nuevo y si no filtráramos
# por el chequeo de arriba, se dispararía en bucle contra sí mismo.
raise_pair_if_needed() {
    back_is_right_below_front && return
    wmctrl -i -a "$BACK_WID" 2>/dev/null
    wmctrl -i -a "$FRONT_WID" 2>/dev/null
}

reposition
raise_pair_if_needed

# Escucha en paralelo los cambios reales de _NET_WM_STATE (maximizar/restaurar)
# y solo entonces actualiza el flag cacheado; se queda bloqueado el resto del tiempo.
mkfifo "$SPY_FIFO"
xprop -spy -id "$FRONT_WID" _NET_WM_STATE > "$SPY_FIFO" 2>/dev/null &
SPY_SRC_PID=$!
while read -r line; do
    if [[ "$line" == *MAXIMIZED_VERT* && "$line" == *MAXIMIZED_HORZ* ]]; then
        echo 1 > "$MAX_FLAG"
    else
        echo 0 > "$MAX_FLAG"
    fi
done < "$SPY_FIFO" &
SPY_PID=$!

# En vez de sondear en un bucle, escuchamos los eventos X11 de la ventana de
# adelante (mover/redimensionar/minimizar/restaurar) y solo actuamos cuando
# realmente ocurren, así el script queda en reposo (0% CPU) el resto del tiempo.
mkfifo "$XEV_FIFO"
xev -id "$FRONT_WID" > "$XEV_FIFO" 2>/dev/null &
XEV_PID=$!
while read -r line; do
    case "$line" in
        *ConfigureNotify*) reposition ;;
        *UnmapNotify*) xdotool windowunmap "$BACK_WID" 2>/dev/null ;;
        *MapNotify*)
            xdotool windowmap "$BACK_WID" 2>/dev/null
            reposition
            raise_pair_if_needed
            ;;
        *FocusIn*) raise_pair_if_needed ;;
    esac
done < "$XEV_FIFO" &
EVENT_PID=$!

wait -n "$FRONT_PID" "$BACK_PID" 2>/dev/null
