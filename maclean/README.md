# maclean — unified macOS cleanup

A single, interactive script to tidy up a developer’s macOS environment: brew cruft, language caches, Xcode DerivedData/Archives, Docker leftovers, legacy Box folders, and more. Designed to be safe (HOME-scoped) and transparent (per-step confirmations, per-step size reclaimed).

**v1.1 adds:** crash/diagnostic log cleanup, optional Time Machine local snapshot purge, LaunchServices/Quick Look/Spotlight rebuild, DNS flush, memory purge, and an end-of-run summary report.

## Quick start

```bash
# clone to your Projects folder
mkdir -p ~/Projects && cd ~/Projects
git clone https://github.com/sevmorris/maclean maclean
cd maclean

# link into ~/.local/bin so you can run 'maclean' from anywhere
make install   # or: ./install.sh
make doctor    # optional sanity check
```

Now run it from any directory:
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
- **Node ecosystem**: Corepack/npm/pnpm/yarn/bun caches (no global uninstallations)
- **Xcode**: `DerivedData` and (unless `--fast`) `Archives`
- **Docker**: `docker system prune -af --volumes` (skipped in `--fast`)
- **Trash**: `~/.Trash`
- **Legacy Box**: `.Box_*` folders under `$HOME` (depth ≤ 2)

## System-level (with `--system`)

- **Time Machine**: purge local snapshots (`tmutil deletelocalsnapshots`)
- **LaunchServices/Quick Look**: rebuild caches (`lsregister`, `qlmanage`)
- **Spotlight**: reindex `/` (`mdutil -E /`) (can be slow)
- **DNS cache**: flush (`dscacheutil`, `mDNSResponder`)
- **Memory purge**: `purge`

> All system tasks require confirmation; many use `sudo`. `-n/--dry-run` prints the actions instead of executing.

## Make targets

- `make install` – symlink `maclean` into `~/.local/bin`
- `make uninstall` – remove the symlink
- `make doctor` – verify PATH and basic prereqs
- `make test`/`make dry-run` – run `FAST=1 maclean -n --fast`

## Uninstall

```bash
make uninstall
```

## License

MIT
