# Investigation: Generalizing mk-posix-shell.nix for rc

## Current Architecture

- `lib/mk-posix-shell.nix` takes `{ name, etcRcPath, homeRcPath }` and returns three modules
- Generated files: `/etc/profile` (login), `/etc/<name>rc` (interactive via `ENV`), `~/.profile`, `~/.<name>rc`
- File content is hardcoded with POSIX syntax: `[` tests, `alias`, `HISTFILE`/`HISTSIZE`, `PS1`, `set -o noclobber`, `export`
- Options duplicated across all three modules
- `modules/ksh93.nix` layers ksh-specific extras on top via `imports`

## rc Shell Differences (from source and man page)

- **Startup file**: Only `$home/.rcrc` for login shells (`argv[0][0] == '-'`). No `ENV` equivalent. No interactive-non-login init file.
- **Syntax**: C-like. `if (cond) { cmd }`, lists `('a' 'b')`, `fn name { body }` for functions/aliases.
- **Prompt**: `$prompt` is a list, default `('; ' '')`. No `$PS1`.
- **History**: `$history` is just a file path. No `HISTSIZE`.
- **System-wide config**: None. `main.c` hardcodes `concat(varlookup("home"), word("/.rcrc", NULL))`. No `/etc/rcrc`, no env var override.

## Key Challenge

The current builder conflates **module plumbing** (options, assertions, file registration) with **POSIX shell semantics** (syntax, variable names, initialization model). rc needs the plumbing but not the semantics.

## Proposed Plan

### Phase 1: Refactor into two-tier system

**Tier 1 — `lib/mk-shell-module.nix` (generic)**

- Accepts a declarative `files` attribute specifying which files to generate per platform
- Handles common option declarations, defaults, assertions, package installation
- Does not assume POSIX syntax or any specific file layout
- API sketch:
  ```nix
  mkShellModule {
    name = "rc";
    files = {
      nixos = {};  # rc has no native system-wide config
      darwin = {};
      hm = {
        ".rcrc" = {
          mode = "login";
          content = { cfg, lib, ... }: ''...'';
        };
      };
    };
    extraOptions = { lib, ... }: { prompt = lib.mkOption { ... }; };
    defaults = { historyFile = "$home/.rc_history"; };
  }
  ```

**Tier 2 — `lib/mk-posix-shell-module.nix` (POSIX specialization)**

- Thin wrapper around `mkShellModule`
- Provides the current POSIX-specific file templates and defaults
- Maintains backward compatibility — `modules/ksh-base.nix` needs no changes

### Phase 2: Implement rc modules

- `modules/rc.nix` uses `mkShellModule`
- Generates `~/.rcrc` only (home-manager)
- NixOS/darwin modules install the package but generate no files
- Options: `enable`, `package`, `historyFile`, `prompt`, `shellAliases` (rendered as `fn`), `initExtra`

### Phase 3: Add system-wide rc support (optional, deferred)

- Patch rc to read `/etc/rcrc` before `$home/.rcrc` (small patch to `main.c`)
- Or: set `RCRC` env var if we patch rc to respect it
- Then NixOS/darwin modules can generate `/etc/rcrc` with system-wide config

### Phase 4: Tests

- Test that rc HM module generates `~/.rcrc`
- Test that rc NixOS module installs package but doesn't assert on darwin module (no conflicting files)
- Test rc-specific syntax in generated files

## Alternative: Skip Generic Builder for rc

Since rc is fundamentally non-POSIX, we could write `modules/rc.nix` as a plain NixOS module without using any generic builder. The generic builder only saves ~30 lines of boilerplate for rc. The real value is for future POSIX-like shells (yash, dash, etc.).

**Recommendation**: Do Phase 1 anyway — it makes the codebase cleaner and enables future shells. But keep the rc module simple; don't over-abstract where the abstraction doesn't fit.

## Files to Touch

1. `lib/mk-shell-module.nix` — new generic builder
2. `lib/mk-posix-shell-module.nix` — POSIX wrapper (or inline in `lib/default.nix`)
3. `lib/default.nix` — export both builders
4. `modules/rc.nix` — rc-specific module
5. `flake.nix` — wire rc modules
6. `tests/default.nix` — add rc tests

## Open Questions

1. Should rc's NixOS/darwin module set `users.defaultUserShell = pkgs.rc` or just install the package?
2. Should we patch rc for `/etc/rcrc` support now or defer?
3. For HM integration, should rc's `.rcrc` source `/etc/rcrc` if it exists (to bridge system + user config)?
