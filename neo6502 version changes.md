# Neo6502 version changes

This document describes how this fork differs from upstream Ozmoo. The
comparison point is upstream `master` at `5b990fb` ("Added benchmark
walkthrough for Madman"). This fork is at `60aabf4`; the merge base is the same
upstream commit, so at the time of writing the fork is 50 commits ahead and has
no upstream-only commits. The full diff is 187 files, most of which are vendored
Neo6502 emulator/firmware support material rather than interpreter changes.

The goal of the fork is to add a Neo6502 target without changing the existing
C64, C128, MEGA65, Plus/4, X16 or Z6 builds. Almost all Neo behaviour is behind
`TARGET_NEO6502` in assembly or `$target == 'neo6502'` in `make.rb`; the few
generic differences that are present in the diff are listed at the end.

## Highlights

* New text-only `neo6502` build target.
* Flat, disk-backed VMEM instead of the C64-style banked/cached VMEM.
* Neo firmware (Morpheus) API adapter for console, keyboard, timing and files.
* Native save/restore to `<GAME>.S00`, with comments and slot listing.
* Build-time console palette selection with `-neo-fg` / `-neo-bg`.
* Z1-Z3 status-line inversion and a Neo-specific MORE prompt.
* Quit restores the NeoBasic console and reloads BASIC through the firmware.
* New `.NEO` executable packager, flat release packages and emulator tests.

## Build target and release format

`make.rb` gains a sixth target:

```sh
ruby make.rb -t:neo6502 game.z3
```

The target uses the 65C02 assembly mode, starts code at `$1000`, and uses the
flat 16-bit address space. Only build mode P is accepted; on Neo it is
special-cased to enable VMEM, whereas mode P on the other targets still means
"whole story in memory". REU, `OPTIMIZE_VMEM`, C128/MMU bank flags and the other
build modes are rejected for this target. The top two RAM pages, `$fe00-$ffff`,
are reserved for firmware/Morpheus state.

Neo file names are generated from the story's 8.3-style basename. Each build
writes a flat release directory and zip:

```text
dist/<game>/<GAME>.NEO      interpreter plus resident story
dist/<game>/<GAME>.STORY    complete story file for paged reads
dist/<game>/<GAME>.CFG      VMEM map and save configuration
dist/<game>.zip             archive of the directory above
```

`<GAME>.NEO` is written by `tools/make_neo_executable.py`. It has a `\x03NEO`
header with an execute address of `$1000`, followed by two load blocks: the
interpreter at `$1000` and the resident story image. `make.rb` passes the story
load address explicitly from the assembled `story_start` label in
`temp/acme_labels.txt`, rather than relying on a fixed address. Small Z3 builds
currently land around `$4a00`, while the larger Advent Z5 build uses `$5000`.

The `.CFG` file is padded to at least 512 bytes and to a 256-byte boundary. The
emulator is started with its storage path pointing at the flat release
directory, for example `path:dist/minizork`, rather than a nested `storage/`
directory.

Tracked release packages added by this fork are:

* `dist/minizork.zip`
* `dist/adventz3.zip`
* `dist/Adventz5.zip`
* `dist/planetfall.zip`
* `dist/stationfall.zip`
* `dist/WISHBRIN.zip`
* `dist/zork1.zip`
* `dist/zork2.zip`
* `dist/zork3.zip`

The old `dist/advent.zip` was replaced by `dist/adventz3.zip` when the source
was renamed to `adventz3.z3`; the separate Z5 package is `Adventz5.zip`.

## Firmware API and KERNAL adapter

New files `asm/constants-neo6502.asm` and `asm/neo6502-morpheus.asm` provide the
Neo platform layer. They define the Morpheus API registers at `$ff00-$ff09`,
console vectors at `$ffeb-$fff7`, and the system, console and file-I/O command
groups. The KERNAL entry points used by Ozmoo are redirected to Neo adapters.

The adapter implements:

* console write/read, cursor positioning, clear-screen, line delete and
  palette control;
* non-blocking keyboard input, with Neo backspace/delete codes mapped to the
  CBM DELETE code expected by the interpreter;
* file open, close, seek, tell, read, write, delete and stat;
* command-channel behaviour, including `S:` deletes;
* timer/RNG support based on the firmware timer, with a monotonic jiffy
  fallback;
* bounded API polling so a missing firmware response cannot hang forever.

The console palette is selected with build-time CONWrite control codes: `$80+n`
sets foreground colour and `$90+n` sets background colour. `-neo-fg` and
`-neo-bg` accept a firmware palette index (0-15) or a name such as `white` or
`darkblue`; the defaults are foreground white (7) and background darkblue (4).
This avoids relying on the optional console colour API calls, which are
unreliable on some firmware versions.

## VMEM and memory layout

Neo builds use flat, disk-backed VMEM with 512-byte blocks. `asm/vmem.asm` maps
a resident VMEM block directly to two consecutive RAM pages; there is no REU,
no banked window and no cache path. The VMEM map lives at `$0334-$03ff`, giving
102 two-byte entries. Resident VMEM stops before `$d000`, because the
interpreter still uses the C64-compatible I/O window at `$d020`/`$d021` and
colour RAM at `$d800`. `make.rb` mirrors that budget when it clamps map entries
and preload blocks.

`asm/disk.asm` reads the story sidecar by Z-machine page number, because the
sidecar is the complete story file including dynamic memory. Config reads use
flat 256-byte sector offsets. Disk-swap prompts and the save-device query are
skipped, and device 8 is assumed. `asm/memory.asm` and `asm/zaddress.asm` add
Neo-specific re-resolution at 512-byte block boundaries and keep write checks
enabled so paged statmem cannot be corrupted.

## Console, input and screen handling

`asm/screenkernal.asm` has a dedicated Neo print path. It writes plain ASCII
rather than C64 screen codes, ignores colour RAM writes, and maintains a
53-byte word buffer. Cursor movement flushes the buffer first, spaces and
carriage returns are handled explicitly, and line breaks are counted so the
MORE prompt still appears. Column 51 is kept free for the MORE marker and
column 52 is left unused because writing there makes the firmware auto-wrap and
scroll row 0 away. erase_window clears console rows through the API instead of
writing screen RAM.

Keyboard input is translated between the Z-machine's PETSCII-like characters
and the Neo console's ASCII expectations, including upper/lower case mapping.
Neo does not support custom fonts or PETSCII reverse video; non-English and
accented glyphs are approximated with the firmware font.

### Status line

For Z1-Z3 only, the status line simulates inverse video by swapping the
selected foreground/background palette. The final buffered word is flushed
before the normal colours are restored, so input remains visible. Score needs
10 reserved columns instead of 8 and time needs 18 instead of 16, again to keep
the right-aligned values away from the Neo wrap columns.

### MORE prompt

The Neo MORE prompt draws an inverted `*` at row 29, column 51, waits for a key,
then removes the marker and restores colours and cursor state. It uses the Neo
word buffer and its own newline counting rather than the generic buffered
screen path.

## Save and restore

`asm/save-restore-neo6502.asm` implements native SAVE/RESTORE. Saves are written
to `<GAME>.S00` beside the game's sidecars. The 26-byte header contains:

* `OZMSAV` magic and version 1;
* the slot number;
* a 14-byte uppercase comment;
* the 16-bit save start address;
* the 16-bit payload size.

The payload contains the saved zero-page bytes, stack and dynamic memory. On
RESTORE, all configured slots are listed first with their comment, `(empty)` or
`(invalid)`, before the player chooses a slot. Lowercase characters typed at
the save-comment prompt are folded to uppercase so the C64-style input filter
does not reject them.

## Quit and reset

Quit cannot use the C64 reset vector, which is zero-page RAM during play. The
Neo path instead:

1. restores the NeoBasic default palette (foreground 7, background 0);
2. writes CONWrite clear-screen/home (`12`);
3. asks the firmware system API to reload BASIC (function 3);
4. polls until the command completes;
5. jumps directly to the NeoBasic cold start at `$0800`.

The polling loop lives above the BASIC image. Small builds pad to `$4980`;
larger builds place the loop immediately after the interpreter and let
`story_start` move up. This fixed an Acme "Produced too much code" failure for
Z5 games whose interpreter grew past the old fixed `$4980` trampoline.

Darkmode is not wired to the Neo console palette.

## Tools and tests

New support tools:

* `tools/make_neo_executable.py` builds the `.NEO` format.
* `tools/decode_neo_console.py` decodes emulator screenshots against the
  firmware font for test assertions, including inverse-video row detection.
* `tools/test-neo6502-smoke.sh` boots Minizork, types `open mailbox` and
  `read leaflet`, and checks rendering, status line and prompt.
* `tools/test-neo6502-save-restore.sh` verifies the native save header, comment
  folding, slot listing and restore after an emulator restart.

`tests/test_builds.rb` validates Neo release files, `.CFG` padding, VMEM header
fields, `.NEO` block structure and the story address from the assembler labels.
`tests/Makefile` adds `neo-smoke` and `neo-save-restore`; they are deliberately
not part of `make -C tests all` because they need a Neo firmware checkout and
X11 tools.

`README.md` and `tools/README.md` document the target, palette options, release
layout and emulator tests. `screenshots/neo6502.png` was added. The `neo6502/`
directory vendors emulator binaries, firmware images, BASIC/ROM artefacts,
tool archives and platform examples for local development and testing.

## Other differences from upstream

The following changes are present in the diff but are not Neo-only and should
be reviewed when rebasing onto newer upstream code:

* `asm/disk.asm` no longer prints the extra `$d68b`/`$d6a1` disk-error bytes.
* `asm/vmem.asm` clears `mempointer` in a common return path.
* `make.rb` clamps `vmem_data[3]` for all targets and uses copied
  `build_config_data` / `build_vmem_data` values in all build modes.
* `asm/zaddress.asm` uses `Z6PLUS` where upstream uses `Z8` for a packed-address
  guard.
* `asm/ozmoo.asm` still uses the older `Z6_FCM_WINDOW_BG` form, rather than
  upstream's newer X16 `Z6_WINDOW_BG` / `Z6_TRANSPARENT_BG` and MEGA65
  `Z6_FCM_TEXT_BAKE` handling.
* `asm/screenkernal.asm` differs from upstream in the X16 VERA scroll delay.

No Neo-specific code depends on these differences. They are inherited from the
base used for the port rather than part of the new target.
