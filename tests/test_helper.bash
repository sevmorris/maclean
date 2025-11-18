# Test helper functions for BATS tests

# Load the script functions for testing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source the main script to get access to functions
# We need to source it in a way that doesn't execute main()
load_script() {
  # Source the script but skip execution of main()
  bash -c "
    set -euo pipefail
    source '$SCRIPT_DIR/maclean.sh' 2>/dev/null || true
    export -f safe_rm du_bytes resolve_path log_error 2>/dev/null || true
  " || true
}

setup() {
  # Set up test environment
  export HOME="${HOME:-$HOME}"
  export DRY_RUN=0
  export YES=0
  export FAST=0
  export SYSTEM=0
  export DEBUG=0
  export ERROR_COUNT=0
  export ERROR_LOG=()
  
  # Source the script but prevent main() execution
  # This allows us to test individual functions
  if [[ -z "${SCRIPT_SOURCED:-}" ]]; then
    source <(sed '/^main "$@"/d' "$SCRIPT_DIR/maclean.sh") 2>/dev/null || true
    export SCRIPT_SOURCED=1
  fi
}

teardown() {
  # Clean up test artifacts
  rm -rf "$HOME"/test_maclean_* 2>/dev/null || true
  rm -rf "$HOME"/.test_maclean_* 2>/dev/null || true
  rm -rf "$HOME"/test_maclean_link_* 2>/dev/null || true
}

