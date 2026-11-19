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

## External references for Neo6502 porting

- [Neo6502 documentation](https://neo6502.com/)
- [Using cc65 on Neo6502](https://github.com/paulscottrobson/neo6502-documents/blob/main/neo6502/docs/wiki/Using-CC65.md)
- [Ozmoo Oric porting guide](https://github.com/benedictemarty/ozmoo-oric/blob/oric-port/docs/PORTING_ORIC.md) (process guidance only; not Neo6502 hardware authority)
