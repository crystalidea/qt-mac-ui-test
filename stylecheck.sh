#!/bin/bash
# Builds the StyleCheck window and runs it in the light and dark appearance. The window shows its tabs one by one,
# prints its window number and the geometry of the controls of each tab and shoots the tab; the shots are analyzed tab
# by tab. The Progress tab is shot four times 0.25 s apart: the frames show how the indeterminate bars move. With
# --menus the window also shoots its open lists and pull-down menus.
#   stylecheck.sh [--menus] [output_dir]
# The output directory is shots/ next to the script by default
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
QMAKE="${QMAKE:-/usr/local/Qt-6.8.5/bin/qmake}"
BUILD="$HERE/build"
APP="$BUILD/StyleCheck.app/Contents/MacOS/StyleCheck"
MENUS=0

if [[ "${1:-}" == --menus ]]; then
    MENUS=1
    shift
fi

OUT="${1:-$HERE/shots}"
mkdir -p "$OUT" "$BUILD"

if [[ ! -f "$BUILD/Makefile" ]]; then
    (cd "$BUILD" && "$QMAKE" ../StyleCheck.pro) > "$OUT/build.log" 2>&1 || { echo "qmake failed, see $OUT/build.log"; exit 1; }
fi

make -C "$BUILD" -j8 >> "$OUT/build.log" 2>&1 || { echo "build failed, see $OUT/build.log"; exit 1; }

if [[ ! -x "$BUILD/scanalyze" || "$HERE/scanalyze.swift" -nt "$BUILD/scanalyze" ]]; then
    swiftc -O -o "$BUILD/scanalyze" "$HERE/scanalyze.swift" || exit 1
fi

# A locked Mac turns its display off about 30 s after it wakes, and then windows can't be shot: the user activity is
# declared anew every 4 s. The window doesn't become active on a locked Mac
( while true; do caffeinate -u -t 4; done ) &
AWAKE=$!
trap 'kill $AWAKE 2>/dev/null' EXIT

for scheme in light dark; do
    LOG="$OUT/$scheme.txt"
    DIR="$OUT/$scheme"
    ARGS=("$scheme" --shots "$DIR")
    mkdir -p "$DIR"

    if (( MENUS )); then
        ARGS+=(--menus)
    fi

    "$APP" "${ARGS[@]}" > "$LOG" 2>&1 &
    PID=$!

    # about 2 s a tab, and 20 s more for the menus
    for _ in $(seq 1 1500); do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.1
    done

    if kill -0 "$PID" 2>/dev/null; then
        echo "$scheme: the window didn't get through its tabs, see $LOG"
        kill "$PID"
    fi

    wait "$PID" 2>/dev/null

    echo "===== $scheme"

    if ! grep '^stylecheck ready' "$LOG"; then
        echo "the window didn't respond, see $LOG"
        continue
    fi

    # An inactive window draws the bars gray and the edit without the focus ring; sizes and insets come out right in
    # it too. A locked Mac never gives the window the focus, an unlocked one may not give it while you type elsewhere
    LOCKED=0

    if grep -q '^stylecheck ready .* locked=1' "$LOG"; then
        LOCKED=1
        echo "the Mac is locked, the window is shot inactive: gray bars, no focus ring"
    fi

    # the shots the window took of each tab
    while read -r _ _ tab files; do
        if (( ! LOCKED )) && grep -q "^stylecheck tab $tab active=0" "$LOG"; then
            echo "-- $tab, inactive: gray bars, no focus ring"
        else
            echo "-- $tab"
        fi

        SHOTS=()

        for file in $files; do
            SHOTS+=("$DIR/$file")
        done

        if (( ${#SHOTS[@]} == 0 )); then
            echo "no shot of the tab"
            continue
        fi

        "$BUILD/scanalyze" "$LOG" "$tab" "$DIR" "${SHOTS[@]}"
    done < <(grep '^stylecheck shots ' "$LOG")

    if (( MENUS )); then
        echo "-- menus"
        grep -E '^stylecheck (menu|select)' "$LOG"
    fi
done
