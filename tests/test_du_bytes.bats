#!/usr/bin/env bats
# Test suite for du_bytes function

load test_helper

@test "du_bytes handles empty arguments" {
  source "$SCRIPT_DIR/maclean.sh"
  run du_bytes
  [ "$status" -eq 0 ]
  [ "$output" == "0" ]
}

@test "du_bytes calculates size of existing directory" {
  TEST_DIR="$HOME/test_maclean_$$"
  mkdir -p "$TEST_DIR"
  echo "test content" > "$TEST_DIR/test_file"
  
  source "$SCRIPT_DIR/maclean.sh"
  run du_bytes "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  
  rm -rf "$TEST_DIR" 2>/dev/null || true
}

@test "du_bytes handles non-existent paths gracefully" {
  source "$SCRIPT_DIR/maclean.sh"
  run du_bytes "$HOME/nonexistent_path_$$"
  [ "$status" -eq 0 ]
  [ "$output" == "0" ]
}

@test "du_bytes handles multiple paths" {
  TEST_DIR1="$HOME/test_maclean_1_$$"
  TEST_DIR2="$HOME/test_maclean_2_$$"
  mkdir -p "$TEST_DIR1" "$TEST_DIR2"
  echo "test" > "$TEST_DIR1/file1"
  echo "test" > "$TEST_DIR2/file2"
  
  source "$SCRIPT_DIR/maclean.sh"
  run du_bytes "$TEST_DIR1" "$TEST_DIR2"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
  
  rm -rf "$TEST_DIR1" "$TEST_DIR2" 2>/dev/null || true
}

