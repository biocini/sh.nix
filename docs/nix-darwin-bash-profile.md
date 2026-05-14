# Report: How `programs.bash` Generates nix-darwin Derivation Output

## 1. Module Entry Point

**File:** `modules/programs/bash/default.nix`

The nix-darwin `programs.bash` module declares options under `programs.bash.*` and, when `cfg.enable` (default: `true`), produces config in two namespaces:

- `programs.bash.*` — per-shell option values
- `environment.etc.*` — actual filesystem entries in `/etc`
- `environment.systemPackages` — bash package installation

**Critical difference from NixOS:** nix-darwin's bash module does **not** generate `/etc/profile`. The stock macOS `/etc/profile` is preserved.

## 2. Option Assembly

### `programs.bash.interactiveShellInit`

Default is `""`. This is user-facing option for additional bash-specific interactive init.

### `programs.bash.completion.enable`

Default `false`. When enabled, adds `bash-completion` package and sources it in `/etc/bashrc`.

## 3. File Generation (`environment.etc`)

### `/etc/bashrc` (the only file bash generates)

```nix
environment.etc."bashrc".text = ''
    # /etc/bashrc: DO NOT EDIT -- this file has been generated automatically.
    # This file is read for interactive shells.

    [ -r "/etc/bashrc_$TERM_PROGRAM" ] && . "/etc/bashrc_$TERM_PROGRAM"

    # Only execute this file once per shell.
    if [ -n "$__ETC_BASHRC_SOURCED" -o -n "$NOSYSBASHRC" ]; then return; fi
    __ETC_BASHRC_SOURCED=1

    if [ -z "$__NIX_DARWIN_SET_ENVIRONMENT_DONE" ]; then
      . ${config.system.build.setEnvironment}
    fi

    # Return early if not running interactively, but after basic nix setup.
    [[ $- != *i* ]] && return

    # Make bash check its window size after a process completes
    shopt -s checkwinsize

    ${config.system.build.setAliases.text}

    ${config.environment.interactiveShellInit}
    ${cfg.interactiveShellInit}

    ${optionalString cfg.completion.enable ''
      if [ "$TERM" != "dumb" ]; then
        source "${cfg.completion.package}/etc/profile.d/bash_completion.sh"

        nullglobStatus=$(shopt -p nullglob)
        shopt -s nullglob
        for p in $NIX_PROFILES; do
          for m in "$p/etc/bash_completion.d/"*; do
            source $m
          done
        done
        eval "$nullglobStatus"
        unset nullglobStatus p m
      fi
    ''}

    # Read system-wide modifications.
    if test -f /etc/bash.local; then
      source /etc/bash.local
    fi
'';
```

**Key behaviors:**

1. **Term-specific file first:** `[ -r "/etc/bashrc_$TERM_PROGRAM" ] && . "/etc/bashrc_$TERM_PROGRAM"` — macOS convention for terminal-specific config.
2. **Guard:** `if [ -n "$__ETC_BASHRC_SOURCED" -o -n "$NOSYSBASHRC" ]; then return; fi`
3. **`setEnvironment` sourced here** (not in `/etc/profile`): `. ${config.system.build.setEnvironment}`
4. **Interactive guard:** `[[ $- != *i* ]] && return` — returns after nix setup if not interactive
5. **Aliases:** `. ${config.system.build.setAliases.text}` — nix-darwin has a separate `setAliases` derivation
6. **Global init:** `${config.environment.interactiveShellInit}` — nix-darwin's global interactive init
7. **Bash-specific init:** `${cfg.interactiveShellInit}`
8. **Completion:** Optional bash-completion sourcing with nullglob
9. **Local file:** `/etc/bash.local` (not `.local`)

### `/etc/profile` — NOT generated

nix-darwin does **not** set `environment.etc.profile.text`. The stock macOS `/etc/profile` remains:

```sh
# System-wide .profile for sh(1)
if [ -x /usr/libexec/path_helper ]; then
    eval `/usr/libexec/path_helper -s`
fi
if [ "${BASH-no}" != "no" ]; then
    [ -r /etc/bashrc ] && . /etc/bashrc
fi
```

This is why our `darwinProfile` includes the `path_helper` call and the bash escape hatch — it replaces the stock macOS file.

### `knownSha256Hashes`

```nix
environment.etc."bashrc".knownSha256Hashes = [
  "444c716ac2ccd9e1e3347858cb08a00d2ea38e8c12fdc5798380dc261e32e9ef"  # macOS
  "617b39e36fa69270ddbee19ddc072497dbe7ead840cbd442d9f7c22924f116f4"  # official Nix installer
  "6be16cf7c24a3c6f7ae535c913347a3be39508b3426f5ecd413e636e21031e66"  # official Nix installer
  "08ffbf991a9e25839d38b80a0d3bce3b5a6c84b9be53a4b68949df4e7e487bb7"  # DeterminateSystems installer
];
```

These hashes allow nix-darwin to overwrite stock `/etc/bashrc` files safely during activation.

