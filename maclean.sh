#!/usr/bin/env bash
# maclean.sh — unified macOS cleanup
# v1.1.4 2025-11-04
# Changelog v1.1.4:
# - Fix: timed_step no longer runs steps in a subshell; ENTER now reliably reports "skipped by user"
# - Change: step functions set STEP_RECLAIMED instead of echoing; avoid duplicate "Skipped ..." lines
# - Keep: --version, --debug behavior

set -euo pipefail
IFS=$'\n\t'

# --- colors ---
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  green=$(tput setaf 2); yellow=$(tput setaf 3); red=$(tput setaf 1); blue=$(tput setaf 4)
  bold=$(tput bold); reset=$(tput sgr0)
else
  green=""; yellow=""; red=""; blue=""; bold=""; reset=""
fi

ok()   { printf "%s✓ %s%s\n" "$green" "$*" "$reset"; }
warn() { printf "%s⚠ %s%s\n" "$yellow" "$*" "$reset"; }
err()  { printf "%s✗ %s%s\n" "$red" "$*" "$reset" >&2; }

log_error() {
  ((ERROR_COUNT++))
  ERROR_LOG+=("$1")
  [[ $DEBUG -eq 1 ]] && err "$1"
}

# --- opts ---
YES=0
DRY_RUN=0
FAST="${FAST:-0}"
SYSTEM=0
CONFIRM_LAST=""
DEBUG=0
VERSION="v1.1.4"
STEP_RECLAIMED=0
ERROR_COUNT=0
ERROR_LOG=()

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]
  -y, --yes        Non-interactive; assume yes to all prompts
  -n, --dry-run    Show what would be removed without deleting anything
  --fast           Skip slower steps (Xcode Archives, Docker prune)
  --system         Enable system-level tasks (sudo)
  --no-docker      Skip Docker cleanup
  --no-xcode       Skip Xcode cleanup
  --debug          Print per-step rc and confirm status
  --version        Print version and exit
  -h, --help       Show this help
EOF
}

DOCKER_OK=1
XCODE_OK=1

while (( "$#" )); do
  case "$1" in
    -y|--yes) YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --fast) FAST=1 ;;
    --system) SYSTEM=1 ;;
    --no-docker) DOCKER_OK=0 ;;
    --no-xcode) XCODE_OK=0 ;;
    --debug) DEBUG=1 ;;
    --version) echo "$VERSION"; exit 0 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

confirm() {
  local prompt="${1:-Proceed?} [y/N] "
  CONFIRM_LAST=""
  if [[ $YES -eq 1 ]]; then CONFIRM_LAST="yes"; return 0; fi
  read -r -p "$prompt" ans || ans=""
  if [[ -z "$ans" ]]; then
    CONFIRM_LAST="empty"
    printf "  (no input — defaulting to No)\n"
    return 1
  fi
  case "$ans" in
    y|Y|yes|YES) CONFIRM_LAST="yes"; return 0 ;;
    n|N|no|NO)   CONFIRM_LAST="no";  return 1 ;;
    *)           CONFIRM_LAST="invalid"; return 1 ;;
  esac
}

need_sudo() {
  if [[ "${1:-}" == "--check" ]]; then sudo -n true 2>/dev/null || return 1; else sudo -v; fi
}

human() {
  local bytes="${1:-0}"
  awk -v b="${bytes}" 'function human(x){ s="B K M G T P E Z Y";i=0;while (x>=1024 && i<9){x/=1024;i++} return sprintf("%.1f %s", x, substr(s, index(s,i*2+1),1)) } BEGIN{print human(b)}' 2>/dev/null || echo "${bytes}B"
}

