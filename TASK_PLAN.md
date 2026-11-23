# Neo6502 Native Save/Restore — Small Implementation Prompts

Use one prompt at a time. Give the model only one numbered prompt, let it finish, review the diff, then continue to the next prompt.

All prompts assume this repository:

```text
/home/bob/Documents/Projects/neo6502-ozmoo
```

Common rules:

- Keep all commits local. Do not push.
- Do not change C64, C128, Mega65, Plus/4, or X16 behavior.
- Do not generate or commit files under `dist/`.
- Use ACME assembly syntax.
- If a named label or file cannot be found, stop and report instead of guessing.

---

## Prompt 1 — Disable the Neo save-device prompt

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/disk.asm.

Find the routine named `maybe_ask_for_save_device`.

Add this as the first code inside that routine, before any existing code:

    !ifdef TARGET_NEO6502 {
        lda #8
        sta disk_info + 4
        clc
        rts
    }

Do not change the existing code for other targets. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 2 — Skip Neo disk-swap messages

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/disk.asm.

Find `.insert_save_disk` and `.insert_story_disk` inside the save/restore zone.

At the very start of `.insert_save_disk`, add a TARGET_NEO6502 branch that stores 0 into `.last_disk` and jumps to `.dont_print_insert_save_disk`.

At the very start of `.insert_story_disk`, add a TARGET_NEO6502 branch that returns immediately with RTS.

Do not change behavior for other targets. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 3 — Disable Ctrl-D on Neo

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/text.asm.

Find the Ctrl-D handler:

    cmp #4 ; Ctrl-D to forget device# for saves
    bne +
    dec ask_for_save_device
    jmp .did_something

Wrap only those four lines in:

    !ifndef TARGET_NEO6502 {
        ...existing Ctrl-D lines...
    }

Leave the surrounding Ctrl-K and Ctrl-U handling unchanged.

Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 4 — Update the Neo splash hint

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/splashlines.tpl.

Find `splashline6`.

Add a `TARGET_NEO6502` branch after the `TARGET_X16` branch and before the `SHOWUNDO` branch.

If `SHOWUNDO` is defined for Neo, display:

    !pet " Ctrl: K=Key repeat U=Undo",0

Otherwise display:

    !pet "   Ctrl: K=Key repeat",0

Do not change the text for other targets. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 5 — Generate the Neo save-slot filename

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/make.rb.

Find the Neo-only block that writes `temp/neo-file-names.asm`. It currently defines `neo_story_filename` and `neo_config_filename`.

Add a third generated label using the same `neo_base` value:

    neo_save_filename
        !text "<GAME>.S00"
    neo_save_filename_len = * - neo_save_filename

Replace `<GAME>` with the same uppercase 8-character base used for the story filename. For MiniZork this must produce `MINIZORK.S00`.

Use Ruby interpolation in the existing heredoc, matching the style of the story/config names.

Do not change any other generated files. Do not change any other target.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3
    grep -n 'neo_save' temp/neo-file-names.asm

Report the exact diff, the generated lines, and the build result. Do not push commits.
```

---

## Prompt 6 — Add Neo file-stat constants

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/constants-neo6502.asm.

In the Neo API function constants section, add:

    neo_api_fn_file_stat = $10

Near the Neo error constants, add:

    neo_api_error_no_file = $11

Do not change existing constants. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 7 — Add a Neo file-stat helper

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/neo6502-morpheus.asm.

Add a new routine named `neo_kernal_file_stat` near `neo_kernal_write_file_byte`.

Contract:

- Input: A/X/Y = pointer to a length-prefixed filename string.
- Output: C clear if the file exists.
- Output: `neo_api_param0..neo_api_param3` contain the 32-bit file length.
- Output: `neo_api_param4` contains the attribute bitfield.
- Output: C set if the API call fails.

Implementation:

- Put A into `neo_api_param0`.
- Put X into `neo_api_param1`.
- Put Y into `neo_api_param2`.
- Put 0 into `neo_api_param3`, `neo_api_param4`, and `neo_api_param5`.
- Call group `neo_api_group_fileio`, function `neo_api_fn_file_stat`, using `neo_kernal_api_call`.
- Return directly with that routine's carry/status.

Do not change any existing routine. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 8 — Add a bulk Neo file-write helper

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/neo6502-morpheus.asm.

Add a new routine named `neo_kernal_write_file` immediately after `neo_kernal_read_file`.

Copy the structure of `neo_kernal_read_file`, but use function `neo_api_fn_file_write`.

Contract:

- A = file channel.
- X = source address low byte.
- Y = source address high byte.
- `neo_kernal_size` and `neo_kernal_size + 1` contain the requested byte count.
- C clear means all bytes were written.
- C set means API error or short write.

Implementation:

- param0 = A.
- param1 = X.
- param2 = Y.
- param3 = requested count low.
- param4 = requested count high.
- param5 = 0.
- Call group `neo_api_group_fileio`, function `neo_api_fn_file_write`.
- On API error, return with C set.
- Compare returned param3/param4 with the requested count.
- If equal, set `neo_kernal_status = 0`, clear C, and return.
- If short, copy returned count into `neo_kernal_size`, set `neo_kernal_status = neo_api_error_eof`, and return with C set.

Do not change `neo_kernal_read_file`. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 9 — Create and include the Neo save/restore module

```text
Create a new file:

    /home/bob/Documents/Projects/neo6502-ozmoo/asm/save-restore-neo6502.asm

