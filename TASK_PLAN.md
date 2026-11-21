# Neo6502 Disk-Backed VMEM Implementation Plan

## Goal

Implement disk-backed virtual memory for the Neo6502 target so a Z-machine story can exceed 64 KB resident memory. The first acceptance target is `examples/minizork.z3`, followed by existing Praxix regression behavior.

The implementation is intentionally incremental. Each task below is a standalone prompt for a local 12B model and changes only one primary file. Do not implement later tasks while completing an earlier one.

## Architecture decision

Use a Neo6502-specific VMEM build without claiming that every existing `MODE_*` image format works:

- Keep Neo builds in the existing build-mode `P` selection initially; `P` becomes a Neo host-mode containing the interpreter plus preload/dynmem data, while statmem is read on demand from `storage/ozmoo.story`.
- Set `$VMEM = true` for Neo6502 in `make.rb` rather than explicitly disabling it.
- Generate `storage/ozmoo.story` as the complete story sidecar for paged loads.
- Generate `storage/ozmoo.cfg` in VMEM format; Neo `read_track_sector` and `readblock` must consume it and the story sidecar.
- Preserve the Neo flat-memory model: no C128-style banks, no REU, no `first_banked_memory_page` cache fallback, and no 6510 memory windows.
- Keep a 512-byte VMEM block and two 256-byte disk blocks per VMEM block.
- Keep dynmem resident. Only statmem may be paged.
- Do not add a second storage format unless a later task proves the existing sidecars insufficient.

This plan does not require implementing all Ozmoo disk build modes. It requires that the Neo target no longer reject large stories solely because the complete story does not fit resident RAM.

## Existing invariants

- Z-machine address state is a 3-byte address: `(z_address/z_pc high, mid, low)`.
- `read_byte_at_z_address(a,x,y)` inputs are high/mid/low and returns the byte in `A`; `mempointer` must point to the matching 256-byte physical page after the call.
- Dynmem is resident at `>story_start + z-page` for Z-pages below `nonstored_pages`.
- VMEM block size is 512 bytes.
- Each VMEM map entry consists of a high/tick byte and a low-byte Z-machine block number.
- `readblocks_numblocks`, `readblocks_currentblock`, and `readblocks_mempos` describe a disk-to-RAM read in `asm/disk.asm`.
- `neo_readblock` currently calculates its story offset and reads a 256-byte page through Morpheus file API file 2.
- `neo_read_track_sector` currently reads from `ozmoo.cfg` through Morpheus file API file 3.
- Neo KERNAL file channels 2 and 3 are used for story/config sidecars.

## Acceptance criteria

The complete feature passes when:

1. `env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -s test/praxix.z5` still builds and passes `help`/`all`.
2. `env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -s examples/minizork.z3` builds without `The whole story doesn't fit in memory`.
3. The Neo emulator loads the generated interpreter and sidecars and reaches the MiniZork prompt.
4. At the MiniZork prompt, basic navigation/inspection such as `look`, `inventory`, and `quit` completes.
5. VMEM misses do not corrupt `z_pc`, `z_pc_mempointer`, `mempointer`, or dynmem.
6. No Neo VMEM path uses C128 bank registers, REU operations, or C64/C128 hardware memory banking.

## Task 1 - Remove the Neo P-mode/VMEM contradiction

**Primary file:** `make.rb`

**Standalone prompt:**

In `make.rb`, make build mode P compatible with Neo disk-backed VMEM instead of using P exclusively as whole-story in-memory mode.

1. Locate the Neo target restriction around `if mode != MODE_P and $target == 'neo6502'` and the target-only assignment at `$VMEM = ...`.
2. Change `$VMEM` assignment so Neo6502 is included in VMEM builds. For now, use VMEM for Neo whenever the build is not Mega65/X16/ZIP semantics, but do not let Neo automatically enable `OPTIMIZE_VMEM` or REU.
3. Keep the Neo default mode P unless a later task explicitly adds a Neo-supported disk build mode.
4. Locate `build_P` and remove or isolate the size check `if $dynmem_and_vmem_size_bank_0 < $story_size` for Neo. It must remain for C64/P builds.
5. Under Neo P-mode VMEM, `build_P` must continue building an interpreter plus resident/preloaded data; it must not attempt to copy the complete story into that resident block.
6. Ensure `-p` remains either accepted with a zero/limited preload value or explicitly guarded. Do not allow `-p` assumptions that require REU or unsupported multi-disk layouts.
7. Keep `$no_sector_preload` behavior compatible with VMEM; the build can use sector preload metadata but must be able to continue with zero preloaded statmem blocks.

