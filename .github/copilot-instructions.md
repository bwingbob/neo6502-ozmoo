# Neo6502 port

This project ports Ozmoo to the OLIMEX Neo6502. Preserve the upstream
interpreter core and isolate machine-specific code behind Ozmoo's existing
target-selection and conditional-assembly patterns.

Ozmoo's existing build uses Ruby and the ACME assembler. cc65 is the Neo6502
C toolchain; it does not replace ACME for the existing interpreter build.

## Architecture and porting

- `asm/ozmoo.asm` sources the interpreter and selects code using ACME
  conditionals. `make.rb` derives target, Z-machine version, and feature
  defines; C64 is the default target. Check all affected configurations when
  changing shared code.
- The interpreter core is in `zmachine.asm`, `stack.asm`, `memory.asm`, and
  `vmem.asm`. Screen, input, disk, and memory-map code are target-sensitive;
  inspect the existing target branches and `constants*.asm` before adding a
  Neo6502 implementation.
- Version 6 uses `screen-z6.asm` and `screenkernal-z6.asm`, rather than the
  non-v6 screen files. Check the Z-machine specification for version-specific
  opcode behavior. Optional operands must be guarded by `z_operand_count`:
  the operand array is not cleared between instructions.
- Keep target-specific memory, display, and I/O assumptions out of shared
  interpreter paths. Changes to shared zero-page layouts must account for all
  target-specific constants files.

## Build and verification

- Run `ruby make.rb` without arguments for build options. The `-s` option
  starts an emulator; the Makefile's emulator targets may require additional
  local tools or game files.
- For shared changes, exercise both v6 and non-v6 builds across affected
  existing targets. `examples/dejavu.z3` and `test/praxix.z5` are regression
  inputs; `testz6.inf` can be compiled with Inform and compared with Frotz.
  Screen changes also need runtime comparison, not just successful assembly.
- `tests/Makefile` provides build checks; `test/` contains conformance games
  that can be played manually. `temp/acme_labels.txt` is overwritten by each
  build, so use labels from the exact binary being debugged.
- Documentation sources are in `documentation/manual/`; when changing
  shipped manuals, rebuild the corresponding generated PDFs with its Makefile.

`CLAUDE.md` has detailed architecture and debugging notes, especially for v6.
Its branch-specific history and local tool paths may not describe this checkout;
verify them against the current files and branch.

Consult these references when designing or implementing the port:

- [Neo6502 documentation](https://neo6502.com/)
- [Using cc65 on Neo6502](https://github.com/paulscottrobson/neo6502-documents/blob/main/neo6502/docs/wiki/Using-CC65.md)
- [Ozmoo Oric porting guide](https://github.com/benedictemarty/ozmoo-oric/blob/oric-port/docs/PORTING_ORIC.md)

Use the Oric guide for porting approach and context, not as a source of
Neo6502 hardware APIs: verify those against the Neo6502 documentation.
