# Design Proposal: Unified `/etc/profile` Generator

## Objective

Replace the current per-shell `/etc/profile` generation (which uses `lib.mkForce` and conflicts when multiple POSIX shells are enabled) with a single unified profile that dispatches to each shell's rc file via a dynamically generated guard block.

## The Problem

Currently, each call to `mkPosixShellModule` generates its own `/etc/profile` via `lib.mkForce`:

```nix
nixosFiles = {
  ${etcRcPath} = { content = ...; };
  "profile" = { content = posFiles.nixosProfile { inherit name; }; };  # mkForce!
};
```

If a user enables both `programs.ksh` and `programs.yash`, both modules `mkForce` `environment.etc.profile.text` and the module system reports a conflict. Even with only one shell enabled, our `nixosProfile` overrides upstream `programs.bash`'s profile and drops the bash → bashrc bridge.

## First Principles

1. **`/etc/profile` is a POSIX login shell file.** It should be shell-neutral in its body and only shell-specific in its dispatch tail.
2. **All POSIX shells on a given platform share the same global init.** `environment.shellInit`, `environment.loginShellInit`, and `setEnvironment` are platform-global, not per-shell.
3. **The only shell-specific decision in `/etc/profile` is which rc file to source.** Everything else is shared infrastructure.
4. **A shell identifies itself via exported variables at runtime.** `BASH_VERSION`, `KSH_VERSION`, `YASH_VERSION`, etc. These are reliable and standard.

## Architecture

### New Files

```
lib/posix/
├── registry.nix        # Declares options._shnix.posixShells
├── guards.nix          # Default guard expressions: bash, ksh, yash, ...
├── profile-nixos.nix   # Generates /etc/profile on NixOS
└── profile-darwin.nix  # Generates /etc/profile on nix-darwin
```

### 1. Registry (`registry.nix`)

Declares an internal option where each enabled POSIX shell registers itself:

```nix
options._shnix.posixShells = lib.mkOption {
  type = lib.types.attrsOf (lib.types.submodule {
    options = {
      guard = lib.mkOption { type = lib.types.str; };
      rcFile = lib.mkOption { type = lib.types.str; };
      priority = lib.mkOption { type = lib.types.int; default = 100; };
    };
  });
  default = {};
  internal = true;
};
```

### 2. Guard Expressions (`guards.nix`)

```nix
{
  bash = ''[ -n "${BASH_VERSION:-}" ]'';
  ksh  = ''[ -n "$KSH_VERSION" ]'';
  ksh93 = ''[ -n "$KSH_VERSION" ]'';   # same variable
  mksh = ''[ -n "$KSH_VERSION" ]'';    # same variable
  yash = ''[ -n "$YASH_VERSION" ]'';
}
```

Unknown shells can provide a custom guard, or fall back to `$ENV` dispatch.

### 3. Profile Generators

Both NixOS and nix-darwin profile generators:

1. Import `registry.nix`
2. Read `config._shnix.posixShells`
3. Sort by priority
4. Generate `environment.etc.profile.text` with `lib.mkForce`

#### NixOS Profile

```sh
# /etc/profile: DO NOT EDIT -- this file has been generated automatically.
# This file is read for login shells.

# Only execute this file once per shell.
if [ -n "$__ETC_PROFILE_SOURCED" ]; then return; fi
__ETC_PROFILE_SOURCED=1

# Prevent this file from being sourced by interactive non-login child shells.
export __ETC_PROFILE_DONE=1

if [ -z "$__NIXOS_SET_ENVIRONMENT_DONE" ]; then
    . /nix/store/...-set-environment
fi

${config.environment.shellInit}
${config.environment.loginShellInit}

# Read system-wide modifications.
if test -f /etc/profile.local; then
    . /etc/profile.local
fi

# Dispatch to shell-specific rc, setting ENV for child non-login shells
if [ -n "${BASH_VERSION:-}" ]; then
  export ENV=/etc/bashrc
  [ -r /etc/bashrc ] && . /etc/bashrc
elif [ -n "$KSH_VERSION" ]; then
  export ENV=/etc/kshrc
  [ -r /etc/kshrc ] && . /etc/kshrc
elif [ -n "$YASH_VERSION" ]; then
  export ENV=/etc/yashrc
  [ -r /etc/yashrc ] && . /etc/yashrc
fi
```

#### nix-darwin Profile