**Inputs:**
- `$target`
- `$VMEM`
- `mode`
- `$dynmem_and_vmem_size_bank_0`
- `$story_size`
- `$dynmem_blocks`
- `$story_file_data`
- `preload_max_vmem_blocks`

**Outputs:**
- `$VMEM` true for Neo P builds.
- Neo P build continues even if the story is larger than resident memory.
- Existing C64/P behavior remains unchanged.
- Existing `S1/S2/D2/D3/71/81/ZIP` Neo restrictions remain in place unless a later task changes them.

**Edge cases:**
- No preload data: `vmem_data` must still represent every resident VMEM mapping slot available.
- Zero resident statmem blocks: VMEM startup must not assume a nonzero preload list.
- A story just under resident capacity must remain a valid P-like build.
- Do not calculate Neo resident capacity with C64 banking pages.

**Validation:**
- `ruby make.rb -t:neo6502 -s test/praxix.z5` builds.
- `ruby make.rb -t:neo6502 -s examples/minizork.z3` passes the old size gate and reaches sidecar generation.

## Task 2 - Compute a Neo VMEM resident layout

**Primary file:** `make.rb`

**Standalone prompt:**

Add a Neo-only resident-layout calculation, isolated from C64/C128 disk layout code.

1. Keep story data in 512-byte Z-machine blocks.
2. Calculate `$dynmem_blocks` from the Z-machine header/static-memory boundary using the existing Ozmoo machinery.
3. Calculate total 512-byte story blocks.
4. Calculate the maximum resident statmem 512-byte blocks based on the Neo 16-bit PRG/layout and the available VMEM RAM range, excluding dynmem, stack, cache, config, and interpreter-overlap areas.
5. `vmem_data[2]` must remain the number of suggested VMEM entries.
6. `vmem_data[3]` must remain the number of resident/preloaded blocks and must never exceed `vmem_data[2]` or the Neo resident map capacity.
7. If no statmem can remain resident, set `vmem_data[2]`/`vmem_data[3]` to their practical zero or minimal values, while preserving a valid map header.

**Inputs:**
- `$story_file_data`
- `$story_size`
- `$VMEM_BLOCKSIZE`
- `$dynmem_blocks`
- `$CACHE_PAGES`
- `$stack_pages`
- Neo constants from `asm/constants-neo6502.asm`

**Outputs:**
- A valid Neo VMEM map/preload layout without C64 disk-track assumptions.
- `vmem_data[2]` = suggested block count.
- `vmem_data[3]` = preloaded resident block count.
- `preload_max_vmem_blocks` clamped to the real Neo resident block budget.

**Edge cases:**
- Odd final story size not divisible by 512: pad only in build output, never change Z-address semantics.
- Z3 story size 128 KB maximum; Z5 256 KB; Z6-Z8 512 KB.
- Map entry storage must fit `vmap_buffer_start..vmap_buffer_end`.
- `cache_pages` must not be counted as VMEM resident story blocks.

**Validation:**
- Rebuild Praxix and compare the resident block count against the existing P baseline.
- Build MiniZork and ensure `vmem_data[3]` is within available Neo RAM.

## Task 3 - Generate Neo VMEM sidecars from resident and full-story data

**Primary file:** `make.rb`

**Standalone prompt:**

Rewrite only the Neo-specific sidecar output block near the final build dispatch.

1. For Neo VMEM builds, write `storage/ozmoo.story` as the full `$story_file_data`, not only `vmem_contents` or dynmem.
2. Keep the existing P build behavior for Neo non-VMEM builds: full story data is the P sidecar.
3. Write `storage/ozmoo.cfg` for VMEM builds by starting with `config_data`, appending `vmem_data`, and padding as needed.
4. Preserve the existing minimum/padding behavior for `ozmoo.cfg` used by `neo_read_track_sector`.
5. Do not include C64 disk-image track maps as if they were Neo storage offsets.
6. Preserve the existing complete-story sidecar path for P mode until Task 1 proves it is safe to replace.

