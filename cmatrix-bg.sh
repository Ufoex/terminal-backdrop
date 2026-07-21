#!/usr/bin/env bash
# Abre una ventana con cmatrix de fondo y una terminal transparente adelante.
# Al mover/redimensionar la de adelante, la de atrás la sigue automáticamente.
#
# Uso: ./cmatrix-bg.sh [opacidad 0.0-1.0]
#   ./cmatrix-bg.sh          # opacidad por defecto 0.55
#   ./cmatrix-bg.sh 0.4      # más transparente

set -uo pipefail

OPACITY="${1:-0.55}"
TAG=$$
BACK_TITLE="cmatrix-bg-$TAG"
FRONT_TITLE="cmatrix-front-$TAG"

# Posición inicial explícita e IGUAL para ambas ventanas: así ninguna
# depende del "cascade placement" del WM (que las abre en esquinas
# distintas) mientras arranca el bucle de sincronización.
START_X=250
START_Y=400

# El inset de decoración de la ventana de adelante (cuánto hay que
# descontarle a su posición reportada para llegar a la esquina de su
# cuadrícula de texto, no a la de su marco/barra de título) cambia según el
# equipo, el tema, el monitor y si está maximizada o no. En vez de
# hardcodear constantes calibradas a mano para una sola máquina, se mide en
# caliente (ver window_decoration_inset más abajo), así el script se
# autocalibra en cualquier equipo y con cualquier cantidad de monitores.
OFFSET_X=0
OFFSET_Y=0

# Caché del offset de maximizado por monitor, en disco (no en un array
# asociativo en memoria): reposition() corre en tres procesos bash
# independientes (el principal, el listener de xev y el de xprop -spy, cada
# uno en su propio subshell por el "&" final), y un array en memoria de uno
# no es visible para los otros — cada proceso recalibraría por su cuenta y
# el que escribiera la ventana de atrás último ganaría con una lectura
# potencialmente vieja, dando una posición inconsistente. Un archivo
# compartido con flock evita esa carrera entre procesos.
MAX_OFFSET_FILE="/tmp/.cmatrix-maxoff-$TAG"
MAX_OFFSET_LOCK="/tmp/.cmatrix-maxoff-lock-$TAG"
: > "$MAX_OFFSET_FILE"

BACK_PID=""
FRONT_PID=""
EVENT_PID=""
XEV_PID=""
SPY_PID=""
SPY_SRC_PID=""
MAX_FLAG="/tmp/.cmatrix-max-$TAG"
XEV_FIFO="/tmp/.cmatrix-xev-$TAG"
SPY_FIFO="/tmp/.cmatrix-spy-$TAG"

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
    rm -f "$MAX_FLAG" "$XEV_FIFO" "$SPY_FIFO" "$MAX_OFFSET_FILE" "$MAX_OFFSET_LOCK"
}
trap cleanup EXIT INT TERM

for bin in xterm alacritty wmctrl xdotool xev xwininfo cmatrix xrandr; do
    command -v "$bin" >/dev/null || { echo "Falta '$bin'. Instalalo con: sudo apt install $bin" >&2; exit 1; }
done

# Tamaño real del escritorio virtual (todos los monitores combinados, origen
# 0,0). "xdotool getdisplaygeometry" en un setup multi-monitor devuelve el
# tamaño de UN solo monitor (no el total), lo que hacía que el clamp de
# pantalla de más abajo se disparara sobre ventanas que estaban perfectamente
# adentro. Se calcula una sola vez: no cambia mientras corre el script.
read -r SCREEN_W SCREEN_H < <(xrandr --query | awk '/^Screen/{gsub(",","",$10); print $8, $10}')

# Ventana de atrás: cmatrix puro en xterm (X11 nativo). Arranca en la misma
# posición nominal que la de adelante; measure_normal_offset la corrige
# apenas ambas ventanas están mapeadas.
xterm -title "$BACK_TITLE" -bg black -fg green -geometry "+$START_X+$START_Y" -e cmatrix &
BACK_PID=$!

# Ventana de adelante: shell normal, forzada a X11 (para poder moverla/medirla)
# y con opacidad real para dejar ver cmatrix detrás.
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

# Fijar el par "siempre arriba" en vez de perseguir foco/stacking a mano:
# tratar de subirlas cuando se enfocan y bajarlas cuando no, peleaba contra
# Mutter (el tipo UTILITY ya las trataba como flotantes) y nunca era
# confiable. _NET_WM_STATE_ABOVE es el mismo mecanismo que usa cualquier
# app con "mantener siempre visible", y el WM lo respeta siempre.
wmctrl -i -r "$BACK_WID" -b add,above 2>/dev/null
wmctrl -i -r "$FRONT_WID" -b add,above 2>/dev/null