Identical structure to NixOS, with two differences:

1. Uses `__NIX_DARWIN_SET_ENVIRONMENT_DONE` instead of `__NIXOS_SET_ENVIRONMENT_DONE`
2. **Does not call `/usr/libexec/path_helper` at runtime**. Instead, `profile-darwin.nix` reads `/etc/paths`, `/etc/paths.d/*`, `/etc/manpaths`, and `/etc/manpaths.d/*` at Nix evaluation time and appends their entries to `environment.systemPath` (with deduplication against existing entries).

This avoids the `path_helper` reordering bug where Apple paths shadow Nix paths, and fixes the MANPATH regression (`/opt/homebrew/share/man::`).

### nix-darwin `path_helper` Replacement

The nix-darwin profile generator (`profile-darwin.nix`) performs the following at evaluation time:

```nix
let
  # Read system paths at eval time
  readPaths = dir:
    let
      entries = builtins.attrNames (builtins.readDir dir);
      sorted = builtins.sort builtins.lessThan entries;
      paths = map (f: lib.removeSuffix "\n" (builtins.readFile (dir + "/" + f))) sorted;
    in
    lib.concatMap (lib.splitString "\n") paths;

  systemPaths = readPaths "/etc/paths.d" ++ lib.splitString "\n" (builtins.readFile "/etc/paths");
  systemManPaths = readPaths "/etc/manpaths.d" ++ lib.splitString "\n" (builtins.readFile "/etc/manpaths");

  # Deduplicate against already-configured paths
  newPaths = lib.subtractLists config.environment.systemPath systemPaths;
  newManPaths = lib.subtractLists (config.environment.profileRelativeEnvVars.MANPATH or []) systemManPaths;
in
{
  config.environment.systemPath = lib.mkAfter newPaths;
  config.environment.profileRelativeEnvVars.MANPATH = lib.mkAfter newManPaths;
}
```

This is an impure operation (reads system files at eval time), but it is the only way to:

1. Preserve Nix path priority (Nix paths come before Apple paths)
2. Include Apple-specific paths that change between macOS releases
3. Avoid the `path_helper` MANPATH regression

### Interactive Guard in System RC Files

Every system-wide rc file (`/etc/kshrc`, `/etc/yashrc`, etc.) includes an interactive guard placed **after** the `__ETC_PROFILE_DONE` fallback and **before** any interactive content:

```sh
# If /etc/profile was not loaded in a parent process, source it.
if [ -z "$__ETC_PROFILE_DONE" ]; then
  . /etc/profile
fi

# Commands that should be applied only for interactive shells.
case $- in
  *i*) ;;
  *) return ;;
esac

# Setup command line history.
HISTSIZE=${toString cfg.histSize}
HISTFILE=${cfg.histFile}

# Safe defaults.
set -o noclobber
PS1="..."

# Aliases, prompt, interactive init...
```

This mirrors upstream behavior:

- **NixOS bash**: `if [ -n "$PS1" ]; then ...; fi` — tests for prompt string
- **nix-darwin bash**: `[[ $- != *i* ]] && return` — tests shell options for interactive flag
- **sh.nix**: `case $- in *i*) ;; *) return ;; esac` — POSIX-compatible, works in all shells

The guard ensures non-interactive login shells (e.g., `ksh -l -c 'echo hi'`) exit early after the environment bootstrap but before any interactive setup.

### Why No Dash Guard?

Dash has no interactive features (no history, no line editing, no `set -o` beyond POSIX). It is designed for scripts, not login shells. If a user uses dash interactively, they expect a minimal environment. The explicit guards cover all interactive shells; dash falls through silently with no rc file sourced. No `ENV` is set, so child dash processes remain clean.

### 4. `mkPosixShellModule` Changes

**Removes** `/etc/profile` from `nixosFiles` and `darwinFiles`. **Adds** shell registration:

