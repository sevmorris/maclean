# maclean — unified macOS cleanup

A single, interactive script to tidy up a developer’s macOS environment: brew cruft, language caches, Xcode DerivedData/Archives, Docker leftovers, legacy Box folders, and more. Designed to be safe (HOME-scoped) and transparent (per-step confirmations, per-step size reclaimed).

## Quick install (users)

Install to `~/bin` so you can run `maclean` from anywhere:

```bash
mkdir -p "$HOME/bin"
curl -fsSL https://raw.githubusercontent.com/sevmorris/maclean/main/maclean.sh -o "$HOME/bin/maclean"
chmod +x "$HOME/bin/maclean"

# ensure ~/bin is on your PATH (zsh example)
# echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc && exec zsh

maclean --version
```

**Upgrade:**
```bash
curl -fsSL https://raw.githubusercontent.com/sevmorris/maclean/main/maclean.sh -o "$HOME/bin/maclean"
chmod +x "$HOME/bin/maclean"
```

**Uninstall:**
```bash
rm -f "$HOME/bin/maclean"
```

> Tip: to pin a specific release tag, swap `main` for a tag:
> `https://raw.githubusercontent.com/sevmorris/maclean/v1.1.3/maclean.sh`

## Usage

```bash
maclean                   # interactive mode
maclean -y                # non-interactive (yes to all)
maclean -n                # dry-run (simulate)
FAST=1 maclean --fast     # skip slower steps
maclean --no-docker
maclean --no-xcode
maclean --system          # enable system-level tasks (sudo)
```

## What it cleans

- **Homebrew**: `brew cleanup -s`, `brew autoremove`
- **User caches/logs**: `~/Library/Caches`, `~/.cache`, `~/Library/Logs`
- **Crash/diagnostic logs**: `~/Library/Logs/DiagnosticReports`, `~/Library/Logs/CrashReporter`
- **Python**: `~/.venvs`, `pip`/`pipx` caches
- **Node ecosystem**: Corepack/npm/pnpm/yarn/bun caches
- **Xcode**: `DerivedData` and (unless `--fast`) `Archives`
- **Docker**: `docker system prune -af --volumes` (skipped in `--fast`)
- **Trash**: `~/.Trash`
- **Legacy Box**: `.Box_*` under `$HOME` (depth ≤ 2)

**System-level (with `--system`):**
- **Time Machine** local snapshots
- Rebuild **LaunchServices** & **Quick Look** caches, optional **Spotlight** reindex
- **Flush DNS** cache
- **Memory purge**

All steps are confirmed interactively; dry-run prints actions only.

## For developers (this repo)

Clone and work in `~/Projects/maclean`, but **do not** install the dev copy onto your PATH if you want to behave like a typical user:

```bash
# development clone
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/sevmorris/maclean maclean
cd maclean

# run tests, edit script, commit, push, make releases
# Users install via the curl command above.
```

> If you *do* want a local dev alias without shadowing the user install, use:
> ```bash
> alias maclean-dev="bash ~/Projects/maclean/maclean.sh"
> ```
> That keeps `maclean` pointing at `~/bin/maclean` while you iterate in the repo.