## 4. The `set-environment` Bootstrap

**File:** `modules/environment/default.nix`

```nix
system.build.setEnvironment = pkgs.writeText "set-environment" ''
  # Prevent this file from being sourced by child shells.
  export __NIX_DARWIN_SET_ENVIRONMENT_DONE=1

  export PATH=${config.environment.systemPath}
  ${concatStringsSep "\n" exportVariables}

  # Extra initialisation
  ${cfg.extraInit}
'';
```

Where:

- `config.environment.systemPath` = `makeBinPath profiles` + `/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`
- `exportVariables` = `export VAR="value"` lines from `environment.variables`
- `cfg.extraInit` = `NIX_USER_PROFILE_DIR` and `NIX_PROFILES` exports

On a stock system:

```sh
export __NIX_DARWIN_SET_ENVIRONMENT_DONE=1
export PATH="/run/current-system/sw/bin:...:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export XDG_CONFIG_DIRS="/run/current-system/sw/etc/xdg"
export XDG_DATA_DIRS="/run/current-system/sw/share"
export EDITOR="nano"
export PAGER="less -R"
export NIX_USER_PROFILE_DIR="/nix/var/nix/profiles/per-user/$USER"
export NIX_PROFILES="/nix/var/nix/profiles/default /run/current-system/sw $HOME/.nix-profile"
```

### `system.build.setAliases`

```nix
system.build.setAliases = pkgs.writeText "set-aliases" ''
  ${concatStringsSep "\n" aliasCommands}
'';
```

Where `aliasCommands = mapAttrsToList (n: v: ''alias ${n}=${escapeShellArg v}'')`.

## 5. `/etc` Assembly Pipeline

**File:** `modules/system/etc.nix`

nix-darwin's `/etc` assembly is simpler than NixOS's:

```nix
system.build.etc = pkgs.runCommand "etc" { preferLocalBuild = true; } ''
  mkdir -p $out/etc
  cd $out/etc
  ${concatMapStringsSep "\n" (attr: ''
    mkdir -p "$(dirname ${escapeShellArg attr.target})"
    ln -s ${escapeShellArgs [ attr.source attr.target ]}
  '') etc}
'';
```

At activation time:

1. Symlinks `$systemConfig/etc` to `/etc/static`
2. For each file in `/etc/static`, creates a symlink in `/etc`
3. Backs up existing files to `*.before-nix-darwin`
4. Checks `knownSha256Hashes` before overwriting stock files

## 6. Summary: What Bash Actually Produces on nix-darwin

| File              | Generated? | Content                                                        |
| ----------------- | ---------- | -------------------------------------------------------------- |
| `set-environment` | Yes        | `export __NIX_DARWIN_SET_ENVIRONMENT_DONE=1`, `PATH`, env vars |
| `set-aliases`     | Yes        | `alias name='value'` lines                                     |
| `/etc/profile`    | **No**     | Stock macOS file preserved                                     |
| `/etc/bashrc`     | Yes        | `setEnvironment`, aliases, interactive init, completion        |
| `/etc/bash.local` | No         | User hook, sourced at end of `/etc/bashrc`                     |

### Interactive Guard Pattern

nix-darwin bash places the interactive guard **after** the `setEnvironment` bootstrap and **before** any interactive content. The guard is `[[ $- != *i* ]] && return` which tests the shell options for the `i` (interactive) flag. This ensures non-interactive shells exit early from `/etc/bashrc` after the environment bootstrap but before any interactive setup.

This same pattern must be reproduced for any POSIX shell's system-wide rc file (`/etc/kshrc`, `/etc/yashrc`, etc.) to prevent non-interactive login shells from running interactive setup.

## 7. Key Differences from NixOS

| Aspect                    | NixOS                       | nix-darwin                           |
| ------------------------- | --------------------------- | ------------------------------------ |
| `/etc/profile`            | **Generated from scratch**  | **Stock macOS file preserved**       |
| `setEnvironment` location | `/etc/profile`              | `/etc/bashrc`                        |
| Bashrc bridge             | In generated `/etc/profile` | In stock `/etc/profile`              |
| Interactive guard         | `if [ -n "$PS1" ]`          | `[[ $- != *i* ]] && return`          |
| Aliases                   | Inlined into `/etc/bashrc`  | Sourced from `setAliases` derivation |
| Local file                | `/etc/bashrc.local`         | `/etc/bash.local`                    |
| `knownSha256Hashes`       | None                        | `/etc/bashrc` only                   |
| `path_helper`             | Not used                    | Called in stock `/etc/profile`       |

## 8. Implications for sh.nix

Our `darwinProfile` replaces the stock macOS `/etc/profile` with a generated one. This is necessary because:

1. The stock profile does not source `setEnvironment` for non-bash shells
2. The stock profile does not set `__ETC_PROFILE_DONE`
3. We need to bridge to `$ENV` for our POSIX shells

Our generated `darwinProfile` must reproduce the stock macOS behavior (including `path_helper` and the bash escape hatch) while adding our POSIX shell support.
