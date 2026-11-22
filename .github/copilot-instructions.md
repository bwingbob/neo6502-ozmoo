# Neo6502 port guidance

This repo (`origin`: `bwingbob/neo6502-ozmoo`) is a Neo6502-focused fork of Ozmoo (`upstream`: `johanberntsson/ozmoo`). Keep upstream-compatible changes separate from Neo6502-specific work, and do not push without explicit permission.

## Current state and intent

- Neo6502 target now builds and runs Minizork in the emulator. Treat remaining
  work as targeted hardening, not a greenfield port.
- Preserve interpreter core behavior; isolate new platform logic behind existing target/version conditionals.
- Verify Neo6502 hardware/software interfaces with the scripted emulator workflow below before changing memory map, loader, I/O, or screen assumptions.

## Architecture you must understand first

- `asm/ozmoo.asm` is the root assembly unit (`!source` fan-in + `!ifdef` target/version selection).
- `make.rb` is the build orchestrator: it derives `-D` defines (target, z-version, features) and drives ACME/Exomizer/disk output.
- Core interpreter path: `asm/zmachine.asm`, `asm/stack.asm`, `asm/memory.asm`, `asm/vmem.asm`.
- Screen/input diverge by Z-machine version:
  - non-v6: `asm/screen.asm`, `asm/screenkernal.asm`
  - v6: `asm/screen-z6.asm`, `asm/screenkernal-z6.asm` (+ picture engines)
- Target memory/zero-page layouts live in `asm/constants*.asm`; any shared layout edits must be checked across all target constants files.

## Codebase-specific conventions

- ACME + Ruby are the interpreter build path. cc65/cl65 are relevant for Neo6502 tooling, but **do not replace** ACME for Ozmoo builds.
- Prefer adding target branches over cloning shared logic; keep platform assumptions out of common opcode/interpreter paths.
- For v6 opcode work, guard optional operands with `z_operand_count` checks (operand storage is reused between instructions).
- Keep z6/non-z6 screen paths behaviorally aligned unless a spec/platform difference requires divergence.

## Productive workflows

- Discover options: `ruby make.rb`
- Core regression builds used in this repo’s Makefile/docs:
  - `make z6`, `make z6-fcm`, `make z6-x16`, `make z6-pics`, `make z6-pics-x16`
  - `make dejavu-c64` (non-v6 regression)
  - `ruby make.rb test/praxix.z5` (or equivalent target variants)
- Build checks: `make -C tests` (runs `tests/test_builds.rb`)
- `temp/acme_labels.txt` is regenerated every build; only use labels matching the exact binary under debug.

## Tooling and integration details

- Linux default Exomizer path in `make.rb` is repo-local: `exomizer/src/exomizer`.
- Override tool paths with `.ozmoorc` (checked via `OZMOO_HOME`, cwd, then home directory).
- Picture pipeline utilities are in `tools/` (`pics2asm.py`, `make_blorb.py`); `-pics` builds depend on that path.

## Validation expectations for shared changes

- Do both assembly success and runtime behavior checks (especially screen/window changes).
- Exercise both v6 and non-v6 baselines (`testz6.inf`/frotz comparison, `examples/dejavu.z3`, `test/praxix.z5`).
- Keep manual/doc changes in sync with `documentation/manual/` sources.

## Neo6502 emulator findings (from current port work)