# xterm redondea su tamaño a la grilla de caracteres (resize increment) y
# siempre redondea hacia abajo, lo que deja un borde fino sin cmatrix.
# Le sumamos ese margen para que la de atrás siempre quede igual o más
# grande que la de adelante, nunca más chica.
HINTS="$(xprop -id "$BACK_WID" WM_NORMAL_HINTS 2>/dev/null)"
INC_W="$(grep -oP 'resize increment: \K[0-9]+' <<< "$HINTS")"
INC_H="$(grep -oP 'resize increment: [0-9]+ by \K[0-9]+' <<< "$HINTS")"
PAD_W=$(( ${INC_W:-1} > 0 ? ${INC_W:-1} - 1 : 0 ))
PAD_H=$(( ${INC_H:-1} > 0 ? ${INC_H:-1} - 1 : 0 ))

echo "Listo. Mueve o redimensiona la ventana transparente y cmatrix la va a seguir."
echo "Cierra esa ventana (la de adelante) para terminar todo."

# Orígenes X de cada monitor conectado (para keyear el offset de maximizado
# por monitor: paneles/DPI distintos entre pantallas pueden dar desfases
# distintos al maximizar en una u otra). Se calcula una sola vez.
MONITOR_ORIGINS=()
while IFS= read -r origin; do
    MONITOR_ORIGINS+=("$origin")
done < <(xrandr --query | grep -oE '[0-9]+x[0-9]+\+[0-9]+\+[0-9]+' | awk -F'+' '{print $2}' | sort -n -u)

# Dado un X absoluto, devuelve el origen del monitor al que pertenece (el
# mayor origen de monitor que sea <= X). Asume monitores en fila horizontal,
# igual que el resto del script.
monitor_key() {
    local x="$1" best=0 origin
    for origin in "${MONITOR_ORIGINS[@]}"; do
        (( origin <= x )) && best="$origin"
    done
    echo "$best"
}

# Archivo de diagnóstico persistente: cuando el script corre desde un atajo
# de teclado (ver README, "bash -c '... >/dev/null 2>&1'"), cualquier aviso
# por stderr se pierde para siempre. Este log queda en disco pase lo que
# pase, para poder auditar una calibración rara después de los hechos.
DEBUG_LOG="/tmp/cmatrix-bg-debug.log"
dbg() { echo "[$TAG] $*" >> "$DEBUG_LOG" 2>/dev/null; }

# Tamaño real de la decoración (barra de título + borde) de una ventana: la
# diferencia entre su posición y la de su padre inmediato (el frame que
# dibuja el WM), tal como lo reporta xwininfo ("Relative upper-left").
# Deliberadamente NO se usa "xdotool getwindowgeometry" para esto: en este
# equipo, para una ventana con frame, xdotool devuelve una traducción de
# coordenadas que ya trae este mismo inset sumado una vez de más (verificado
# a mano comparando ambas herramientas sobre la misma ventana) — usarlo para
# calibrar terminaba sumando el inset dos veces, empujando el fondo hacia la
# esquina de arriba/izquierda (donde están los botones) en vez de a la
# esquina de la cuadrícula de texto. xwininfo lo da directo, sin ese lío.
window_decoration_inset() {
    local info ix iy
    info="$(xwininfo -id "$1" 2>/dev/null)" || return 1
    ix="$(awk -F': *' '/Relative upper-left X/{print $2}' <<< "$info")"
    iy="$(awk -F': *' '/Relative upper-left Y/{print $2}' <<< "$info")"
    [[ -n "$ix" && -n "$iy" ]] || return 1
    echo "$ix $iy"
}

# Mide el inset de decoración de la ventana de adelante en estado normal.
# Al ser una propiedad de la ventana en sí (no una comparación contra la de
# atrás), no hace falta esperar a que la de atrás exista ni reintentar por
# posibles estados transitorios.
measure_normal_offset() {
    local ix iy
    read -r ix iy < <(window_decoration_inset "$FRONT_WID") || return 1
    OFFSET_X=$ix
    OFFSET_Y=$iy
    dbg "offset normal (inset real de decoración): $OFFSET_X,$OFFSET_Y"
}

# Da "OX OY" para un monitor, calibrando y guardando en el archivo
# compartido la primera vez que hace falta (ver el comentario de
# MAX_OFFSET_FILE más arriba sobre por qué es un archivo con flock y no un
# array en memoria). Todo el check-then-set queda bajo un mismo lock, así
# dos procesos que lleguen a la vez no calibran cada uno por su cuenta.
resolve_max_offset() {
    local key="$1" line ix iy
    exec 9>>"$MAX_OFFSET_LOCK"
    flock -x 9
    line="$(awk -v k="$key" '$1==k{print; exit}' "$MAX_OFFSET_FILE" 2>/dev/null)"
    if [[ -z "$line" ]]; then
        read -r ix iy < <(window_decoration_inset "$FRONT_WID")
        ix="${ix:-0}"; iy="${iy:-0}"
        line="$key $ix $iy"
        echo "$line" >> "$MAX_OFFSET_FILE"
        dbg "offset maximizado (monitor x=$key): $ix,$iy"
    fi
    exec 9>&-
    echo "$line"
}

