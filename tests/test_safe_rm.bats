#!/usr/bin/env bats
# Test suite for safe_rm function

load test_helper

@test "safe_rm refuses non-home paths" {
  # Source script and prevent main() execution
  run bash -c "
    source <(sed '/^main \"\$@\"/d' '$SCRIPT_DIR/maclean.sh')
    safe_rm /etc/passwd
  "
  [ "$status" -eq 3 ]
  [[ "$output" == *"Refusing to touch non-home path"* ]]
}

@test "safe_rm accepts home paths" {
  TEST_DIR="$HOME/test_maclean_$$"
  mkdir -p "$TEST_DIR"
  run bash -c "
    source <(sed '/^main \"\$@\"/d' '$SCRIPT_DIR/maclean.sh')
    safe_rm '$TEST_DIR'
  "
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_DIR" ]
}

@test "safe_rm handles empty arguments" {
  run bash -c "
    source <(sed '/^main \"\$@\"/d' '$SCRIPT_DIR/maclean.sh')
    safe_rm
  "
  [ "$status" -eq 0 ]
  [ "$output" == "0" ]
}

@test "safe_rm handles symlinks pointing to home" {
  TEST_DIR="$HOME/test_maclean_$$"
  TEST_LINK="$HOME/test_maclean_link_$$"
  mkdir -p "$TEST_DIR"
  ln -s "$TEST_DIR" "$TEST_LINK"
  
  run bash -c "
    source <(sed '/^main \"\$@\"/d' '$SCRIPT_DIR/maclean.sh')
    safe_rm '$TEST_LINK'
  "
  [ "$status" -eq 0 ]
  [ ! -L "$TEST_LINK" ]
  [ -d "$TEST_DIR" ]  # Original directory should still exist (symlink removed)
  
  rmdir "$TEST_DIR" 2>/dev/null || true
}

@test "safe_rm refuses symlinks pointing outside home" {
  TEST_DIR="/tmp/test_maclean_$$"
  TEST_LINK="$HOME/test_maclean_link_$$"
  mkdir -p "$TEST_DIR"
  ln -s "$TEST_DIR" "$TEST_LINK"
  
  run bash -c "
    source <(sed '/^main \"\$@\"/d' '$SCRIPT_DIR/maclean.sh')
    safe_rm '$TEST_LINK'
  "
  [ "$status" -eq 3 ]
  [[ "$output" == *"Refusing to touch non-home path"* ]]
  
  rm -rf "$TEST_DIR" "$TEST_LINK" 2>/dev/null || true
}

@test "safe_rm works in dry-run mode" {
  TEST_DIR="$HOME/test_maclean_$$"
  mkdir -p "$TEST_DIR"
  DRY_RUN=1 run bash -c "
    source <(sed '/^main \"\$@\"/d' '$SCRIPT_DIR/maclean.sh')
    safe_rm '$TEST_DIR'
  "
  [ "$status" -eq 0 ]
  [ -d "$TEST_DIR" ]  # Should still exist in dry-run
  rmdir "$TEST_DIR" 2>/dev/null || true
}

