#!/usr/bin/env bash
# Reproduce, en una terminal real, la animación del fantasma que aparece en
# la home de Ghostty (https://ghostty.org) — los 235 cuadros vienen de los
# datos de esa página (assets/ghost-frames.txt.gz): su marcado HTML
# <span class="b"> se combinó con la densidad de cada carácter para pintar
# un degradé de color (no había color en los datos originales, solo un
# flag de negrita; el degradé es un agregado mío). El arte y la animación
# en sí son de Ghostty, no míos: https://ghostty.org
#
# No conozco el FPS original (no está en los datos, vive en su JS
# compilado), así que FRAME_DELAY es una aproximación mía: ajustala si la
# querés más rápida o más lenta.

set -uo pipefail

FRAME_DELAY=0.05  # segundos entre cuadros (~20 fps aprox.)
ART_COLS=100       # cada cuadro mide 100x41 caracteres, tal cual en la web
ART_ROWS=41

SELF_DIR="$(dirname "$(readlink -f "$0")")"
FRAMES_GZ="$SELF_DIR/assets/ghost-frames.txt.gz"
[[ -f "$FRAMES_GZ" ]] || { echo "No encontré $FRAMES_GZ" >&2; exit 1; }

# Cargar las 235*41 líneas una sola vez en memoria (unos 3MB sin comprimir).
mapfile -t LINES < <(zcat "$FRAMES_GZ")
TOTAL_LINES=${#LINES[@]}
NUM_FRAMES=$(( TOTAL_LINES / ART_ROWS ))

# Centrar el arte (100x41) dentro de la terminal real, sea cual sea su
# tamaño. Se recalcula solo ante un resize (señal WINCH), no en cada cuadro.
PAD_LEFT=0
PAD_TOP=0
calc_padding() {
    local cols lines
    read -r lines cols < <(stty size 2>/dev/null) || return
    (( cols > ART_COLS )) && PAD_LEFT=$(( (cols - ART_COLS) / 2 )) || PAD_LEFT=0
    (( lines > ART_ROWS )) && PAD_TOP=$(( (lines - ART_ROWS) / 2 )) || PAD_TOP=0
}
trap calc_padding WINCH
calc_padding

restore_cursor() { printf '\033[?25h\033[0m'; }
trap restore_cursor EXIT INT TERM

printf '\033[?25l\033[2J'  # ocultar cursor, limpiar pantalla una vez
LEFT_PAD_STR=""

while true; do
    for (( f = 0; f < NUM_FRAMES; f++ )); do
        printf '\033[H'  # volver al origen sin limpiar (evita parpadeo)
        for (( i = 0; i < PAD_TOP; i++ )); do printf '\n'; done
        LEFT_PAD_STR="$(printf '%*s' "$PAD_LEFT" '')"
        base=$(( f * ART_ROWS ))
        for (( r = 0; r < ART_ROWS; r++ )); do
            printf '%s%s\n' "$LEFT_PAD_STR" "${LINES[base + r]}"
        done
        sleep "$FRAME_DELAY"
    done
done