- Neo text output is currently most stable through the target-specific path in `asm/screenkernal.asm` (`.neo_printchar`), with `TARGET_NEO6502` bypass in `printchar_buffered` (`asm/screen.asm`). Re-enabling the generic buffered path for Neo has repeatedly caused one-character-per-line regressions.
- The Neo console path should output plain character bytes (masked with `#$7f`) rather than C64 screen codes. Keep Neo-specific character conversion behavior isolated in `TARGET_NEO6502` branches.
- Current verified geometry for emulator/runtime behavior is **53x30** (`SCREEN_WIDTH=53`, `SCREEN_HEIGHT=30` in `asm/constants-neo6502.asm`).
- Newline handling that currently works for this path is CR-based (`#13`) in Neo emit routines. Treat CR/LF combinations as platform-sensitive and verify in emulator before changing.
- Prompt/input echo reliability depends on immediate echo during input mode; keep input-mode handling separate from story-text wrapping logic.
- Neo keyboard backspace/delete may arrive as `$08`/`$7f`; normalize to Ozmoo delete code `20` in the Neo KERNAL adapter (`asm/neo6502-morpheus.asm`) so line editing works.
- For Neo prompt editing, delete must erase one character (`BS`, space, `BS`) and must not emit clear-screen control (`12`); keep this behavior in the Neo print path (`asm/screenkernal.asm`).
- Neo KERNAL `CLOSE` should tolerate defensive closes of unopened channels (for example lfn 15/2/255) and avoid cascading into false disk-error handling.
- Avoid stack manipulation side effects inside Neo print routines (extra `PLA/PHA` in mid-flow caused severe output corruption during testing).
- ACME branch distance is a recurring risk in large target-specific blocks; prefer short local conditional branches plus explicit `jmp` fallbacks when needed.

### Scripted emulator verification (preferred; do not do this manually)

`tools/test-neo6502-smoke.sh` is the reference implementation. It rebuilds
Minizork, strips the two-byte PRG load address, launches the emulator with both
raw binaries, waits for the SDL window by PID, injects game commands with
`xdotool`, captures the window, decodes pixels against the firmware font,
asserts the rendered text, and kills the emulator in an `EXIT` trap. Prefer it
over asking the user to click through the emulator.

```sh
# From the repository root; uses /tmp/opencode/neo-firmware/emulator/neo.
NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware tools/test-neo6502-smoke.sh

# Reuse the binaries from an immediately preceding build.
NEO_SMOKE_SKIP_BUILD=1 NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware \
    tools/test-neo6502-smoke.sh
```

Outputs are under `/tmp/opencode/neo-smoke`: `screen.png`, `decoded.txt`, and
`emulator.log`. The smoke test needs `ruby`, `python3` with Pillow, `xdotool`,
ImageMagick `import`, and an SDL display.

The manual equivalent of the launch step is:

```sh
cd /home/bob/Documents/Projects/neo6502-ozmoo
NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware
mkdir -p /tmp/opencode/neo-smoke
env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -v examples/minizork.z3

# Strip the PRG load address from the interpreter; the story image is already raw.
tail -c +3 temp/ozmoo > temp/ozmoo-neo-main.bin
cp temp/compmem.tmp temp/ozmoo-neo-story.bin

"$NEO_FIRMWARE_ROOT/emulator/neo" cold \
  "$PWD/temp/ozmoo-neo-main.bin@1000" \
  "$PWD/temp/ozmoo-neo-story.bin@4600" \
  run@1000 > /tmp/opencode/neo-smoke/emulator.log 2>&1 &
EMU_PID=$!
```

Do not pipe game input to the emulator's stdin. The loader arguments are
parsed from the command line; game input is SDL keyboard input and must be sent
to the emulator window. Arguments are processed left to right:

- `file@HEX` loads a raw binary at a hexadecimal address.
- `run@HEX` sets the 6502 reset vector to `HEX`; `cold`, `warm` and `exec` set
  it to `$0800`, `$0803` and `$0806`.
- `path:DIR` sets the storage root. The default is `storage` relative to the
  current directory, so run from the repository root or pass an absolute path.
- `trace` prints each executed instruction to stdout.
- `keys` disables the emulator's debugger keys and makes exit `Ctrl+ESC`
  instead of `ESC`.
- `scale=1` through `scale=4` sets the display scale (default `3`).
- A `*.neo` argument loads a Neo container; its execute address comes from the
  header.

Drive the SDL window like this (this is what the smoke script wraps):

```sh
# Wait for the window owned by the emulator process.
WINDOW_ID=""
until [[ -n "$WINDOW_ID" ]]; do
  WINDOW_ID="$(xdotool search --pid "$EMU_PID" 2>/dev/null | head -n 1 || true)"
  sleep 0.2
done
sleep 4                                      # boot delay

send_line() {
  xdotool windowactivate --sync "$WINDOW_ID" # SDL needs explicit activation
  sleep 0.2
  xdotool type --delay 60 -- "$1"
  xdotool key Return
}
send_line "open mailbox"
sleep 5
send_line "read leaflet"
```

