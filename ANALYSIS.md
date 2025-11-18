# maclean Project Analysis & Improvement Suggestions

## Executive Summary

`maclean` is a well-structured macOS cleanup script with good safety features (HOME-scoped operations, interactive confirmations) and clear documentation. The codebase is maintainable but has opportunities for improvement in testing, error handling, feature completeness, and developer experience.

---

## 1. Code Quality & Structure

### ✅ Strengths
- Good use of `set -euo pipefail` for strict error handling
- Clear function organization
- Consistent naming conventions
- Good separation of concerns

### 🔧 Improvements Needed

#### 1.1 Path Validation Issues
**Problem:** The `safe_rm` function checks `"$p" == "$HOME"*` which can fail with edge cases:
- Symlinks pointing outside HOME
- Paths with spaces or special characters
- Relative paths that resolve outside HOME

**Suggestion:**
```bash
safe_rm() {
  if [[ $# -eq 0 ]]; then echo 0; return; fi
  for p in "$@"; do
    # Resolve to absolute path and check
    local abs_path
    abs_path=$(cd "$(dirname "$p")" 2>/dev/null && pwd)/$(basename "$p") || abs_path="$p"
    [[ "$abs_path" == "$HOME"/* ]] || { 
      err "Refusing to touch non-home path: $p (resolved: $abs_path)"; 
      return 3; 
    }
  done
  # ... rest of function
}
```

#### 1.2 Error Handling Inconsistency
**Problem:** Many operations use `|| true` which swallows all errors, making debugging difficult.

**Suggestion:** Add error tracking and optional verbose error reporting:
```bash
ERROR_COUNT=0
ERROR_LOG=()

log_error() {
  ((ERROR_COUNT++))
  ERROR_LOG+=("$1")
  [[ $DEBUG -eq 1 ]] && err "$1"
}

# Then in functions:
brew cleanup -s || log_error "brew cleanup failed"
```

#### 1.3 `du_bytes` Function Limitations
**Problem:** Uses `du -sk` which may not handle:
- Files being deleted during calculation
- Very large directory trees (slow)
- Permission errors (silently ignored)

**Suggestion:** Add error handling and timeout:
```bash
du_bytes() {
  local sum=0 k
  if [[ $# -eq 0 ]]; then echo 0; return; fi
  while IFS= read -r -d '' p; do
    [[ ! -e "$p" ]] && continue  # Skip if already deleted
    k=$(timeout 5 du -sk "$p" 2>/dev/null | awk '{print $1}') || k=0
    [[ -n "$k" && "$k" =~ ^[0-9]+$ ]] && sum=$((sum + k))
  done < <(printf '%s\0' "$@")
  echo $((sum * 1024))
}
```

#### 1.4 Magic Numbers and Hardcoded Values
**Problem:** Hardcoded values scattered throughout (e.g., `maxdepth 2` in `box_legacy`)

**Suggestion:** Extract to constants at top of file:
```bash
# Configuration
readonly MAX_BOX_DEPTH=2
readonly SUMMARY_TOP_N=10
readonly DU_TIMEOUT=5
```

#### 1.5 Function Return Value Tracking
**Problem:** `brew_cleanup()` and `docker_cleanup()` don't track reclaimed space properly.

**Suggestion:** Calculate space before/after for these operations:
```bash
brew_cleanup() {
  STEP_RECLAIMED=0
  if command -v brew >/dev/null 2>&1; then
    if confirm "Run brew cleanup & autoremove?"; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  (dry-run) brew cleanup -s"
        echo "  (dry-run) brew autoremove"
      else
        local before
        before=$(brew --cache 2>/dev/null | xargs du -sk 2>/dev/null | awk '{sum+=$1} END {print sum*1024}') || before=0
        brew cleanup -s || true
        brew autoremove || true
        local after
        after=$(brew --cache 2>/dev/null | xargs du -sk 2>/dev/null | awk '{sum+=$1} END {print sum*1024}') || after=0
        STEP_RECLAIMED=$((before - after))
      fi
    fi
  else
    warn "Homebrew not found; skipping"
  fi
}
```

---

## 2. Functionality & Features

### ✅ Strengths
- Comprehensive cleanup coverage
- Good safety defaults (HOME-scoped)
- Interactive mode with confirmations
- Dry-run support

### 🔧 Improvements Needed

