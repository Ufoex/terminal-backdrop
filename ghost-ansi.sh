#!/usr/bin/env bash
# Dibuja el fantasma de Ghostty (https://ghostty.org) como arte ANSI,
# ocupando toda la terminal. No sondea: se re-dibuja solo cuando la
# terminal cambia de tamaño (señal WINCH), así que queda en reposo el
# resto del tiempo. Pensado para usarse como reemplazo de "cmatrix" en
# cmatrix-bg.sh (ver ghost-bg.sh y el README).
#
# El arte del fantasma es de Ghostty, no mío: https://ghostty.org

set -uo pipefail

command -v chafa >/dev/null || { echo "Falta 'chafa'. Instalalo con: sudo apt install chafa" >&2; exit 1; }

IMG="$(dirname "$(readlink -f "$0")")/assets/ghost.png"
[[ -f "$IMG" ]] || { echo "No encontré $IMG" >&2; exit 1; }

render() {
    clear
    chafa --clear --animate=off "$IMG"
}

trap render WINCH
render

while true; do sleep infinity; done