du_bytes() {
  local sum=0 k
  if [[ $# -eq 0 ]]; then echo 0; return; fi
  while IFS= read -r -d '' p; do
    [[ ! -e "$p" ]] && continue  # Skip if already deleted or doesn't exist
    k=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
    [[ -n "$k" && "$k" =~ ^[0-9]+$ ]] && sum=$((sum + k))
  done < <(printf '%s\0' "$@")
  echo $((sum * 1024))
}

# Resolve path to absolute, following symlinks (macOS-compatible)
resolve_path() {
  local path="$1"
  # Use Python for reliable symlink resolution on macOS
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$path" 2>/dev/null || echo "$path"
  else
    # Fallback: use cd/pwd to resolve (doesn't follow symlinks, but gets absolute path)
    (cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path") 2>/dev/null || echo "$path"
  fi
}

safe_rm() {
  if [[ $# -eq 0 ]]; then echo 0; return; fi
  for p in "$@"; do
    # Skip empty glob results (literal asterisk in path means glob didn't expand)
    [[ "$p" == *"/*" ]] && continue
    # Resolve to absolute path, following symlinks
    local real_path
    real_path=$(resolve_path "$p")
    # Ensure resolved path is within HOME
    [[ "$real_path" == "$HOME"/* ]] || {
      err "Refusing to touch non-home path: $p (resolved: $real_path)"
      log_error "Path validation failed: $p -> $real_path"
      return 3
    }
  done
  local before; before=$(du_bytes "$@")
  if [[ $DRY_RUN -eq 1 ]]; then
    for p in "$@"; do
      [[ "$p" == *"/*" ]] && continue
      echo "  (dry-run) rm -rf $p"
    done
  else
    for p in "$@"; do
      [[ "$p" == *"/*" ]] && continue
      rm -rf "$p" || log_error "Failed to remove: $p"
    done
  fi
  echo "$before"
}

# --- core runner (no subshell) ---
timed_step() {
  local title="$1"; shift
  local start_ts; start_ts=$(date +%s)
  printf "%s— %s%s\n" "$blue" "$title" "$reset"

  CONFIRM_LAST=""
  STEP_RECLAIMED=0

  "$@"; local rc=$?

  local end_ts; end_ts=$(date +%s)
  local dur=$((end_ts - start_ts))
  local reclaimed="$STEP_RECLAIMED"

  if [[ $DEBUG -eq 1 ]]; then
    echo "  [debug] rc=${rc} confirm=${CONFIRM_LAST} reclaimed=${reclaimed}"
  fi

  if [[ "$CONFIRM_LAST" == "empty" || "$CONFIRM_LAST" == "no" || "$CONFIRM_LAST" == "invalid" ]]; then
    warn "$title — skipped by user (ENTER defaults to No)"
    return 0
  fi

  if [[ $rc -eq 0 ]]; then
    if [[ -n "$reclaimed" && "$reclaimed" =~ ^[0-9]+$ ]]; then
      ok "$title — freed ~$(human "$reclaimed") in ${dur}s"
    else
      ok "$title — done in ${dur}s"
    fi
  else
    warn "$title — finished with non-zero exit (${rc}) in ${dur}s"
  fi
}

# --- steps (set STEP_RECLAIMED, do not echo) ---
brew_cleanup() {
  STEP_RECLAIMED=0
  if command -v brew >/dev/null 2>&1; then
    if confirm "Run brew cleanup & autoremove?"; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  (dry-run) brew cleanup -s"
        echo "  (dry-run) brew autoremove"
      else
        brew cleanup -s || true
        brew autoremove || true
      fi
    fi
  else
    warn "Homebrew not found; skipping"
  fi
}

purge_user_caches() {
  STEP_RECLAIMED=0
  if confirm "Purge user caches under ~/Library/Caches and ~/.cache?"; then
    local targets=()
    # Safely expand globs only if directories exist
    if [[ -d "$HOME/Library/Caches" ]]; then
      for item in "$HOME/Library/Caches"/*; do
        [[ -e "$item" ]] && targets+=("$item")
      done
    fi
    if [[ -d "$HOME/.cache" ]]; then
      for item in "$HOME/.cache"/*; do
        [[ -e "$item" ]] && targets+=("$item")
      done
    fi
    if [[ ${#targets[@]} -gt 0 ]]; then
      STEP_RECLAIMED=$(safe_rm "${targets[@]}")
    else
      ok "No cache directories found to clean"
    fi
  fi
}

purge_user_logs() {
  STEP_RECLAIMED=0
  if confirm "Purge user logs under ~/Library/Logs?"; then
    local targets=()
    if [[ -d "$HOME/Library/Logs" ]]; then
      for item in "$HOME/Library/Logs"/*; do
        [[ -e "$item" ]] && targets+=("$item")
      done
    fi
    if [[ ${#targets[@]} -gt 0 ]]; then
      STEP_RECLAIMED=$(safe_rm "${targets[@]}")
    else
      ok "No log directories found to clean"
    fi
  fi
}

purge_crash_logs() {
  STEP_RECLAIMED=0
  if confirm "Remove DiagnosticReports and CrashReporter logs under ~/Library/Logs?"; then
    local targets=()
    if [[ -d "$HOME/Library/Logs/DiagnosticReports" ]]; then
      for item in "$HOME/Library/Logs/DiagnosticReports"/*; do
        [[ -e "$item" ]] && targets+=("$item")
      done
    fi
    if [[ -d "$HOME/Library/Logs/CrashReporter" ]]; then
      for item in "$HOME/Library/Logs/CrashReporter"/*; do
        [[ -e "$item" ]] && targets+=("$item")
      done
    fi
    if [[ ${#targets[@]} -gt 0 ]]; then
      STEP_RECLAIMED=$(safe_rm "${targets[@]}")
    else
      ok "No crash log files found to clean"
    fi
  fi
}

purge_venvs() {
  STEP_RECLAIMED=0
  if confirm "Remove Python virtualenvs under ~/.venvs?"; then
    STEP_RECLAIMED=$(safe_rm "$HOME/.venvs")
  fi
}

purge_python_caches() {
  STEP_RECLAIMED=0
  if confirm "Clear pip/pipx caches?"; then
    if command -v python3 >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  (dry-run) python3 -m pip cache purge"
      else
        python3 -m pip cache purge 2>/dev/null || true
      fi
    fi
    local px="$HOME/Library/Caches/pipx"
    if [[ -d "$px" ]]; then
      local b; b=$(safe_rm "$px"); STEP_RECLAIMED=$((STEP_RECLAIMED + b))
    fi
  fi
}

purge_node_caches() {
  STEP_RECLAIMED=0
  if confirm "Clear Node/Corepack/npm/pnpm/yarn/bun caches?"; then
    local targets=(
      "$HOME/Library/Caches/Corepack"
      "$HOME/Library/Caches/npm"
      "$HOME/Library/Caches/pnpm"
      "$HOME/Library/Caches/yarn"
      "$HOME/Library/Caches/Bun"
      "$HOME/.pnpm-store"
      "$HOME/Library/Caches/bun"
    )
    STEP_RECLAIMED=$(safe_rm "${targets[@]}")
  fi
}

xcode_cleanup() {
  STEP_RECLAIMED=0
  [[ $XCODE_OK -eq 1 ]] || { warn "Xcode cleanup disabled"; return 0; }
  [[ -d "$HOME/Library/Developer/Xcode" ]] || { ok "No Xcode developer folder found"; return 0; }
  if [[ $FAST -eq 1 ]]; then warn "FAST=1 → Skipping Xcode Archives"; fi
  local targets=("$HOME/Library/Developer/Xcode/DerivedData")
  [[ $FAST -eq 0 ]] && targets+=("$HOME/Library/Developer/Xcode/Archives")
  if confirm "Remove Xcode DerivedData${FAST:+ (Archives skipped by FAST)}?"; then
    STEP_RECLAIMED=$(safe_rm "${targets[@]}")
  fi
}

docker_cleanup() {
  STEP_RECLAIMED=0
  [[ $DOCKER_OK -eq 1 ]] || { warn "Docker cleanup disabled"; return 0; }
  if command -v docker >/dev/null 2>&1; then
    if [[ $FAST -eq 1 ]]; then
      warn "FAST=1 → Skipping docker system prune"; return 0
    fi
    if confirm "Prune unused Docker data (images/containers/build cache)?"; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  (dry-run) docker system prune -af --volumes"
      else
        docker system prune -af --volumes || true
      fi
    fi
  else
    warn "Docker not found; skipping"
  fi
}

trash_empty() {
  STEP_RECLAIMED=0
  if confirm "Empty your user Trash? (~/.Trash)"; then
    STEP_RECLAIMED=$(safe_rm "$HOME/.Trash"/*)
  fi
}

box_legacy() {
  STEP_RECLAIMED=0
  if confirm "Remove legacy .Box_* folders under $HOME (depth ≤ 2)?"; then
    mapfile -t BOX_LEGACY < <(find "$HOME" -maxdepth 2 -type d -name ".Box_*" -print0 | xargs -0 -I{} echo "{}")
    if [[ "${#BOX_LEGACY[@]}" -gt 0 ]]; then
      printf "  Found %d legacy folders\n" "${#BOX_LEGACY[@]}"
      STEP_RECLAIMED=$(safe_rm "${BOX_LEGACY[@]}")
    else
      ok "No legacy .Box_* folders found"
    fi
  fi
}

tm_snapshots() {
  STEP_RECLAIMED=0
  [[ $SYSTEM -ne 1 ]] && { warn "--system not set; skipping Time Machine snapshots"; return 0; }
  if ! confirm "Purge local Time Machine snapshots? (sudo)"; then return 0; fi
  need_sudo || true
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  (dry-run) sudo tmutil listlocalsnapshots /"
    return 0
  fi
  local ids
  ids=$(tmutil listlocalsnapshots / 2>/dev/null | awk -F'.' '/LocalSnapshots/ {print $(NF-1)}; /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {print $1}')
  [[ -z "$ids" ]] && { ok "No local Time Machine snapshots found"; return 0; }
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "  Deleting snapshot: $id"
    sudo tmutil deletelocalsnapshots "$id" || true
  done <<< "$ids"
}

rebuild_services() {
  STEP_RECLAIMED=0
  [[ $SYSTEM -ne 1 ]] && { warn "--system not set; skipping LS/QuickLook/Spotlight"; return 0; }
  if confirm "Rebuild LaunchServices & Quick Look caches? (sudo not required)"; then
    local lsreg="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  (dry-run) $lsreg -kill -r -domain local -domain system -domain user"
      echo "  (dry-run) qlmanage -r cache"
    else
      [[ -x "$lsreg" ]] && "$lsreg" -kill -r -domain local -domain system -domain user || true
      qlmanage -r cache >/dev/null 2>&1 || true
    fi
  fi
  if confirm "Rebuild Spotlight index for / ? (sudo, can be slow)"; then
    need_sudo || true
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  (dry-run) sudo mdutil -E /"
    else
      sudo mdutil -E / || true
    fi
  fi
}

flush_dns() {
  STEP_RECLAIMED=0
  [[ $SYSTEM -ne 1 ]] && { warn "--system not set; skipping DNS flush"; return 0; }
  if confirm "Flush DNS cache? (sudo)"; then
    need_sudo || true
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  (dry-run) sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
    else
      sudo dscacheutil -flushcache || true
      sudo killall -HUP mDNSResponder || true
    fi
  fi
}

memory_purge() {
  STEP_RECLAIMED=0
  [[ $SYSTEM -ne 1 ]] && { warn "--system not set; skipping memory purge"; return 0; }
  if confirm "Purge inactive memory? (sudo, may stall briefly)"; then
    need_sudo || true
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  (dry-run) sudo purge"
    else
      sudo purge || true
    fi
  fi
}

report_summary() {
  STEP_RECLAIMED=0
  echo "— Generating summary report"
  if command -v du >/dev/null 2>&1; then
    echo "Top 10 directories under $HOME by size:"
    du -sh "$HOME"/* 2>/dev/null | sort -hr | head -n 10
  fi
  if [[ -d "$HOME/Library/Caches" ]]; then
    echo ""
    echo "Largest cache folders:"
    du -sh "$HOME/Library/Caches"/* 2>/dev/null | sort -hr | head -n 10
  fi
}

main() {
  echo "${bold}macOS cleanup — interactive (${VERSION})${reset}"
  need_sudo --check || true

  local start_bytes end_bytes total_reclaimed
  start_bytes=$(df -k "$HOME" | awk 'NR==2{print $4*1024}') || start_bytes=0

  timed_step "Homebrew cleanup"          brew_cleanup
  timed_step "User caches"               purge_user_caches
  timed_step "User logs"                 purge_user_logs
  timed_step "Crash/Diagnostic logs"     purge_crash_logs
  timed_step "Python venvs (~/.venvs)"   purge_venvs
  timed_step "Python caches"             purge_python_caches
  timed_step "Node ecosystem caches"     purge_node_caches
  timed_step "Xcode caches"              xcode_cleanup
  timed_step "Legacy Box folders"        box_legacy
  timed_step "Empty Trash"               trash_empty
  timed_step "Docker prune"              docker_cleanup

  timed_step "Time Machine snapshots"    tm_snapshots
  timed_step "LS/Quick Look/Spotlight"   rebuild_services
  timed_step "Flush DNS cache"           flush_dns
  timed_step "Memory purge"              memory_purge

  end_bytes=$(df -k "$HOME" | awk 'NR==2{print $4*1024}') || end_bytes=0
  if [[ $start_bytes -gt 0 && $end_bytes -gt 0 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      warn "Dry-run mode — reported reclaimed space is estimated per-step only"
    else
      total_reclaimed=$(( end_bytes - start_bytes ))
      ok "Total space reclaimed: $(human "$total_reclaimed")"
    fi
  fi

  timed_step "Summary report"            report_summary

  if [[ $ERROR_COUNT -gt 0 ]]; then
    warn "Cleanup finished with $ERROR_COUNT error(s)"
    [[ $DEBUG -eq 1 ]] && {
      echo "Error log:"
      printf "  %s\n" "${ERROR_LOG[@]}"
    }
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    warn "Dry-run complete. Re-run without -n to apply."
  else
    ok "Cleanup sequence finished"
  fi
}

main "$@"
