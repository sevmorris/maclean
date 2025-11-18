SHELL := /bin/bash

.PHONY: install uninstall doctor test dry-run lint help

BIN_NAME := maclean
SCRIPT := $(PWD)/maclean.sh
BIN_DIR := $(HOME)/.local/bin
TARGET := $(BIN_DIR)/$(BIN_NAME)

help:
	@echo "Targets:"
	@echo "  install   Link $(SCRIPT) to $(TARGET)"
	@echo "  uninstall Remove $(TARGET)"
	@echo "  doctor    Check PATH and prerequisites"
	@echo "  lint      Run ShellCheck on scripts"
	@echo "  test      Run BATS tests (if available)"
	@echo "  dry-run   Run a dry-run (-n) with --fast"

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

lint:
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "⚠ shellcheck not found. Install with: brew install shellcheck"; \
		exit 1; \
	fi
	@echo "Running ShellCheck on scripts..."
	@shellcheck -S error $(SCRIPT) install.sh || exit 1
	@echo "✓ Linting passed"

test: dry-run
	@if command -v bats >/dev/null 2>&1; then \
		echo "Running BATS tests..."; \
		bats tests/ || exit 1; \
	else \
		echo "⚠ BATS not found. Install with: brew install bats-core"; \
		echo "Running dry-run test instead..."; \
		$(MAKE) dry-run; \
	fi

dry-run:
	@FAST=1 $(SCRIPT) -n --fast
