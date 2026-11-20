# Neo6502 port guidance

This repo (`origin`: `bwingbob/neo6502-ozmoo`) is a Neo6502-focused fork of Ozmoo (`upstream`: `johanberntsson/ozmoo`). Keep upstream-compatible changes separate from Neo6502-specific work, and do not push without explicit permission.

## Current state and intent

- Neo6502 target is **not implemented yet**. Treat this as a porting/design phase.
- Preserve interpreter core behavior; isolate new platform logic behind existing target/version conditionals.
- Verify Neo6502 hardware/software interfaces directly before committing to memory map, loader, I/O, or screen assumptions.

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
- Avoid stack manipulation side effects inside Neo print routines (extra `PLA/PHA` in mid-flow caused severe output corruption during testing).
- ACME branch distance is a recurring risk in large target-specific blocks; prefer short local conditional branches plus explicit `jmp` fallbacks when needed.

### Quick runtime verification used in this repo

- Build + run smoke check used repeatedly during Neo debugging:
  - `env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -s test/praxix.z5`
- Emulator command path used by current build flow:
  - `./neo6502/neo temp/ozmoo-neo.bin@801 cold`
- Functional runtime check used as acceptance:
  - At prompt, run `all` in Praxix and confirm it completes with "all tests passed".

### Debugger notes (Neo6502 + ACME)

- `temp/acme_labels.txt` is build-artifact-specific. Always rebuild first, then debug with labels from that exact build output.
- If code layout changes (especially in `asm/screenkernal.asm` Neo blocks), label addresses and branch distances change; refresh labels before stepping/inspecting symbols.
- Prefer debugging Neo text issues from `.neo_printchar` and its helpers (`.neo_flush_word`, `.neo_emit_newline`) rather than generic buffered output paths.
- When behavior differs between build-only and emulator runtime, validate against the same produced binaries loaded by:
  - `./neo6502/neo temp/ozmoo-neo.bin@801 cold`
- For runtime regressions, use Praxix prompt-driven checks (`help`, `all`) as fast end-to-end assertions after single-file assembly changes.

## Next session reminder

- Priority next step: implement Neo6502 VM/paging support so larger stories (for example `examples/minizork.z3`) can build/run without the current mode-P in-memory size failure.
- Current known blocker: Neo target is currently restricted to build mode `P`, which requires the whole story to fit in RAM.

## External references for Neo6502 porting

- [Neo6502 documentation](https://neo6502.com/)
- [Using cc65 on Neo6502](https://github.com/paulscottrobson/neo6502-documents/blob/main/neo6502/docs/wiki/Using-CC65.md)
- [Ozmoo Oric porting guide](https://github.com/benedictemarty/ozmoo-oric/blob/oric-port/docs/PORTING_ORIC.md) (process guidance only; not Neo6502 hardware authority)
