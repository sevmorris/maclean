#!/usr/bin/env bats
# Test suite for glob expansion fixes

load test_helper

@test "purge_user_caches handles empty cache directories" {
  # Create empty cache directories
  mkdir -p "$HOME/Library/Caches/test_cache"
  mkdir -p "$HOME/.cache/test_cache"
  
  # Remove contents but keep directories
  rm -rf "$HOME/Library/Caches/test_cache"/* 2>/dev/null || true
  rm -rf "$HOME/.cache/test_cache"/* 2>/dev/null || true
  
  # Source the script and test the function
  source "$SCRIPT_DIR/maclean.sh"
  YES=1 run purge_user_caches
  
  # Should not fail even with empty directories
  [ "$status" -eq 0 ]
  
  # Cleanup
  rm -rf "$HOME/Library/Caches/test_cache" "$HOME/.cache/test_cache" 2>/dev/null || true
}

@test "purge_user_logs handles empty log directories" {
  mkdir -p "$HOME/Library/Logs/test_logs"
  rm -rf "$HOME/Library/Logs/test_logs"/* 2>/dev/null || true
  
  source "$SCRIPT_DIR/maclean.sh"
  YES=1 run purge_user_logs
  
  [ "$status" -eq 0 ]
  
  rm -rf "$HOME/Library/Logs/test_logs" 2>/dev/null || true
}

@test "purge_user_caches processes existing cache files" {
  TEST_CACHE="$HOME/Library/Caches/test_maclean_$$"
  mkdir -p "$TEST_CACHE"
  echo "test" > "$TEST_CACHE/test_file"
  
  source "$SCRIPT_DIR/maclean.sh"
  YES=1 run purge_user_caches
  
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_CACHE" ] || [ ! -f "$TEST_CACHE/test_file" ]
  
  rm -rf "$TEST_CACHE" 2>/dev/null || true
}