#### 2.1 Missing Cleanup Targets
**Suggestions:**
- **Rust/Cargo:** `~/.cargo/registry/cache`, `~/.cargo/git`
- **Go:** `~/go/pkg/mod/cache`
- **Ruby:** `~/.gem/cache`, `~/.bundle/cache`
- **Java/Maven:** `~/.m2/repository`
- **Gradle:** `~/.gradle/caches`
- **Android:** `~/.android/cache`
- **VS Code:** `~/.vscode/extensions/.obsolete`
- **Chrome/Chromium:** `~/Library/Caches/Google/Chrome`
- **Safari:** `~/Library/Caches/com.apple.Safari`
- **Spotlight:** `~/.Spotlight-V100` (if exists)

#### 2.2 Configuration File Support
**Suggestion:** Add `~/.macleanrc` for user preferences:
```bash
# ~/.macleanrc example
SKIP_STEPS="docker,xcode"
CUSTOM_PATHS="/custom/cache/path"
FAST_MODE_DEFAULT=1
```

#### 2.3 Selective Step Execution
**Suggestion:** Add `--only` flag to run specific steps:
```bash
maclean --only brew,python,node
```

#### 2.4 Better Summary Report
**Problem:** Current summary doesn't show per-step reclaimed space or categories.

**Suggestion:** Track and display:
- Per-step space reclaimed
- Category totals (caches, logs, build artifacts, etc.)
- Before/after disk usage breakdown

#### 2.5 Logging/History
**Suggestion:** Add optional logging to `~/.maclean.log`:
```bash
--log          Write operations to ~/.maclean.log
--log-level    Set log level (info, warn, error)
```

---

## 3. Testing & CI/CD

### ❌ Current State
- No automated tests
- Only manual dry-run test in Makefile
- No CI/CD pipeline

### 🔧 Improvements Needed

#### 3.1 Unit Tests
**Suggestion:** Create `tests/` directory with BATS (Bash Automated Testing System):
```bash
# tests/test_safe_rm.bats
#!/usr/bin/env bats

@test "safe_rm refuses non-home paths" {
  run safe_rm "/etc/passwd"
  [ "$status" -eq 3 ]
  [[ "$output" == *"Refusing to touch"* ]]
}

@test "safe_rm accepts home paths" {
  mkdir -p "$HOME/test_cleanup"
  run safe_rm "$HOME/test_cleanup"
  [ "$status" -eq 0 ]
}
```

#### 3.2 Integration Tests
**Suggestion:** Test full workflow in Docker/VM:
- Test each cleanup step
- Verify dry-run mode
- Test error handling

#### 3.3 CI/CD Pipeline
**Suggestion:** Add GitHub Actions workflow:
```yaml
# .github/workflows/test.yml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install BATS
        run: brew install bats-core
      - name: Run tests
        run: make test
      - name: ShellCheck
        run: brew install shellcheck && shellcheck maclean.sh
```

#### 3.4 Linting
**Suggestion:** Add ShellCheck to catch common bash issues:
```bash
# In Makefile
lint:
	@command -v shellcheck >/dev/null || (echo "Install shellcheck: brew install shellcheck" && exit 1)
	@shellcheck maclean.sh install.sh
```

---

## 4. Documentation

### ✅ Strengths
- Clear README
- Good usage examples
- Version tracking in script

### 🔧 Improvements Needed

#### 4.1 Man Page
**Suggestion:** Create `maclean.1`:
```roff
.TH MACLEAN 1 "2025-01-XX" "maclean v1.1.4" "macOS Cleanup Utility"
.SH NAME
maclean \- unified macOS cleanup tool
.SH SYNOPSIS
.B maclean
[OPTIONS]
...
```

#### 4.2 Contributing Guidelines
**Suggestion:** Add `CONTRIBUTING.md`:
- Code style guidelines
- Testing requirements
- PR process
- Release process

#### 4.3 Changelog
**Suggestion:** Maintain `CHANGELOG.md` (currently only in script comments):
```markdown
# Changelog

## [1.1.4] - 2025-11-04
### Fixed
- timed_step no longer runs steps in a subshell
- ENTER now reliably reports "skipped by user"

## [1.1.3] - YYYY-MM-DD
...
```

#### 4.4 API Documentation
**Suggestion:** Document internal functions for contributors:
```bash
# ---
# Function: safe_rm
# Description: Safely removes files/directories, ensuring they're within HOME
# Arguments: Paths to remove
# Returns: Bytes reclaimed (before deletion)
# Side effects: Removes files if not in dry-run mode
# ---
```

