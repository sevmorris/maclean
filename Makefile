SHELL := /bin/bash

.PHONY: install uninstall doctor test dry-run help

BIN_NAME := maclean
SCRIPT := $(PWD)/maclean.sh
BIN_DIR := $(HOME)/.local/bin
TARGET := $(BIN_DIR)/$(BIN_NAME)

help:
	@echo "Targets:"
	@echo "  install   Link $(SCRIPT) to $(TARGET)"
	@echo "  uninstall Remove $(TARGET)"
	@echo "  doctor    Check PATH and prerequisites"
	@echo "  test      Run a dry-run (-n) with --fast"
	@echo "  dry-run   Alias to test"

install:
	@mkdir -p $(BIN_DIR)
	@chmod +x $(SCRIPT)
	@ln -snf $(SCRIPT) $(TARGET)
	@echo "✓ Linked $(TARGET) -> $(SCRIPT)"
	@echo "Add $$HOME/.local/bin to your PATH if not present."

uninstall:
	@rm -f $(TARGET)
	@echo "✓ Removed $(TARGET)"

doctor:
	@echo "PATH: $$PATH"
	@if ! command -v bash >/dev/null; then echo "✗ bash not found"; exit 1; fi
	@if [[ ":$$PATH:" != *":$(BIN_DIR):"* ]]; then echo "⚠ $(BIN_DIR) not in PATH"; else echo "✓ $(BIN_DIR) in PATH"; fi
	@echo "✓ Doctor OK"

test: dry-run
dry-run:
	@FAST=1 $(SCRIPT) -n --fast