The title `Neo6502 Emulator` can also be used with `xdotool search --name` if
the PID is unavailable. Always terminate the emulator you started; the smoke
script does this with `trap cleanup EXIT`.

Capture and decode the console without OCR:

```sh
import -window "$WINDOW_ID" /tmp/opencode/neo-smoke/screen.png
python3 tools/decode_neo_console.py \
  /tmp/opencode/neo-smoke/screen.png \
  "$NEO_FIRMWARE_ROOT/firmware/common/include/interface/font_5x7.h"
```

At the default `scale=3` the window is 1008x840. The decoder's defaults
(`X0=27`, `Y0=60`, `CW=18`, `CH=24`, 53 columns x 30 rows) are derived from the
centred 320x240 display and the 5x7 font; override them with `NEO_SMOKE_X0`,
`NEO_SMOKE_Y0`, `NEO_SMOKE_CW`, `NEO_SMOKE_CH`, `NEO_SMOKE_COLS` or
`NEO_SMOKE_ROWS` only if the scale or geometry changes.

### Debugger and debug-output access

There are four complementary mechanisms; use the least invasive one that
answers the question.

- **SDL debugger keys** (available unless the `keys` loader argument was
  passed): `F6` breaks into the debugger, `F7` single-steps, `F8` steps over,
  `F9` sets a breakpoint at the current code address, `F2` homes the code view
  to PC, `F5` runs, and `TAB` shows the game display while stopped. Hex digits
  `0-9`/`A-F` shift into the inspected address; with `Shift` or `Ctrl` they
  shift into the data address. A `BRK` (`$03`) at PC also stops in the
  debugger. `ESC` exits the emulator.
- **Instruction trace**: add `trace` to the loader command line and capture
  stdout. This is useful for narrow paging or branching bugs, but very noisy.
- **Firmware debug port**: System group 1, function 10 writes one character to
  the debug port. On the emulator that is `stderr`, so redirect both streams
  as in the launch command above. The API registers are `$FF00` (group,
  writing it triggers dispatch), `$FF01` (function), and `$FF04`..`$FF09`
  (parameters). Example, emitting `A`:

  ```asm
      lda #$41       ; character
      sta $ff04      ; parameter 0
      ldx #$0a       ; function 10 = write debug char
      lda #$01       ; group 1 = system
      stx $ff01
      sta $ff00      ; trigger
  ```

  Keep temporary calls like this out of committed interpreter code; they were
  used to trace `ZTEXT`/paged reads while fixing the leaflet corruption.
- **BASIC monitor and memory dump**: in a normal `cold`-booted BASIC session
  (not the `run@1000` Ozmoo launch), type `mon` to enter the WozMon-style
  monitor (`\` prompt); a hex address dumps bytes, `.` lists a range, `:`
  stores bytes, `R` runs, and `N` returns to NeoBASIC. On clean exit the
  emulator also writes a 64 KiB `memory.dump` in its working directory, which
  can be inspected with `xxd`.

`temp/acme_labels.txt` is build-artifact-specific. Always rebuild first, then
debug with labels from that exact binary. If code layout changes, refresh the
labels before stepping or inspecting symbols. For Neo text bugs, start at
`.neo_printchar` and its `.neo_flush_word` / `.neo_emit_newline` helpers rather
than the generic buffered path.

For a fast non-graphics sanity check after an assembly-only change, the older
Praxix check is still useful:

```sh
env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -s test/praxix.z5
# At the prompt, run `all` and expect "all tests passed".
```

## Next session reminder

- Minizork now builds and runs on Neo6502 with the flat `storage/ozmoo.story`
  sidecar and direct VMEM page mapping. Re-run `tools/test-neo6502-smoke.sh`
  before changing paging, screen, or input behavior.

## External references for Neo6502 porting

- [Neo6502 documentation](https://neo6502.com/)
- [Using cc65 on Neo6502](https://github.com/paulscottrobson/neo6502-documents/blob/main/neo6502/docs/wiki/Using-CC65.md)
- [Ozmoo Oric porting guide](https://github.com/benedictemarty/ozmoo-oric/blob/oric-port/docs/PORTING_ORIC.md) (process guidance only; not Neo6502 hardware authority)