#### 4.5 Troubleshooting Section
**Suggestion:** Add to README:
- Common issues and solutions
- How to report bugs
- Debug mode usage

---

## 5. Security

### ✅ Strengths
- HOME-scoped operations
- Interactive confirmations
- No arbitrary code execution

### 🔧 Improvements Needed

#### 5.1 Path Traversal Protection
**Problem:** Current `safe_rm` check could be bypassed with symlinks.

**Suggestion:** Use `realpath` or resolve symlinks:
```bash
safe_rm() {
  # ... existing code ...
  for p in "$@"; do
    local real_path
    real_path=$(realpath "$p" 2>/dev/null || echo "$p")
    [[ "$real_path" == "$HOME"/* ]] || {
      err "Refusing to touch non-home path: $p"
      return 3
    }
  done
}
```

#### 5.2 Input Sanitization
**Suggestion:** Validate all user inputs and environment variables:
```bash
# Validate HOME
[[ -n "$HOME" && "$HOME" == /* ]] || {
  err "Invalid HOME directory: $HOME"
  exit 1
}
```

#### 5.3 Sudo Command Injection
**Problem:** While unlikely, ensure sudo commands are safe.

**Suggestion:** Explicitly validate sudo commands before execution.

#### 5.4 File Permissions
**Suggestion:** Check file permissions before deletion to avoid accidental removal of protected files.

---

## 6. Performance

### ✅ Strengths
- Fast mode for skipping slow operations
- Per-step timing

### 🔧 Improvements Needed

#### 6.1 Parallel Execution
**Suggestion:** Allow parallel execution of independent steps:
```bash
# Steps that can run in parallel
parallel_steps=(
  "purge_user_caches"
  "purge_user_logs"
  "purge_node_caches"
)

# Use GNU parallel or background jobs
```

#### 6.2 Summary Report Optimization
**Problem:** `du -sh "$HOME"/*` can be very slow on large home directories.

**Suggestion:** 
- Add timeout
- Make it optional with `--summary`
- Cache results
- Use `find` with `-exec du` for better performance

#### 6.3 Incremental Progress
**Suggestion:** Show progress for long operations:
```bash
# For large directory deletions
find "$dir" -type f | while read -r file; do
  rm "$file"
  # Show progress every 100 files
done
```

#### 6.4 Smart Caching
**Suggestion:** Cache directory sizes to avoid recalculating:
```bash
CACHE_FILE="$HOME/.maclean.cache"
# Store: path:size:timestamp
```

---

## 7. User Experience

### ✅ Strengths
- Interactive mode
- Clear output with colors
- Dry-run support
- Version info

### 🔧 Improvements Needed

#### 7.1 Better Progress Indicators
**Suggestion:** Add progress bars for long operations:
```bash
# Use a simple progress indicator
show_progress() {
  local current=$1 total=$2
  local percent=$((current * 100 / total))
  printf "\r  Progress: [%-50s] %d%%" "$(printf '#%.0s' {1..$((percent/2))})" "$percent"
}
```

#### 7.2 Estimated Time Remaining
**Suggestion:** Calculate and display ETA based on previous steps.

#### 7.3 Undo/Backup Feature
**Suggestion:** Optional backup before deletion:
```bash
--backup DIR    Backup files to DIR before deletion
--undo          Restore from last backup
```

#### 7.4 Interactive Selection
**Suggestion:** Allow users to select which steps to run interactively:
```bash
maclean --interactive-select
# Shows menu:
# [ ] Homebrew cleanup
# [x] User caches
# [ ] Python caches
# ...
```

#### 7.5 Better Error Messages
**Suggestion:** More descriptive errors with suggestions:
```bash
err "Homebrew not found. Install from https://brew.sh"
err "Permission denied. Try: sudo maclean --system"
```

#### 7.6 JSON/CSV Output
**Suggestion:** Machine-readable output for scripting:
```bash
--json          Output results as JSON
--csv           Output results as CSV
```

---

## 8. Project Management

### 🔧 Improvements Needed

#### 8.1 Version Management
**Suggestion:** 
- Use semantic versioning consistently
- Auto-increment version in CI
- Tag releases in git

#### 8.2 Release Process
**Suggestion:** Add release script:
```bash
# scripts/release.sh
#!/bin/bash
# Bump version, create tag, update changelog
```