The file should initially contain only:

    ; Neo6502-native SAVE/RESTORE helpers.
    ; This file is sourced inside disk.asm's save_restore zone.

Do not add a `!zone` line to this file.

Then edit /home/bob/Documents/Projects/neo6502-ozmoo/asm/disk.asm.

Find the closing line:

    } ; end zone save_restore

Immediately before that line, add:

    !ifdef TARGET_NEO6502 {
        !source "save-restore-neo6502.asm"
    }

Do not change any other code. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 10 — Add the Neo save header buffer and filename builder

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/save-restore-neo6502.asm.

Add these storage bytes:

    neo_save_header !fill 26, 0

Add a routine named `neo_build_save_filename`.

Contract:

- Input: A = slot digit as ASCII, for example `$30` for slot 0.
- Output: `neo_kernal_lpref_name` contains the length-prefixed save filename.
- The filename length must come from `neo_save_filename_len`.
- The last character must be replaced with the value in A.

Implementation steps:

1. Copy `neo_save_filename_len` bytes from `neo_save_filename` into `neo_kernal_lpref_name + 1`.
2. Store `neo_save_filename_len` into `neo_kernal_lpref_name`.
3. Store A into `neo_kernal_lpref_name + neo_save_filename_len`.
4. Return with C clear.

Use X as the copy index. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 11 — Add the Neo save-header writer

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/save-restore-neo6502.asm.

Add a routine named `neo_write_save_header`.

Contract:

- Input: A = slot digit as ASCII.
- Uses the existing `.inputstring` buffer for the 14-character comment.
- Fills all 26 bytes of `neo_save_header`.
- Returns with C clear.

Header layout:

- bytes 0..5: ASCII bytes `O`, `Z`, `M`, `S`, `A`, `V`
- byte 6: value 1
- byte 7: slot digit from A
- bytes 8..21: 14 bytes copied from `.inputstring`, padding missing bytes with 0
- bytes 22..23: 16-bit little-endian value `stack_start - zp_bytes_to_save`
- bytes 24..25: 16-bit little-endian value `stack_size + zp_bytes_to_save + dynmem_size`

Use X/Y as loop counters. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 12 — Add the Neo save-header reader

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/save-restore-neo6502.asm.

Add a routine named `neo_read_save_header`.

Contract:

- Reads exactly 26 bytes from file channel 3 into `neo_save_header`.
- Uses `neo_kernal_read_file`.
- Set `neo_kernal_size` to 26 before the read.
- File channel 3 must already be open.
- Returns C clear only when bytes 0..5 are `OZMSAV` and byte 6 is 1.
- Returns C set for any API error, short read, bad magic, or bad version.

Do not validate the slot byte in this routine. Do not validate addresses or size in this routine. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 13 — Add a header comment printer

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/save-restore-neo6502.asm.

Add a routine named `neo_print_save_comment`.

Contract:

- Prints bytes 8..21 of `neo_save_header` using `s_printchar`.
- Stops early at a zero byte.
- Prints at most 14 characters.
- Does not add a newline.
- Returns with C clear.

Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 14 — Implement Neo save_game

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/save-restore-neo6502.asm.

Add a routine named `neo_save_game`.

It must use the existing save/restore zone labels:

- `.saveslot_msg_save`
- `.saveslot_msg`
- `.input_alphanum`
- `.inputstring`
- `.savename_msg`
- `.save_msg`
- `.swap_pointers_for_save`

Behavior:

1. Print `.saveslot_msg_save`, then `.saveslot_msg`.
2. Call `.input_alphanum`.
3. If X is not 1, return failure.
4. Read the slot digit from `.inputstring`.
5. Reject slots where the digit is greater than or equal to `first_unavailable_save_slot_charcode`.
6. Print `.savename_msg`.
7. Call `.input_alphanum`.
8. If X is 0, return failure.
9. Print `.save_msg`.
10. Call `neo_write_save_header` with the slot digit.
11. Call `neo_build_save_filename` with the slot digit.
12. Open file channel 2 with secondary address 3 using `kernal_setlfs` and `kernal_open`.
13. Call `kernal_chkout` for channel 2.
14. Set `neo_kernal_size` to 26 and call `neo_kernal_write_file` with `neo_save_header`.
15. If that fails, close channel 2 and return failure.
16. Call `.swap_pointers_for_save`.
17. Set `neo_kernal_size` to `stack_size + zp_bytes_to_save + dynmem_size`.
18. Call `neo_kernal_write_file` starting at `stack_start - zp_bytes_to_save`.
19. Close channel 2.
20. Call `.swap_pointers_for_save` again.
21. Clear the window with `erase_window`.
22. Return success with A=0, X=1, C clear.

For failure, close any open channel, clear the window, and return A=0, X=0.

Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 15 — Implement Neo restore_game

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/save-restore-neo6502.asm.

Add a routine named `neo_restore_game`.

It must use the existing save/restore zone labels:

- `.saveslot_msg_restore`
- `.saveslot_msg`
- `.input_alphanum`
- `.inputstring`
- `.restore_msg`
- `.swap_pointers_for_save`

Behavior:

1. Print `.saveslot_msg_restore`, then `.saveslot_msg`.
2. Call `.input_alphanum`.
3. If X is not 1, return failure.
4. Read the slot digit from `.inputstring`.
5. Reject slots where the digit is greater than or equal to `first_unavailable_save_slot_charcode`.
6. Build the filename with `neo_build_save_filename`.
7. Open file channel 3 with secondary address 0 using `kernal_setlfs` and `kernal_open`.
8. Call `kernal_chkin` for channel 3.
9. Call `neo_read_save_header`.
10. If that fails, close channel 3 and return failure.
11. Check `neo_save_header + 7` equals the requested slot digit. If not, fail.
12. Check `neo_save_header + 22..23` equals little-endian `stack_start - zp_bytes_to_save`. If not, fail.
13. Check `neo_save_header + 24..25` equals little-endian `stack_size + zp_bytes_to_save + dynmem_size`. If not, fail.
14. Print `.restore_msg`.
15. Call `.swap_pointers_for_save`.
16. Set `neo_kernal_size` from `neo_save_header + 24..25`.
17. Call `neo_kernal_read_file` with destination `stack_start - zp_bytes_to_save`, using file channel 3.
18. Close channel 3.
19. Call `.swap_pointers_for_save` again.
20. Clear the window with `erase_window`.
21. Call `get_page_at_z_pc`.
22. Return success with A=0, X=1, C clear.

For failure, close any open channel, clear the window, and return A=0, X=0.

Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 16 — Implement Neo list_save_files

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/save-restore-neo6502.asm.

Add a routine named `neo_list_save_files`.

Behavior:

1. Print a newline with `s_printchar`.
2. Set X to `disk_info + 1`, the number of save slots.
3. Set an index Y to 0.
4. For each slot:
   - print the ASCII digit `$30 + Y`;
   - print `": "`;
   - build the filename by calling `neo_build_save_filename` with `$30 + Y`;
   - call `neo_kernal_file_stat`;
   - if the stat call fails, print `"(empty)"`;
   - otherwise open channel 3 read-only, CHKIN, call `neo_read_save_header`, close channel 3;
   - if header validation succeeds, call `neo_print_save_comment`;
   - if header validation fails, print `"(invalid)"`;
   - print a newline.
5. Continue until all slots are printed.
6. Return A=1, C clear.

Use static strings inside this module for `": "`, `"(empty)"`, and `"(invalid)"`.

Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 17 — Route Neo save/restore calls to the new module

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/asm/disk.asm.

Add early TARGET_NEO6502 jumps in three existing routines:

1. At the start of `list_save_files`, add:

       !ifdef TARGET_NEO6502 {
           jmp neo_list_save_files
       }

2. At the start of `restore_game`, add:

       !ifdef TARGET_NEO6502 {
           jmp neo_restore_game
       }

3. At the start of `save_game`, add:

       !ifdef TARGET_NEO6502 {
           jmp neo_save_game
       }

Do not remove the existing generic code. Do not change other targets. Do not change any other file.

Validate with:

    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3

Report the exact diff and the build result. Do not push commits.
```

---

## Prompt 18 — Create the Neo save/restore emulator test skeleton

```text
Create a new executable script:

    /home/bob/Documents/Projects/neo6502-ozmoo/tools/test-neo6502-save-restore.sh

Start by copying the structure of `tools/test-neo6502-smoke.sh`.

Keep these parts:

- ROOT_DIR / TOOLS_DIR discovery
- STORY, OZMOO_HOME, FIRMWARE_ROOT, EMULATOR, FONT_HEADER variables
- WORKDIR defaulting to `/tmp/opencode/neo-save-restore`
- cleanup trap that kills the emulator
- require_command and require_file helpers
- build step
- raw load file preparation
- emulator start with `path:$WORKDIR/storage`
- xdotool window discovery
- send_line helper
- screenshot decode with `tools/decode_neo_console.py`

For now, after boot, send only:

    look

Do not add save/restore assertions yet. Do not change any other file.

Validate by running:

    NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware tools/test-neo6502-save-restore.sh

The script should exit 0 and leave no emulator process running.

Report the script and test result. Do not push commits.
```

---

## Prompt 19 — Add the save half of the emulator test

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/tools/test-neo6502-save-restore.sh.

After the initial boot delay, inject these commands with `send_line`:

    save
    0
    TEST SAVE

Then add assertions:

1. The decoded console must not contain `Device#`.
2. The decoded console must contain `TEST SAVE`.
3. This file must exist:

       $WORKDIR/storage/MINIZORK.S00

4. Add a Python check that reads the first 26 bytes of `MINIZORK.S00` and verifies:
   - bytes 0..5 are `b"OZMSAV"`;
   - byte 6 is 1;
   - byte 7 is ASCII `0`;
   - bytes 8..21 start with `b"TEST SAVE"`.

Do not add restore assertions yet. Do not change any other file.

Run:

    NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware tools/test-neo6502-save-restore.sh

Report the test result and any decoded console output on failure. Do not push commits.
```

---

## Prompt 20 — Add the restore half of the emulator test

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/tools/test-neo6502-save-restore.sh.

After the save assertions, inject this command:

    open mailbox

Then inject:

    restore
    0

Add assertions:

1. The decoded console must not contain `Disk error`.
2. The decoded console must not contain `Device#`.
3. The decoded console must contain `WEST OF HOUSE`.
4. The decoded console must not contain `OPENING THE SMALL MAILBOX REVEALS A LEAFLET.` after the final restore prompt.

If the screen only shows the latest page and not the full history, adjust the assertion to check the final screen text near the prompt instead of the whole transcript.

Do not change any other file.

Run:

    NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware tools/test-neo6502-save-restore.sh

Report the test result and any decoded console output on failure. Do not push commits.
```

---

## Prompt 21 — Add persistence across emulator restart

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/tools/test-neo6502-save-restore.sh.

After the in-session restore assertions:

1. Kill the emulator using the existing `EMU_PID` cleanup logic.
2. Set `EMU_PID=""`.
3. Start the emulator again with the same `path:$WORKDIR/storage` argument.
4. Wait for the window.
5. Send:

       restore
       0

6. Assert that `WEST OF HOUSE` appears again.
7. Assert that no `Disk error` or `Device#` appears.

Make sure the EXIT trap still kills the second emulator process.

Do not change any other file.

Run:

    NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware tools/test-neo6502-save-restore.sh

Report the test result. Do not push commits.
```

---

## Prompt 22 — Wire the new test into the test tooling

```text
Edit only /home/bob/Documents/Projects/neo6502-ozmoo/tests/Makefile and /home/bob/Documents/Projects/neo6502-ozmoo/tools/README.md.

In `tests/Makefile`, add two phony-style targets:

    neo-smoke:
        NEO_FIRMWARE_ROOT=$${NEO_FIRMWARE_ROOT:-/tmp/opencode/neo-firmware} ../tools/test-neo6502-smoke.sh

    neo-save-restore:
        NEO_FIRMWARE_ROOT=$${NEO_FIRMWARE_ROOT:-/tmp/opencode/neo-firmware} ../tools/test-neo6502-save-restore.sh

Do not add the emulator tests to `all`, because they require the firmware checkout and X11 tools.

In `tools/README.md`, add a short section documenting both commands:

    make -C tests neo-smoke
    make -C tests neo-save-restore

Mention that the save/restore test uses an isolated storage directory under `/tmp/opencode/neo-save-restore`.

Do not change any other file. Do not push commits.
```

---

## Prompt 23 — Final verification

```text
Run these commands from /home/bob/Documents/Projects/neo6502-ozmoo:

    env OZMOO_HOME=/tmp/ozmoo-home make -C tests
    env OZMOO_HOME=/tmp/ozmoo-home ruby make.rb -t:neo6502 -P examples/minizork.z3
    NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware tools/test-neo6502-smoke.sh
    NEO_FIRMWARE_ROOT=/tmp/opencode/neo-firmware tools/test-neo6502-save-restore.sh
    pgrep -a -x neo || true
    git status --short

Report:

- test results;
- whether any `neo` process is still running;
- changed and untracked files;
- any failures.

Do not commit generated files under `dist/` or `storage/`. Do not push commits.
```