**Inputs:**
- `$target`
- `$VMEM`
- `$story_file_data`
- `$vmem_contents`
- `config_data`
- `vmem_data`

**Outputs:**
- `storage/ozmoo.story` full 512-page-readable story in VMEM mode.
- `storage/ozmoo.cfg` valid VMEM metadata in VMEM mode.
- Existing P Praxix output remains the full-story sidecar.

**Edge cases:**
- Missing `storage/` directory: create it before `File.binwrite`.
- Empty/full story: reject or fatal-build on zero-byte story data.
- Config padding must not overwrite the config header.
- VMEM map size in bytes must not exceed 512 bytes.

**Validation:**
- Inspect `ozmoo.story` size and prefix bytes against `$story_file_data`.
- Inspect `ozmoo.cfg` and verify its VMEM header length and entry arrays are present.

## Task 4 - Add 16-bit Morpheus seek/read primitives

**Primary file:** `asm/neo6502-morpheus.asm`

**Standalone prompt:**

Add or harden low-level Morpheus file seek/read primitives needed by VMEM block paging. Reuse `neo_kernal_api_call`, `neo_api_param0..param5`, and existing channel/file-state variables.

Define/implement these ACME labels:

- `neo_kernal_seek_file` — inputs: `A=LFN`, `X=seek-low 16-bit offset`, `Y=seek-high 16-bit offset`; output: C set on error, status in `neo_kernal_status`; no other disk register contract.
- `neo_kernal_read_file` — inputs: `A=LFN`, `X=<destination-page/low address?>`, `Y=>destination-page/high address?>`, with length fixed or explicit; output: C set on error, bytes returned in `A/X/Y` or a single existing `neo_kernal_size` word.

Use the actual existing convention already used by `neo_readblock`: `neo_api_param0` channel, `neo_api_param1/2` destination, `neo_api_param3/4` 16-bit length, `neo_api_param5` unused. A 256-byte read is length `$0100` in param3/4.

**Inputs:**
- Story/config channel LFN
- Absolute 16-/24-bit story offset
- Destination 16-bit RAM page address
- 256-byte or 512-byte block length

**Outputs:**
- C clear on success and `neo_kernal_status=0`; C set on Morpheus/API or EOF failure.
- Destination memory filled for exactly the requested byte count.

**Edge cases:**
- Offset crosses a 64 KB page boundary.
- Destination address is page-aligned.
- API error/timeout after a `seek` or `read`.
- Defensive close must not overwrite successful read status.
- Preserve `X/Y` for callers only where existing Ozmoo calling conventions require it.

**Validation:**
- Build only; then add emulator smoke reads for 256-byte blocks 0 and 1.
- Use a known MiniZork header/page and verify no read fills with zeros outside EOF.

## Task 5 - Correct Neo story offset mapping

**Primary file:** `asm/disk.asm`

**Standalone prompt:**

Complete and isolate `neo_readblock` in `asm/disk.asm` so it maps a Z-machine 256-byte block to an absolute 256-byte story sidecar offset.

1. Preserve the existing `readblock` adjustment: `readblocks_currentblock_adjusted = readblocks_currentblock - nonstored_pages`.
2. For Neo, if `readblocks_currentblock_adjusted` is negative/carry-set, fatal-error rather than reading a resident/dynmem address as statmem.
3. Use the adjusted 16-bit offset as 256-byte block units.
4. Convert it to an absolute byte offset: `block-index * 256`.
5. Call Morpheus seek with channel 2 and the destination `readblocks_mempos`.
6. Read exactly 256 bytes.
7. Close channel 2 only after success or use defensive close semantics already in `neo_kernal_close`.

**Current labels/functions:**
- `readblock`
- `readblocks_currentblock`
- `readblocks_currentblock_adjusted`
- `readblocks_mempos`
- `neo_readblock`
- `neo_open_story_file`

