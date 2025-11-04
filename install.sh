#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
chmod +x "$REPO_DIR/maclean.sh"
ln -snf "$REPO_DIR/maclean.sh" "$BIN_DIR/maclean"
echo "Linked $BIN_DIR/maclean -> $REPO_DIR/maclean.sh"
echo "If needed, add: export PATH=\"$HOME/.local/bin:$PATH\" to your shell rc file."
