#!/usr/bin/env bash
# maclean.sh — unified macOS cleanup
# v1.1.3 2025-11-04
# Changelog v1.1.3:
# - Fix: ENTER now shows "(no input — defaulting to No)" and step reports "skipped by user"
# - Add: --version prints version; banner prints version at start
# - Add: --debug prints rc/CONFIRM_LAST per step

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

# --- opts ---
YES=0
DRY_RUN=0
FAST="${FAST:-0}"
SYSTEM=0
CONFIRM_LAST=""
DEBUG=0
VERSION="v1.1.3"

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
    k=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
    [[ -n "$k" ]] && sum=$((sum + k))
  done < <(printf '%s\0' "$@")
  echo $((sum * 1024))
}

safe_rm() {
  if [[ $# -eq 0 ]]; then echo 0; return; fi
  for p in "$@"; do
    [[ "$p" == "$HOME"* ]] || { err "Refusing to touch non-home path: $p"; return 3; }
  done
  local before; before=$(du_bytes "$@")
  if [[ $DRY_RUN -eq 1 ]]; then
    for p in "$@"; do echo "  (dry-run) rm -rf $p"; done
  else
    rm -rf "$@"
  fi
  echo "$before"
}

timed_step() {
  local title="$1"; shift
  local start_ts; start_ts=$(date +%s)
  printf "%s— %s%s\n" "$blue" "$title" "$reset"
  CONFIRM_LAST=""
  local reclaimed; reclaimed=$("$@" || true)
  local rc=$?
  local end_ts; end_ts=$(date +%s)
  local dur=$((end_ts - start_ts))

  if [[ $DEBUG -eq 1 ]]; then
    echo "  [debug] rc=${rc} confirm=${CONFIRM_LAST}"
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

brew_cleanup() {
  if command -v brew >/dev/null 2>&1; then
    if confirm "Run brew cleanup & autoremove?"; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  (dry-run) brew cleanup -s"
        echo "  (dry-run) brew autoremove"
      else
        brew cleanup -s || true
        brew autoremove || true
      fi
      echo 0; return 0
    else
      warn "Skipped brew cleanup"; echo 0; return 0
    fi
  else
    warn "Homebrew not found; skipping"; echo 0; return 0
  fi
}

purge_user_caches() {
  if confirm "Purge user caches under ~/Library/Caches and ~/.cache?"; then
    local targets=("$HOME/Library/Caches"/* "$HOME/.cache"/*)
    safe_rm "${targets[@]}"
  else
    warn "Skipped user cache purge"; echo 0
  fi
}

purge_user_logs() {
  if confirm "Purge user logs under ~/Library/Logs?"; then
    local targets=("$HOME/Library/Logs"/*)
    safe_rm "${targets[@]}"
  else
    warn "Skipped log purge"; echo 0
  fi
}

purge_crash_logs() {
  if confirm "Remove DiagnosticReports and CrashReporter logs under ~/Library/Logs?"; then
    local targets=("$HOME/Library/Logs/DiagnosticReports"/* "$HOME/Library/Logs/CrashReporter"/*)
    safe_rm "${targets[@]}"
  else
    warn "Skipped crash/diagnostic logs"; echo 0
  fi
}

purge_venvs() {
  if confirm "Remove Python virtualenvs under ~/.venvs?"; then
    safe_rm "$HOME/.venvs"
  else
    warn "Skipped virtualenv removal"; echo 0
  fi
}

purge_python_caches() {
  if confirm "Clear pip/pipx caches?"; then
    local reclaimed=0
    if command -v python3 >/dev/null 2>&1; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  (dry-run) python3 -m pip cache purge"
      else
        python3 -m pip cache purge 2>/dev/null || true
      fi
    fi
    local px="$HOME/Library/Caches/pipx"
    if [[ -d "$px" ]]; then
      reclaimed=$((reclaimed + $(safe_rm "$px")))
    fi
    echo "$reclaimed"
  else
    warn "Skipped Python cache purge"; echo 0
  fi
}

purge_node_caches() {
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
    safe_rm "${targets[@]}"
  else
    warn "Skipped Node ecosystem cache purge"; echo 0
  fi
}

xcode_cleanup() {
  [[ $XCODE_OK -eq 1 ]] || { warn "Xcode cleanup disabled"; echo 0; return 0; }
  if [[ $FAST -eq 1 ]]; then warn "FAST=1 → Skipping Xcode Archives"; fi
  if [[ -d "$HOME/Library/Developer/Xcode" ]]; then
    local targets=("$HOME/Library/Developer/Xcode/DerivedData")
    if [[ $FAST -eq 0 ]]; then
      targets+=("$HOME/Library/Developer/Xcode/Archives")
    fi
    if confirm "Remove Xcode DerivedData${FAST:+ (Archives skipped by FAST)}?"; then
      safe_rm "${targets[@]}"
    else
      warn "Skipped Xcode cleanup"; echo 0
    fi
  else
    ok "No Xcode developer folder found"; echo 0
  fi
}

docker_cleanup() {
  [[ $DOCKER_OK -eq 1 ]] || { warn "Docker cleanup disabled"; echo 0; return 0; }
  if command -v docker >/dev/null 2>&1; then
    if [[ $FAST -eq 1 ]]; then
      warn "FAST=1 → Skipping docker system prune"; echo 0; return 0
    fi
    if confirm "Prune unused Docker data (images/containers/build cache)?"; then
      if [[ $DRY_RUN -eq 1 ]]; then
        echo "  (dry-run) docker system prune -af --volumes"
      else
        docker system prune -af --volumes || true
      fi
    else
      warn "Skipped Docker prune"
    fi
  else
    warn "Docker not found; skipping"; echo 0
  fi
  echo 0
}

trash_empty() {
  if confirm "Empty your user Trash? (~/.Trash)"; then
    safe_rm "$HOME/.Trash"/*
  else
    warn "Skipped Trash empty"; echo 0
  fi
}

box_legacy() {
  if confirm "Remove legacy .Box_* folders under $HOME (depth ≤ 2)?"; then
    mapfile -t BOX_LEGACY < <(find "$HOME" -maxdepth 2 -type d -name ".Box_*" -print0 | xargs -0 -I{} echo "{}")
    if [[ "${#BOX_LEGACY[@]}" -gt 0 ]]; then
      printf "  Found %d legacy folders\n" "${#BOX_LEGACY[@]}"
      safe_rm "${BOX_LEGACY[@]}"
    else
      ok "No legacy .Box_* folders found"; echo 0
    fi
  else
    warn "Skipped Box legacy check"; echo 0
  fi
}

tm_snapshots() {
  if [[ $SYSTEM -ne 1 ]]; then warn "--system not set; skipping Time Machine snapshots"; echo 0; return 0; fi
  if ! confirm "Purge local Time Machine snapshots? (sudo)"; then warn "Skipped TM snapshots"; echo 0; return 0; fi
  need_sudo || true
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "  (dry-run) sudo tmutil listlocalsnapshots /"
    return 0
  fi
  local ids
  ids=$(tmutil listlocalsnapshots / 2>/dev/null | awk -F'.' '/LocalSnapshots/ {print $(NF-1)}; /^[0-9]{4}-[0-9]{2}-[0-9]{2}/ {print $1}')
  if [[ -z "$ids" ]]; then ok "No local Time Machine snapshots found"; echo 0; return 0; fi
  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "  Deleting snapshot: $id"
    sudo tmutil deletelocalsnapshots "$id" || true
  done <<< "$ids"
  echo 0
}

rebuild_services() {
  if [[ $SYSTEM -ne 1 ]]; then warn "--system not set; skipping LS/QuickLook/Spotlight"; echo 0; return 0; fi
  if confirm "Rebuild LaunchServices & Quick Look caches? (sudo not required)"; then
    local lsreg="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  (dry-run) $lsreg -kill -r -domain local -domain system -domain user"
      echo "  (dry-run) qlmanage -r cache"
    else
      [[ -x "$lsreg" ]] && "$lsreg" -kill -r -domain local -domain system -domain user || true
      qlmanage -r cache >/dev/null 2>&1 || true
    fi
  else
    warn "Skipped LaunchServices/Quick Look rebuild"
  fi

  if confirm "Rebuild Spotlight index for / ? (sudo, can be slow)"; then
    need_sudo || true
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  (dry-run) sudo mdutil -E /"
    else
      sudo mdutil -E / || true
    fi
  else
    warn "Skipped Spotlight reindex"
  fi
  echo 0
}

flush_dns() {
  if [[ $SYSTEM -ne 1 ]]; then warn "--system not set; skipping DNS flush"; echo 0; return 0; fi
  if confirm "Flush DNS cache? (sudo)"; then
    need_sudo || true
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  (dry-run) sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
    else
      sudo dscacheutil -flushcache || true
      sudo killall -HUP mDNSResponder || true
    fi
  else
    warn "Skipped DNS flush"
  fi
  echo 0
}

memory_purge() {
  if [[ $SYSTEM -ne 1 ]]; then warn "--system not set; skipping memory purge"; echo 0; return 0; fi
  if confirm "Purge inactive memory? (sudo, may stall briefly)"; then
    need_sudo || true
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "  (dry-run) sudo purge"
    else
      sudo purge || true
    fi
  else
    warn "Skipped memory purge"
  fi
  echo 0
}

report_summary() {
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
  echo 0
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

  if [[ $DRY_RUN -eq 1 ]]; then
    warn "Dry-run complete. Re-run without -n to apply."
  else
    ok "Cleanup sequence finished"
  fi
}

main "$@"