**Inputs:**
- `A/X/Y` not relied upon across calls.
- `readblocks_currentblock` = Z-machine 256-byte page index.
- `nonstored_pages` = first statmem 256-byte page index.
- `readblocks_mempos` = destination 16-bit RAM address.

**Outputs:**
- C clear on success.
- `readblocks_mempos` unchanged by `neo_readblock`.
- One 256-byte page loaded at the destination.

**Edge cases:**
- File offset exceeds 24-bit/16-bit arithmetic capacity.
- Story block 0-1 can be dynmem and should never call this routine.
- EOF or short read must set the existing fatal disk error path.
- The two VMEM pages in a 512-byte block must remain independently readable.

**Validation:**
- Praxix statmem page reads complete through VMEM and `all` passes.
- MiniZork reaches prompt and `look` returns story text.

## Task 6 - Add Neo config metadata reads

**Primary file:** `asm/disk.asm`

**Standalone prompt:**

Make `neo_read_track_sector` reliably read 256-byte sectors from `storage/ozmoo.cfg` and ensure the config/VMEM list is initialized once.

1. Preserve the existing `neo_open_config_file` channel 3 setup.
2. Interpret its current 256-byte sector addressing as a byte offset: `sector * 256 + track` only if a later format audit proves track contributes; for first implementation, keep the existing sector variable behavior and document it as an offset sector.
3. Seek channel 3 to `sector * 256`.
4. Read exactly 256 bytes into `readblocks_mempos`.
5. If the generated VMEM config size is below 512 bytes, preserve the existing build padding and close behavior.
6. Return C clear on success, C set on seek/read/EOF error.

**Inputs:**
- `A=track`, `X=sector`, `Y=device#` in `read_track_sector`.
- `readblocks_mempos` destination.
- `disk_info` config sector metadata, if present.

**Outputs:**
- One 256-byte config sector loaded.
- Existing startup `prepare_static_high_memory` can parse the loaded config at `config_load_address`.

**Edge cases:**
- Config file missing.
- Config file shorter than requested sector.
- Config VMEM metadata crossing 256-byte boundaries.
- 16-bit sector index overflow in the current C64 disk abstraction.

**Validation:**
- Startup loads a nonzero VMEM block count.
- Praxix and MiniZork both have valid `vmap_used_entries`.

## Task 7 - Enforce flat-memory VMEM allocation

**Primary file:** `asm/vmem.asm`

**Standalone prompt:**

Complete the Neo-specific removal of all C64/C128 bank/cache assumptions in VMEM.

1. In `vmem.asm`, keep `vmem_blocksize = 512` and enforce it with a Neo compile-time error.
2. Add explicit Neo branches in every resident-map calculation, cache check, old-block eviction, and page replacement path.
3. Define one Neo invariant: every resident VMEM physical address is a normal 6502 page address and `mempointer` is exactly 16-bit `(high=page, low=0)`.
4. In `load_blocks_from_index`, Neo must always call the non-cache `readblocks`/`readblock` load path unless cache buffering is needed for a two-page 512-byte load.
5. In `read_byte_at_z_address`, dynmem remains the direct story-start page mapping.
6. Add explicit Neo handling for `vmem_offset_in_block = 0/1` and 512-byte block replacement.
7. Ensure no Neo branch falls through to C128 `vmem_cache_bank_index` or REU/REUBOOST code.

**Inputs:**
- `A/X/Y` Z-machine address conventions.
- `vmap_*`, `nonstored_pages`, `vmem_offset_in_block`, `vmem_cache_*`.

**Outputs:**
- `mempointer` 16-bit physical pointer to a resident 256-byte page.
- `A` contains the requested byte.
- VMEM map and resident cache remain internally consistent.

**Edge cases:**
- Requested block is resident and already mapped.
- Block miss with no free vmap entry.
- PC points to the block being replaced.
- Cache page points to the block being replaced.
- 512-byte block spans two resident 256-byte pages.
- Z-page equals dynmem boundary `nonstored_pages`.

**Validation:**
- Praxix `all` passes.
- MiniZork `look` and repeated room transitions pass.
- Neo build has no runtime branch into C128 bank state.

## Task 8 - Fix PC address updates at 256-byte boundaries

**Primary file:** `asm/memory.asm`

**Standalone prompt:**

