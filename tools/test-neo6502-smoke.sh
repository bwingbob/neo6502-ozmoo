#!/usr/bin/env bash
# Build Minizork for Neo6502, drive the instrumented-free emulator, and assert
# that the rendered console contains the previously corrupted leaflet text.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/tools"

STORY="${NEO_SMOKE_STORY:-examples/minizork.z3}"
OZMOO_HOME="${OZMOO_HOME:-/tmp/ozmoo-home}"
FIRMWARE_ROOT="${NEO_FIRMWARE_ROOT:-/tmp/opencode/neo-firmware}"
EMULATOR="$FIRMWARE_ROOT/emulator/neo"
FONT_HEADER="$FIRMWARE_ROOT/firmware/common/include/interface/font_5x7.h"
WORKDIR="${NEO_SMOKE_WORKDIR:-/tmp/opencode/neo-smoke}"

SKIP_BUILD="${NEO_SMOKE_SKIP_BUILD:-0}"
BOOT_DELAY="${NEO_SMOKE_BOOT_DELAY:-4}"
COMMAND_DELAY="${NEO_SMOKE_COMMAND_DELAY:-5}"
FINAL_DELAY="${NEO_SMOKE_FINAL_DELAY:-3}"
WINDOW_TIMEOUT="${NEO_SMOKE_WINDOW_TIMEOUT:-10}"

mkdir -p "$WORKDIR"
LOG="$WORKDIR/emulator.log"
SCREENSHOT="$WORKDIR/screen.png"
DECODED="$WORKDIR/decoded.txt"

EMU_PID=""
WINDOW_ID=""

cleanup() {
    if [[ -n "$EMU_PID" ]] && kill -0 "$EMU_PID" 2>/dev/null; then
        kill "$EMU_PID" 2>/dev/null || true
        wait "$EMU_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

require_command() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $1" >&2
        exit 1
    }
}

require_file() {
    [[ -f "$1" ]] || {
        echo "ERROR: required file not found: $1" >&2
        exit 1
    }
}

require_command ruby
require_command python3
require_command xdotool
require_command import
require_file "$EMULATOR"
require_file "$FONT_HEADER"
require_file "$TOOLS_DIR/decode_neo_console.py"

python3 -c 'import PIL' >/dev/null 2>&1 || {
    echo "ERROR: Pillow is required by tools/decode_neo_console.py" >&2
    exit 1
}

cd "$ROOT_DIR"

if [[ "$SKIP_BUILD" != "1" ]]; then
    echo "Building $STORY for Neo6502..."
    env OZMOO_HOME="$OZMOO_HOME" ruby make.rb -t:neo6502 -v "$STORY"
fi

echo "Preparing raw emulator load files..."
tail -c +3 temp/ozmoo > temp/ozmoo-neo-main.bin
cp temp/compmem.tmp temp/ozmoo-neo-story.bin

rm -f "$LOG" "$SCREENSHOT" "$DECODED"

echo "Starting emulator..."
"$EMULATOR" \
    cold \
    "$ROOT_DIR/temp/ozmoo-neo-main.bin@1000" \
    "$ROOT_DIR/temp/ozmoo-neo-story.bin@4600" \
    run@1000 > "$LOG" 2>&1 &
EMU_PID=$!

deadline=$((SECONDS + WINDOW_TIMEOUT))
while [[ -z "$WINDOW_ID" ]]; do
    WINDOW_ID="$(xdotool search --pid "$EMU_PID" 2>/dev/null | head -n 1 || true)"
    if [[ -z "$WINDOW_ID" ]]; then
        if ((SECONDS >= deadline)); then
            echo "ERROR: emulator window did not appear within ${WINDOW_TIMEOUT}s" >&2
            tail -40 "$LOG" >&2 || true
            exit 1
        fi
        sleep 0.2
    fi
done

sleep "$BOOT_DELAY"

send_line() {
    xdotool windowactivate --sync "$WINDOW_ID"
    sleep 0.2
    xdotool type --delay 60 -- "$1"
    xdotool key Return
}

echo "Injecting smoke-test commands..."
send_line "open mailbox"
sleep "$COMMAND_DELAY"
send_line "read leaflet"
sleep "$FINAL_DELAY"

echo "Capturing console..."
import -window "$WINDOW_ID" "$SCREENSHOT"
python3 "$TOOLS_DIR/decode_neo_console.py" "$SCREENSHOT" "$FONT_HEADER" > "$DECODED"

failures=0

expect_text() {
    if ! grep -Fq "$1" "$DECODED"; then
        echo "FAIL: expected text not found: $1" >&2
        failures=$((failures + 1))
    fi
}

expect_regex() {
    if ! grep -Eq "$1" "$DECODED"; then
        echo "FAIL: expected pattern not found: $1" >&2
        failures=$((failures + 1))
    fi
}

expect_text "OPENING THE SMALL MAILBOX REVEALS A LEAFLET."
expect_text "THE LARGER, DISK-BASED VERSION OF ZORK I."
expect_text ">read leaflet"
expect_regex '^00: WEST OF HOUSE'
expect_regex '^29: >'

if grep -Fq "BH!CJ" "$DECODED"; then
    echo "FAIL: known corrupted leaflet text is present" >&2
    failures=$((failures + 1))
fi

if ((failures > 0)); then
    echo "--- decoded console ---" >&2
    cat "$DECODED" >&2
    echo "--- emulator log tail ---" >&2
    tail -40 "$LOG" >&2 || true
    exit 1
fi

echo "PASS: Neo6502 smoke test"
echo "  screenshot: $SCREENSHOT"
echo "  decoded:    $DECODED"
echo "  log:        $LOG"
