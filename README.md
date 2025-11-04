# maclean — unified macOS cleanup

A single, interactive script to tidy up a developer’s macOS environment: brew cruft, language caches, Xcode DerivedData/Archives, Docker leftovers, legacy Box folders, and more. Designed to be safe (HOME‑scoped) and transparent (per‑step confirmations, per‑step size reclaimed).

## Quick start

```bash
# clone to your Projects folder
mkdir -p ~/Projects && cd ~/Projects
git clone <YOUR_REMOTE> maclean
cd maclean

# link into ~/.local/bin so you can run 'maclean' from anywhere
make install   # or: ./install.sh
make doctor    # optional sanity check
```

Now run it from any directory:
```bash
maclean     # interactive mode
maclean -y  # non-interactive (yes to all)
maclean -n  # dry-run (simulate)
FAST=1 maclean --fast   # skip slower steps
maclean --no-docker     # skip Docker
maclean --no-xcode      # skip Xcode
```

## What it cleans

- **Homebrew**: `brew cleanup -s`, `brew autoremove`
- **User caches/logs**: `~/Library/Caches`, `~/.cache`, `~/Library/Logs`
- **Python**: `~/.venvs`, `pip`/`pipx` caches
- **Node ecosystem**: Corepack/npm/pnpm/yarn/bun caches (no global uninstallations)
- **Xcode**: `DerivedData` and (unless `--fast`) `Archives`
- **Docker**: `docker system prune -af --volumes` (skipped in `--fast`)
- **Trash**: `~/.Trash`
- **Legacy Box**: `.Box_*` folders under `$HOME` (depth ≤ 2)

All removals are guarded to **$HOME** paths only.

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
