; Constants for a future Neo6502 target.
;
; Bootstrap phase note:
; - This file intentionally keeps a C64-like layout so we can thread
;   TARGET_NEO6502 through the build without changing interpreter core logic.
; - Morpheus firmware mappings (I/O, timing, file API, reset) will replace
;   the compatibility placeholders below in follow-up steps.
;

; ---- temporary machine/layout assumptions (bootstrap only) ----
basic_reset           = $a000
SCREEN_HEIGHT         = 30
SCREEN_WIDTH          = 53
SCREEN_ADDRESS        = $0400
COLOUR_ADDRESS        = $d800
COLOUR_ADDRESS_DIFF   = COLOUR_ADDRESS - SCREEN_ADDRESS
num_rows 			  = $a6 ; !byte 0
CURRENT_DEVICE        = $ba
;ti_variable           = $a0; 3 bytes
keyboard_buff_len     = $c6
keyboard_buff         = $277
key_repeat            = $028a
directory_buffer      = $700 ; 140 bytes, must be near end of screen RAM

use_reu				  = $9b
reu_boost_vmap_clock  = $b1
window_start_row	  = $2a; 4 bytes


; Screen kernal stuff. Must be kept together or update s_init in screenkernal.
; z6 indexes this by current_window (0-7), so three bytes are not enough and
; the overrun lands on s_reverse below. screenkernal-z6.asm defines its own
; eight-byte array instead; this zero page is free in a z6 build.
!ifndef Z6 {
s_ignore_next_linebreak = $b0 ; 3 bytes
}
s_reverse 			  = $b3 ; !byte 0

zp_temp               = $fb ; 5 bytes
savefile_zp_pointer   = $c1 ; 2 bytes
is_buffered_window	  = $c8;  !byte 1
first_banked_memory_page = $d0 ; Placeholder bootstrap value
reu_filled            = $0255 ; 4 bytes
vmap_buffer_start     = $0334
vmap_buffer_end       = $0400 ; Last byte + 1. Should not be more than vmap_buffer_start + 512


; --- I/O registers (bootstrap placeholders) ---
reg_rasterline_highbit=	$d011
reg_rasterline        = $d012
reg_screen_char_mode  = $d018
reg_bordercolour      = $d020
reg_backgroundcolour  = $d021
rasterline_for_scroll = 56

; --- Neo6502 Morpheus API register placeholders ---
; NOTE: These are adapter-layer placeholders. Verify against firmware docs before
; implementing concrete calls.
neo_api_command       = $ff00
neo_api_function      = $ff01
neo_api_error         = $ff02
neo_api_status        = $ff03
neo_api_param0        = $ff04
neo_api_param1        = $ff05
neo_api_param2        = $ff06
neo_api_param3        = $ff07
neo_api_param4        = $ff08
neo_api_param5        = $ff09

neo_vector_readline   = $ffeb
neo_vector_readchar   = $ffee
neo_vector_writechar  = $fff1
neo_vector_waitmsg    = $fff4
neo_vector_sendmsg    = $fff7

neo_api_group_system  = $01
neo_api_group_console = $02
neo_api_group_fileio  = $03

neo_api_fn_timer      = $01
neo_api_fn_reset      = $07
neo_api_fn_read_char  = $01
neo_api_fn_console_status = $02
neo_api_fn_write_char = $06
neo_api_fn_clear_screen = $0c

neo_api_fn_file_open  = $04
neo_api_fn_file_close = $05
neo_api_fn_load_file  = $02
neo_api_fn_store_file = $03
neo_api_fn_file_delete= $0d
neo_api_fn_file_read  = $08
neo_api_fn_file_write = $09

neo_api_file_mode_read              = $00
neo_api_file_mode_write             = $01
neo_api_file_mode_readwrite         = $02
neo_api_file_mode_readwrite_create  = $03

neo_api_error_ok   = $00
neo_api_error_eof  = $02

; --- Neo6502 Morpheus adapter bindings ---
; Route KERNAL entrypoints used by Ozmoo through local adapter routines.
kernal_reset          = neo_kernal_reset
kernal_delay_1ms      = neo_kernal_delay_1ms
kernal_readst         = neo_kernal_readst
kernal_setlfs         = neo_kernal_setlfs
kernal_setnam         = neo_kernal_setnam
kernal_open           = neo_kernal_open
kernal_close          = neo_kernal_close
kernal_chkin          = neo_kernal_chkin
kernal_chkout         = neo_kernal_chkout
kernal_clrchn         = neo_kernal_clrchn
kernal_readchar       = neo_kernal_readchar
kernal_printchar      = neo_kernal_printchar
kernal_load           = neo_kernal_load
kernal_save           = neo_kernal_save
kernal_settime        = neo_kernal_settime
kernal_readtime       = neo_kernal_readtime
kernal_getchar        = neo_kernal_getchar

; Pull in the shared constants, zero-page layout and common vectors.
!source "constants.asm"
