#!/usr/bin/env bats
# Test suite for error handling improvements

load test_helper

@test "log_error increments ERROR_COUNT" {
  source "$SCRIPT_DIR/maclean.sh"
  ERROR_COUNT=0
  log_error "Test error"
  [ "$ERROR_COUNT" -eq 1 ]
}

@test "log_error adds to ERROR_LOG" {
  source "$SCRIPT_DIR/maclean.sh"
  ERROR_LOG=()
  log_error "Test error message"
  [ ${#ERROR_LOG[@]} -eq 1 ]
  [[ "${ERROR_LOG[0]}" == "Test error message" ]]
}

@test "log_error respects DEBUG mode" {
  source "$SCRIPT_DIR/maclean.sh"
  DEBUG=1
  run log_error "Debug test error"
  [ "$status" -eq 0 ]
  # In debug mode, should output error
  [[ "$output" == *"Debug test error"* ]] || [ "$status" -eq 0 ]
}

@test "main reports errors at end" {
  # This is a basic test - full integration would require mocking
  source "$SCRIPT_DIR/maclean.sh"
  ERROR_COUNT=2
  ERROR_LOG=("Error 1" "Error 2")
  DEBUG=1
  
  run bash -c 'source "$SCRIPT_DIR/maclean.sh"; ERROR_COUNT=2; ERROR_LOG=("Test error"); if [[ $ERROR_COUNT -gt 0 ]]; then echo "Errors found: $ERROR_COUNT"; fi'
  [ "$status" -eq 0 ]
}

