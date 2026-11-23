all: runtests

runtests:
	ruby test_builds.rb

clean:

.PHONY: neo-smoke neo-save-restore

neo-smoke:
	NEO_FIRMWARE_ROOT=$${NEO_FIRMWARE_ROOT:-/tmp/opencode/neo-firmware} ../tools/test-neo6502-smoke.sh

neo-save-restore:
	NEO_FIRMWARE_ROOT=$${NEO_FIRMWARE_ROOT:-/tmp/opencode/neo-firmware} ../tools/test-neo6502-save-restore.sh
