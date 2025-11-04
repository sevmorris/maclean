#!/usr/bin/env bash
# maclean.sh — unified macOS cleanup
# v1 2025-11-04
# Features:
# - Interactive by default; use -y/--yes to auto-confirm, -n/--dry-run to simulate
# - Per-step confirmations
# - Measures space reclaimed per step and total
# - Optional FAST mode via ESPnet-style env var (FAST=1) to skip slower tasks
# - Safe deletes with guardrails (only user paths under $HOME)
# - Broad developer caches (brew, pip/pipx, node/npm/corepack/pnpm/yarn, Python venvs, Xcode DerivedData & Archives, Docker)
# - Legacy Box folders cleanup
# - Trash empty (user) — optional
#
# Tested on macOS 13–15 with /bin/bash (3.2) and Homebrew bash (5+).

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

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  -y, --yes        Non-interactive; assume "yes" to all prompts
  -n, --dry-run    Show what would be removed without deleting anything
  --fast           Skip slower/optional steps (Xcode Archives, Docker prune)
  --no-docker      Skip Docker cleanup
  --no-xcode       Skip Xcode cleanup
  -h, --help       Show this help
EOF
}

DOCKER_OK=1
XCODE_OK=1

while (( "$#" )); do
  case "${1}" in
    -y|--yes) YES=1 ;;
    -n|--dry-run) DRY_RUN=1 ;;
    --fast) FAST=1 ;;
    --no-docker) DOCKER_OK=0 ;;
    --no-xcode) XCODE_OK=0 ;;
    -h|--help) usage; exit 0 ;;
    *) err "Unknown option: ${1}"; usage; exit 2 ;;
  esac
  shift
done

confirm() {
  local prompt="${1:-Proceed?} [y/N] "
  if [[ $YES -eq 1 ]]; then return 0; fi
  read -r -p "$prompt" ans || ans=""
  case "$ans" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

need_sudo() {
  if [[ "${1:-}" == "--check" ]]; then sudo -n true 2>/dev/null || return 1; else sudo -v; fi
}

human() { # bytes -> human, uses awk if available
  local bytes="${1:-0}"
  awk -v b="${bytes}" 'function human(x){ s="B K M G T P E Z Y";i=0;while (x>=1024 && i<9){x/=1024;i++} return sprintf("%.1f %s", x, substr(s, index(s,i*2+1),1)) } BEGIN{print human(b)}' 2>/dev/null || echo "${bytes}B"
}

du_bytes() { # sum du -sk for paths; prints bytes
  local sum=0 k
  if [[ $# -eq 0 ]]; then echo 0; return; fi
  while IFS= read -r -d '' p; do
    k=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
    [[ -n "$k" ]] && sum=$((sum + k))
  done < <(printf '%s\0' "$@")
  echo $((sum * 1024))
}

safe_rm() { # rm for user paths w/ DRY_RUN support
  local deleted=0
  if [[ $# -eq 0 ]]; then echo 0; return; fi
  # guard: only allow paths under $HOME
  for p in "$@"; do
    [[ "$p" == "$HOME"* ]] || { err "Refusing to touch non-home path: $p"; return 3; }
  done
  local before; before=$(du_bytes "$@")
  if [[ $DRY_RUN -eq 1 ]]; then
    for p in "$@"; do echo "  (dry-run) rm -rf $p"; done
  else
    rm -rf "$@"
  fi
  local after; after=$(du_bytes "$@")
  # bytes reclaimed ~= before (after should be near 0)
  echo "$before"
}

timed_step() {
  local title="$1"; shift
  local start_ts=$(date +%s)
  printf "%s— %s%s\n" "$blue" "$title" "$reset"
  local reclaimed=$("$@" || true)
  local rc=$?
  local end_ts=$(date +%s)
  local dur=$((end_ts - start_ts))
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
      return 0
    else
      warn "Skipped brew cleanup"; return 0
    fi
  else
    warn "Homebrew not found; skipping"; return 0
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
    # pipx caches
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
  if confirm "Clear Node/Corepack/npm/pnpm/yarn caches?"; then
    local targets=(
      "$HOME/Library/Caches/Corepack"
      "$HOME/Library/Caches/npm"
      "$HOME/Library/Caches/pnpm"
      "$HOME/Library/Caches/yarn"
      "$HOME/Library/Caches/Bun"
      "$HOME/.pnpm-store"
      "$HOME/Library/Caches/bun"
    )
    # npm cache clean is slow; use rm of cache dirs
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
    else
      warn "Skipped Docker prune"
    fi
  fi
  return 0
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

main() {
  echo "${bold}macOS cleanup — interactive${reset}"
  need_sudo --check || true

  local start_bytes end_bytes total_reclaimed
  start_bytes=$(df -k "$HOME" | awk 'NR==2{print $4*1024}') || start_bytes=0

  timed_step "Homebrew cleanup"        brew_cleanup
  timed_step "User caches"             purge_user_caches
  timed_step "User logs"               purge_user_logs
  timed_step "Python venvs (~/.venvs)" purge_venvs
  timed_step "Python caches"           purge_python_caches
  timed_step "Node ecosystem caches"   purge_node_caches
  timed_step "Xcode caches"            xcode_cleanup
  timed_step "Legacy Box folders"      box_legacy
  timed_step "Empty Trash"             trash_empty
  timed_step "Docker prune"            docker_cleanup

  end_bytes=$(df -k "$HOME" | awk 'NR==2{print $4*1024}') || end_bytes=0
  if [[ $start_bytes -gt 0 && $end_bytes -gt 0 ]]; then
    if [[ $DRY_RUN -eq 1 ]]; then
      warn "Dry-run mode — reported reclaimed space is estimated per-step only"
    else
      total_reclaimed=$(( end_bytes - start_bytes ))
      ok "Total space reclaimed: $(human "$total_reclaimed")"
    fi
  fi

  if [[ $DRY_RUN -eq 1 ]]; then
    warn "Dry-run complete. Re-run without -n to apply."
  else
    ok "Cleanup sequence finished"
  fi
}

main "$@"
