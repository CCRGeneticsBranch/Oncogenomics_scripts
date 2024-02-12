#!/bin/bash

DEST="${@:${#@}}"
ABS_DEST="$(cd "$(dirname "$DEST")"; pwd)/$(basename "$DEST")"

for SRC in ${@:1:$((${#@} -1))}; do   (
    cd "$SRC";
    find . -type d -exec mkdir -p "${ABS_DEST}"/\{} \;
    find . -type f -exec mv \{} "${ABS_DEST}"/\{} \;
    find . -type d -empty -delete
) done