Review and harden the Neo/VMEM behavior of:

- `set_z_pc`
- `inc_z_pc_page`
- `get_page_at_z_pc`

Do not change C64/C128 semantics unless a shared bug is proven by a runtime invariant.

For Neo VMEM:

1. `set_z_pc` must update `z_pc` and call `get_page_at_z_pc` or ensure `z_pc_mempointer` is valid before executing the next byte.
2. `inc_z_pc_page` must increment `z_pc`/`z_pc_mempointer` consistently across 256-byte page boundaries and call `get_page_at_z_pc` at block/cache boundaries.
3. `get_page_at_z_pc` must normalize `mempointer` and `z_pc_mempointer` to the resident physical page containing the Z-PC.
4. Fast same-page/same-block behavior must not retain a stale pointer after a VMEM block swap.
5. Preserve Y=0 when `get_page_at_z_pc` returns, matching existing Z-PC reader macro behavior.

**Inputs:**
- Initial Z-PC in `a,x,y` for `set_z_pc`.
- Current `z_pc` and resident maps for page increment.
- Z-PC Z-machine address for `get_page_at_z_pc`.

**Outputs:**
- `z_pc_mempointer` points to the correct resident 256-byte page.
- `z_pc` remains the correct 3-byte Z-machine address.
- `Y=0` on normal exits.

**Edge cases:**
- Page increments from `$ff` to `$0100` and 24-bit Z-address carries.
- VMEM block swap while Z-PC is in the swapped block.
- Z-PC in dynmem versus statmem.
- Z-PC in one 256-byte half of a 512-byte block.
- A call/return changes Z-PC outside the cached block.

**Validation:**
- Praxix opcode suite passes.
- MiniZork executes a `call`/`return`, string text, object data, and dictionary lookup across VMEM misses.

## Task 9 - Initialize Neo VMEM startup state

**Primary file:** `asm/ozmoo.asm`

**Standalone prompt:**

Update Neo VMEM startup and ensure `calc_dynmem_size`, config loading, VMEM initialization, and first Z-PC mapping happen in the correct order.

For Neo:

1. `!ifdef TARGET_NEO6502` must leave `SUPPORT_REU=0` and never use REU/REUBOOST.
2. After `calc_dynmem_size`, set `vmap_first_ram_page` from `nonstored_pages + >story_start`.
3. Set `vmap_unbanked_blocks = vmap_max_entries` or a more precise resident block count.
4. Call `prepare_static_high_memory` before `insert_disks_at_boot`/VMEM first-load operations.
5. Ensure startup loads/initializes resident/preloaded statmem blocks through the Neo disk/config path.
6. The first Z-PC setup must call `set_z_pc` and obtain a valid resident pointer.
7. Keep existing Neo P startup output and clear-screen behavior; do not add C64 startup/disk prompts.

**Inputs:**
- Story header static-memory address.
- `config_load_address`/`ozmoo.cfg` data.
- `vmap_max_entries`, `vmap_used_entries`, `nonstored_pages`.
- Initial Z-PC from header.

**Outputs:**
- Valid resident/page-map state before `z_execute`.
- Valid initial Z-PC pointer.
- No REU mode or C128 setup.

**Edge cases:**
- No VMEM preloads.
- Config VMEM metadata truncated or out of range.
- Initial Z-PC points at dynmem or statmem.
- Story static-memory boundary is not 256-byte/512-byte aligned.
- Header read occurs before dynmem is complete.

**Validation:**
- Praxix startup reaches prompt.
- MiniZork startup reaches prompt.
- No C128/MMU or REU initialization functions execute.

## Task 10 - Define Neo Z-address mapping invariants

**Primary file:** `asm/zaddress.asm`

**Standalone prompt:**

Add no platform-specific pointer memory unless needed. Hardening is limited to ensuring Neo flat-memory address increments/remapping feed `read_byte_at_z_address`/`write_next_byte` correctly.

1. Verify `set_z_address` stores Z-address high/mid/low and never modifies Neo banking state.
2. Verify `read_next_byte` increments high/mid/low correctly and reads the next byte through `read_byte_at_z_address`.
3. Verify `dec_z_address` and `skip_bytes_z_address` can perform carry/borrow without triggering X16 or C128 branches.
4. Ensure `set_z_paddress` converts packed addresses using Z-version multipliers correctly.
5. Ensure `write_next_byte` only writes dynmem; writing statmem remains a checked fatal error.
6. Ensure `mempointer` low/high words do not retain stale bytes after a mapped read.