```nix
{
  name,
  etcRcPath ? name + "rc",
  homeRcPath ? "." + name + "rc",
  guard ? (import ./guards.nix).${name} or null,
}:

let
  shellRegistration = { config, lib, ... }: {
    config._shnix.posixShells.${name} = lib.mkIf config.programs.${name}.enable {
      inherit guard rcFile;
      priority = 100;
    };
  };
in
import ./mk-shell-module.nix {
  inherit name;
  # ... extraOptions, configs, hmFiles ...
  nixosFiles = {
    ${etcRcPath} = { content = posFiles.nixosRc { ... }; };
    # "profile" REMOVED
  };
  darwinFiles = {
    ${etcRcPath} = { content = posFiles.darwinRc { ... }; };
    # "profile" REMOVED
  };
} // {
  nixosModule = { ... }: {
    imports = [
      (import ./mk-shell-module.nix { ... }).nixosModule
      shellRegistration
      ./profile-nixos.nix
    ];
  };
  darwinModule = { ... }: {
    imports = [
      (import ./mk-shell-module.nix { ... }).darwinModule
      shellRegistration
      ./profile-darwin.nix
    ];
  };
  homeManagerModule = (import ./mk-shell-module.nix { ... }).homeManagerModule;
}
```

Each returned module imports the appropriate profile generator. Duplicate imports are idempotent — enabling 3 shells imports `profile-nixos.nix` 3 times, but it only generates one `/etc/profile`.

### 5. Preserved Behavior

| Feature                       | Current                     | Proposed                      |
| ----------------------------- | --------------------------- | ----------------------------- |
| `envBridge`                   | Pure data extraction        | **Preserved**                 |
| `mkShellModule`               | Universal assembler         | **Preserved**                 |
| `__ETC_PROFILE_SOURCED` guard | Once-per-process            | **Preserved**                 |
| `__ETC_PROFILE_DONE`          | Child shell guard           | **Preserved**                 |
| `profile.local` hook          | Local override              | **Preserved**                 |
| `setEnvironment` bootstrap    | Platform-specific           | **Preserved**                 |
| Per-shell rc files            | `/etc/kshrc`, `/etc/yashrc` | **Preserved**                 |
| `environment.shells`          | Shell registration          | **Preserved** (already added) |

### 6. Removed/Changed Behavior

| Feature                                    | Current                              | Proposed                                                              |
| ------------------------------------------ | ------------------------------------ | --------------------------------------------------------------------- |
| `/etc/profile` generation                  | Per-shell `mkForce`                  | **Single unified generator**                                          |
| `ENV` as primary dispatch                  | Profile ends with `. "$ENV"`         | **Dynamic guard block** with `export ENV=...` per shell               |
| `environment.variables.ENV`                | Set by each POSIX shell module       | **Removed** — handled inside guard block                              |
| `programs.${name}.shellInit`               | Assembled per-shell, read by profile | **Profile reads global values directly** (they were identical anyway) |
| `nixosProfile` / `darwinProfile` templates | In `files.nix`                       | **Moved to profile generators**                                       |
| Multi-shell conflict                       | `mkForce` collision                  | **No collision** — single generator reads registry                    |

## Why This Is Better

1. **No conflicts:** One module generates `/etc/profile`, regardless of how many POSIX shells are enabled.
2. **Bash works:** The dynamic guard includes bash, so bash login shells still reach `/etc/bashrc`.
3. **Extensible:** Adding a new shell means adding one line to `guards.nix` and calling `mkPosixShellModule`.
4. **Platform-convergent:** NixOS and nix-darwin share the same registry and guard logic; only the profile template differs.
5. **No global `ENV` conflict:** `ENV` is set inside the guard block, not via `environment.variables.ENV`. Each shell exports its own `ENV` value after being identified.

## Open Questions

1. **What about zsh?** zsh is not a POSIX shell in the standard startup sequence. It uses `/etc/zshenv`, `/etc/zprofile`, `/etc/zshrc`. It should not register in `_shnix.posixShells`. Our design is for POSIX shells only.

2. **What about dash child shells of ksh?** If a ksh user runs `dash`, dash inherits `ENV=/etc/kshrc` and sources it. Since dash has no interactive features, the impact is minimal (some variables are set and ignored). This is an acceptable edge case for a script shell running inside an interactive shell.

## Implementation Plan

1. Create `lib/posix/registry.nix`
2. Create `lib/posix/guards.nix`
3. Create `lib/posix/profile-nixos.nix`
4. Create `lib/posix/profile-darwin.nix`
5. Modify `lib/mk-posix-shell.nix` to register shells and import profile generators
6. Remove `nixosProfile` and `darwinProfile` from `lib/posix/files.nix`
7. Remove `environment.variables.ENV` from `lib/posix/configs.nix`
8. Update tests to verify multi-shell behavior
9. Update documentation