#### 8.3 Dependency Management
**Suggestion:** Document minimum bash version and required tools:
```bash
# Check prerequisites
check_prerequisites() {
  local bash_version
  bash_version=$(bash --version | head -1 | awk '{print $4}')
  # Require bash 4.0+
}
```

#### 8.4 Issue Templates
**Suggestion:** Add GitHub issue templates for:
- Bug reports
- Feature requests
- Questions

#### 8.5 Code of Conduct
**Suggestion:** Add `CODE_OF_CONDUCT.md` for open source best practices.

---

## 9. Code Organization

### 🔧 Improvements Needed

#### 9.1 Modularization
**Suggestion:** Split into multiple files for better maintainability:
```
maclean.sh          # Main entry point
lib/colors.sh       # Color functions
lib/utils.sh        # Utility functions
lib/steps.sh        # Cleanup step functions
lib/validation.sh   # Path validation
```

#### 9.2 Configuration Management
**Suggestion:** Centralize configuration:
```bash
# config.sh
readonly VERSION="1.1.4"
readonly DEFAULT_BIN_DIR="$HOME/.local/bin"
readonly CACHE_FILE="$HOME/.maclean.cache"
```

---

## 10. Specific Code Issues

### 10.1 `purge_user_caches` and `purge_user_logs`
**Problem:** Uses glob expansion `"$HOME/Library/Caches"/*` which fails if directory is empty.

**Suggestion:**
```bash
purge_user_caches() {
  STEP_RECLAIMED=0
  if confirm "Purge user caches under ~/Library/Caches and ~/.cache?"; then
    local targets=()
    [[ -d "$HOME/Library/Caches" ]] && targets+=("$HOME/Library/Caches"/*)
    [[ -d "$HOME/.cache" ]] && targets+=("$HOME/.cache"/*)
    # Remove empty glob results
    targets=("${targets[@]//\*}")
    [[ ${#targets[@]} -gt 0 ]] && STEP_RECLAIMED=$(safe_rm "${targets[@]}")
  fi
}
```

### 10.2 `box_legacy` Function
**Problem:** Uses `xargs -0 -I{} echo "{}"` which is redundant.

**Suggestion:**
```bash
box_legacy() {
  STEP_RECLAIMED=0
  if confirm "Remove legacy .Box_* folders under $HOME (depth ≤ 2)?"; then
    mapfile -t BOX_LEGACY < <(find "$HOME" -maxdepth 2 -type d -name ".Box_*" -print0 | xargs -0)
    # ... rest
  fi
}
```

### 10.3 `tm_snapshots` Parsing
**Problem:** Awk parsing of `tmutil listlocalsnapshots` output is fragile.

**Suggestion:** More robust parsing:
```bash
ids=$(tmutil listlocalsnapshots / 2>/dev/null | \
  grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}' | \
  awk '{print $1}' | \
  sort -u)
```

### 10.4 Missing Error Handling in `main()`
**Problem:** `df -k "$HOME"` can fail, but error handling is minimal.

**Suggestion:**
```bash
start_bytes=$(df -k "$HOME" 2>/dev/null | awk 'NR==2{print $4*1024}') || {
  warn "Could not determine disk usage. Space tracking disabled."
  start_bytes=0
}
```

---

## Priority Recommendations

### High Priority
1. ✅ Add automated tests (BATS)
2. ✅ Fix path validation in `safe_rm` (symlink handling)
3. ✅ Add ShellCheck linting
4. ✅ Improve error handling and logging
5. ✅ Fix glob expansion issues in cache/log functions

### Medium Priority
1. ✅ Add CI/CD pipeline
2. ✅ Create man page
3. ✅ Add configuration file support
4. ✅ Improve summary report
5. ✅ Add more cleanup targets (Rust, Go, etc.)

### Low Priority
1. ✅ Modularize code
2. ✅ Add progress indicators
3. ✅ Add undo/backup feature
4. ✅ Performance optimizations
5. ✅ JSON/CSV output

---

## Conclusion

`maclean` is a solid, well-designed cleanup tool with good safety features. The main areas for improvement are:

1. **Testing infrastructure** - Critical for maintaining quality
2. **Error handling** - Better debugging and user feedback
3. **Code robustness** - Handle edge cases (symlinks, empty dirs, etc.)
4. **Documentation** - More comprehensive docs for users and contributors
5. **Feature completeness** - Additional cleanup targets and UX improvements

The codebase is maintainable and the architecture is sound. With these improvements, it would be production-ready for wider distribution.