**Inputs:**
- Z-address 3-byte `(high,mid,low)`.
- Packed address in `A/X` for `set_z_paddress`.
- Byte value in `A` for `write_next_byte`.

**Outputs:**
- Correct next/previous Z-address state.
- Correct byte read/write.
- No Neo bank state.

**Edge cases:**
- Address increment/borrow across 24-bit boundaries.
- Z6/Z7 string/routine offsets.
- Packed address conversion overflow.
- Write above dynmem.
- Read exactly at dynmem/statmem boundary.

**Validation:**
- Run Praxix suite and MiniZork text/object/string operations.
- Compile Z3, Z5, and Z6 baseline builds if feasible.

## Task 11 - Add Neo build diagnostics and test commands

**Primary file:** `make.rb`

**Standalone prompt:**

Add concise diagnostics for Neo VMEM builds without changing non-Neo output.

Print on verbose builds:

- Total story bytes and 512-byte block count.
- Dynmem bytes/blocks.
- Resident/preloaded VMEM blocks.
- VMEM map entry count and bytes.
- Paged statmem block count.
- Story sidecar and config sidecar paths and sizes.

Also guard runtime-incompatible combinations:

- Neo + VMEM + REU: fatal build-time combination.
- Neo + VMEM + C128 bank constants: fatal build-time combination.
- Neo + `OPTIMIZE_VMEM`: initially unsupported unless implementation explicitly removes C64 optimization assumptions.
- Neo VMEM resident block count greater than `vmap_max_entries`: clamp or fatal.

**Inputs:**
- Existing build variables and `$VMEM`/`$target`.
- Sidecar files after generation.

**Outputs:**
- Clear Neo build log.
- Fail-fast build errors for unsupported combinations.
- No behavior change for non-Neo targets.

**Validation:**
- Verbose Praxix build lists expected resident/paged values.
- Verbose MiniZork build shows paged statmem and no REU/optimization mode.

## Task 12 - Add VMEM runtime smoke coverage

**Primary file:** `tests/test_builds.rb`

**Standalone prompt:**

Extend build tests to cover Neo VMEM assembly and MiniZork sidecar production.

Add tests that:

1. Execute/validate a Neo Praxix VMEM build if VMEM is enabled by the Neo build path.
2. Build MiniZork as Neo VMEM and assert the build exits successfully.
3. Assert `storage/ozmoo.story` exists and is at least the original story size or padded to VMEM granularity.
4. Assert `storage/ozmoo.cfg` exists and contains a valid VMEM header length.
5. Assert no mode-P whole-story-size rejection occurs for MiniZork.
6. Keep emulator runtime checks separate/conditional if the test environment lacks the Neo emulator.

**Inputs:**
- Test story paths.
- Neo executable/emulator availability.
- Storage sidecar paths.

**Outputs:**
- Repeatable build checks for Neo VMEM.
- Clear failures for missing sidecars or rejected builds.

**Edge cases:**
- Emulator absent.
- `storage/` stale files from prior builds.
- Story smaller/larger than resident capacity.
- Config sidecar stale and not regenerated.

**Validation:**
- `make -C tests` passes.
- MiniZork Neo build test passes in CI/build environments without runtime emulator.

## Recommended implementation order

1. Task 1: build flag/layout gating.
2. Task 2: calculate layout.
3. Task 3: write complete sidecars.
4. Task 4: Morpheus seek/read primitive verification.
5. Task 5: correct story offset mapping.
6. Task 6: config metadata reads.
7. Task 7: flat VMEM core.
8. Task 8: Z-PC/boundary behavior.
9. Task 9: startup order.
10. Task 10: Z-address edge cases.
11. Task 11: diagnostics.
12. Task 12: tests.

Do not combine Task 1 and Task 7 in a first implementation: first prove that the build pipeline emits sidecars and that an existing story can remain non-VMEM/P unchanged, then enable VMEM by flag.