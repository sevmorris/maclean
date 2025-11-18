# Cache Removal Impact Guide

## Overview

Removing caches is **generally safe** and won't break apps, but some apps may experience temporary changes in behavior. Most apps will automatically recreate their caches on next launch.

## What Gets Cleaned & Impact

### ✅ **Safe - No Behavior Changes**

#### 1. **Package Manager Caches** (pip, npm, pnpm, yarn, bun)
- **What:** Downloaded package files cached for faster installs
- **Impact:** None - packages will re-download on next install
- **Behavior:** Slightly slower first install after cleanup, then normal

#### 2. **Crash/Diagnostic Logs**
- **What:** Crash reports and diagnostic files
- **Impact:** None - these are just logs
- **Behavior:** No change

#### 3. **User Logs** (`~/Library/Logs`)
- **What:** Application log files
- **Impact:** None - apps will create new logs
- **Behavior:** No change (you just lose historical logs)

#### 4. **Trash** (`~/.Trash`)
- **What:** Files you've already deleted
- **Impact:** None - they're already deleted
- **Behavior:** No change

#### 5. **Docker Prune**
- **What:** Unused containers, images, volumes
- **Impact:** None - only removes unused resources
- **Behavior:** No change (will need to pull images again if needed)

### ⚠️ **Temporary Changes - Apps Will Rebuild**

#### 1. **User Caches** (`~/Library/Caches`, `~/.cache`)
This is the **most impactful** cleanup step. Here's what to expect:

**Browser Caches:**
- Chrome, Safari, Firefox, etc.
- **Impact:** Temporary - caches will rebuild
- **Behavior:**
  - First page loads may be slightly slower
  - Offline content may need to re-download
  - Form autofill data may be lost (if stored in cache)
  - **No data loss** - bookmarks, passwords, history are stored elsewhere

**IDE/Editor Caches:**
- VS Code, IntelliJ, Xcode, etc.
- **Impact:** Temporary - indexes will rebuild
- **Behavior:**
  - First launch after cleanup may be slower
  - Code completion/indexing will rebuild
  - Project caches will regenerate
  - **No data loss** - your code and settings are safe

**Application Caches:**
- Slack, Discord, Spotify, etc.
- **Impact:** Temporary - caches will rebuild
- **Behavior:**
  - First launch may download cached content again
  - Offline content may need to re-download
  - **No data loss** - user data is stored elsewhere

**System Caches:**
- macOS system caches
- **Impact:** Minimal - system will rebuild as needed
- **Behavior:** No noticeable change

#### 2. **Xcode DerivedData**
- **What:** Build artifacts and indexes
- **Impact:** Temporary - will rebuild on next build
- **Behavior:**
  - First build after cleanup will be slower (full rebuild)
  - Code completion may be slower initially
  - **No data loss** - your projects are safe

#### 3. **Python Virtual Environments** (`~/.venvs`)
- **What:** Python virtual environments
- **Impact:** **Significant** - you'll need to recreate them
- **Behavior:**
  - You'll need to recreate virtual environments
  - Reinstall packages in those environments
  - **Only if you use `~/.venvs` directory**

### 🔄 **System-Level Changes** (with `--system` flag)

#### 1. **LaunchServices/Quick Look Cache Rebuild**
- **Impact:** Temporary - caches rebuild automatically
- **Behavior:**
  - First file preview may be slightly slower
  - App associations may need to refresh
  - **No data loss**

#### 2. **Spotlight Reindex**
- **Impact:** Temporary - will reindex in background
- **Behavior:**
  - Spotlight searches may be slower initially
  - Indexing happens in background
  - **No data loss**

#### 3. **DNS Cache Flush**
- **Impact:** Temporary - cache rebuilds automatically
- **Behavior:**
  - First DNS lookups may be slightly slower
  - **No data loss**

## What's NOT Affected

✅ **Your data is safe:**
- Documents, photos, music, videos
- Application settings and preferences
- Browser bookmarks, passwords, history
- Email, contacts, calendars
- Code repositories
- Application databases
- User-created files

✅ **System functionality:**
- No apps will break
- No data will be lost
- No permanent changes to app behavior

## Recommendations

### Before Running Cleanup

1. **Close important applications** - Some apps may have open file handles to cache files
2. **Save your work** - Always a good practice
3. **Use dry-run first** - Run `maclean -n` to see what would be cleaned

### After Cleanup

1. **Launch apps normally** - They'll rebuild caches automatically
2. **Be patient** - First launches may be slightly slower
3. **Let IDEs rebuild** - Don't interrupt indexing/rebuilding processes

### Selective Cleanup

If you're concerned about specific apps:

```bash
# Skip user caches (most impactful)
# Just don't confirm that step when prompted

# Or use specific flags to skip certain steps
maclean --no-xcode  # Skip Xcode cleanup
maclean --no-docker # Skip Docker cleanup
```

## Common Concerns

**Q: Will I lose my browser bookmarks/passwords?**  
A: No - these are stored in application data, not caches.

**Q: Will my code be deleted?**  
A: No - code is in your project directories, not in caches.

**Q: Will apps stop working?**  
A: No - apps will recreate caches automatically on next launch.

**Q: Will I need to reinstall apps?**  
A: No - only caches are removed, not applications.

**Q: How long until things are back to normal?**  
A: Usually within a few minutes - most caches rebuild on first launch.

## Summary

**Removing caches is safe** - it won't break apps or cause data loss. The main impact is:

1. **Temporary slowdown** on first launch after cleanup
2. **Rebuilding indexes/caches** (automatic)
3. **Re-downloading cached content** (if needed)

These are all **temporary** and apps will return to normal behavior quickly. The script is designed to be safe and only removes cache/log files, never your actual data or applications.