measure_normal_offset || { echo "Aviso: no pude autocalibrar el offset, uso 0,0." >&2; dbg "autocalibración FALLÓ, quedó en 0,0"; }

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
    local GEO OX OY MAXIMIZED BX BY BW BH KEY LINE
    GEO="$(xdotool getwindowgeometry --shell "$FRONT_WID" 2>/dev/null)" || return 1
    eval "$GEO"
    read -r MAXIMIZED < "$MAX_FLAG"
    if [[ "$MAXIMIZED" == "1" ]]; then
        KEY="$(monitor_key "$X")"
        LINE="$(resolve_max_offset "$KEY")"
        read -r _ OX OY <<< "$LINE"
        OX="${OX:-0}"; OY="${OY:-0}"
        # resolve_max_offset puede tardar un instante si calibra recién;
        # releer la geometría para no terminar posicionando con una lectura
        # de X/Y ya vieja.
        GEO="$(xdotool getwindowgeometry --shell "$FRONT_WID" 2>/dev/null)" && eval "$GEO"
    else
        OX=$OFFSET_X; OY=$OFFSET_Y
    fi

    # Mutter ignora los pedidos de mover la ventana de adelante estando
    # enfocada (probado: wmctrl -e no le hace nada), así que no podemos
    # impedir que el usuario la arrastre fuera de pantalla. Lo único que
    # controlamos es la de atrás: la encajamos para que nunca dibuje fuera
    # del escritorio virtual (SCREEN_W/SCREEN_H, calculados una sola vez al
    # inicio), aunque la de adelante esté parcialmente afuera.
    BW=$((WIDTH+PAD_W)); BH=$((HEIGHT+PAD_H))
    BX=$((X-OX)); BY=$((Y-OY))
    # Si se pasa de CUALQUIER borde, recortar el TAMAÑO correspondiente y
    # nunca "correr" la esquina opuesta: la posición es la que mantiene
    # alineada la esquina de la cuadrícula de texto con la de adelante.
    # - Borde derecho/inferior (ventana grande o maximizada, ver más abajo):
    #   ya está en su lugar, solo hace falta achicar el ancho/alto sobrante.
    # - Borde izquierdo/superior (de adelante arrastrada parcialmente fuera
    #   de pantalla): acá SÍ hay que mover BX/BY a 0 (no se puede dibujar en
    #   coordenadas negativas), pero eso corta un pedazo del lado izquierdo/
    #   de arriba — sin restarle ese mismo pedazo al ancho/alto, la de atrás
    #   quedaba con su tamaño COMPLETO pegada al borde, sobrando bien a la
    #   derecha/abajo de lo que la de adelante realmente muestra en pantalla
    #   (el bug que se ve al arrastrar la ventana fuera por la izquierda).
    if (( BX < 0 )); then BW=$((BW+BX)); BX=0; fi
    if (( BY < 0 )); then BH=$((BH+BY)); BY=0; fi
    (( BW < 0 )) && BW=0
    (( BH < 0 )) && BH=0
    (( BX + BW > SCREEN_W )) && BW=$((SCREEN_W - BX))
    (( BY + BH > SCREEN_H )) && BH=$((SCREEN_H - BY))
    wmctrl -i -r "$BACK_WID" -e "0,$BX,$BY,$BW,$BH"
}

reposition

# Escucha en paralelo los cambios reales de _NET_WM_STATE (maximizar/restaurar
# Y minimizar/restaurar: bajo Wayland+XWayland el minimizado no siempre manda
# UnmapNotify, pero el atom _NET_WM_STATE_HIDDEN sí cambia siempre, así que es
# la señal confiable para ocultar/mostrar la de atrás. Se queda bloqueado el
# resto del tiempo.
mkfifo "$SPY_FIFO"
xprop -spy -id "$FRONT_WID" _NET_WM_STATE > "$SPY_FIFO" 2>/dev/null &
SPY_SRC_PID=$!
while read -r line; do
    if [[ "$line" == *MAXIMIZED_VERT* && "$line" == *MAXIMIZED_HORZ* ]]; then
        echo 1 > "$MAX_FLAG"
    else
        echo 0 > "$MAX_FLAG"
    fi
    if [[ "$line" == *HIDDEN* ]]; then
        xdotool windowunmap "$BACK_WID" 2>/dev/null
    else
        xdotool windowmap "$BACK_WID" 2>/dev/null
        wmctrl -i -r "$BACK_WID" -b add,above 2>/dev/null
        wmctrl -i -r "$FRONT_WID" -b add,above 2>/dev/null
        reposition
    fi
done < "$SPY_FIFO" &
SPY_PID=$!

# En vez de sondear en un bucle, escuchamos los eventos X11 de la ventana de
# adelante (mover/redimensionar) y solo actuamos cuando realmente ocurren, así
# el script queda en reposo (0% CPU) el resto del tiempo. Minimizar/restaurar
# ya lo cubre el spy de _NET_WM_STATE de arriba; el "siempre arriba" ya lo
# cubre el estado ABOVE fijado al inicio, sin necesidad de escuchar el foco.
mkfifo "$XEV_FIFO"
xev -id "$FRONT_WID" > "$XEV_FIFO" 2>/dev/null &
XEV_PID=$!
while read -r line; do
    case "$line" in
        *ConfigureNotify*) reposition ;;
    esac
done < "$XEV_FIFO" &
EVENT_PID=$!

wait -n "$FRONT_PID" "$BACK_PID" 2>/dev/null
