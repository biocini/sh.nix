# Report: How `programs.bash` Generates NixOS Derivation Output

## 1. Module Entry Point

**File:** `nixos/modules/programs/bash/bash.nix`

The `programs.bash` module declares options under `programs.bash.*` and, when `cfg.enable` (default: `true`), produces config in two namespaces:

- `programs.bash.*` — per-shell option values that other modules can append to
- `environment.etc.*` — actual filesystem entries in `/etc`
- `environment.shells` — registration for `chsh` / `/etc/shells`

## 2. Option Assembly (What Goes Into the Bash Config Options)

### `programs.bash.shellAliases`

```nix
programs.bash.shellAliases = builtins.mapAttrs (name: lib.mkDefault) cfge.shellAliases;
```

This takes `environment.shellAliases` (which defaults to `{ ls = "ls --color=tty"; ll = "ls -l"; l = "ls -alh"; }`) and wraps each value with `lib.mkDefault`. The result is an attrset of aliases with `default` priority, meaning downstream modules can override.

### `programs.bash.shellInit`

```nix
programs.bash.shellInit = ''
    if [ -z "$__NIXOS_SET_ENVIRONMENT_DONE" ]; then
        . ${config.system.build.setEnvironment}
    fi

    ${cfge.shellInit}
'';
```

This is a **single string** containing:

1. The `setEnvironment` bootstrap (gated by `__NIXOS_SET_ENVIRONMENT_DONE`)
2. The global `environment.shellInit` (empty by default)

### `programs.bash.loginShellInit`

```nix
programs.bash.loginShellInit = cfge.loginShellInit;
```

Direct alias of the global `environment.loginShellInit` (empty by default).

### `programs.bash.interactiveShellInit`

```nix
programs.bash.interactiveShellInit = ''
    # Disable hashing (i.e. caching) of command lookups.
    set +h

    ${cfg.promptInit}
    ${cfg.promptPluginInit}
    ${bashAliases}

    ${cfge.interactiveShellInit}
'';
```

This assembles:

1. `set +h`
2. `promptInit` — the colorful bash prompt (default is the multi-line `PROMPT_COLOR` block)
3. `promptPluginInit` — empty by default, reserved for plugins
4. `bashAliases` — rendered from `cfg.shellAliases` as `alias -- <name>='<value>'` lines
5. `cfge.interactiveShellInit` — global interactive init (empty by default)

## 3. File Generation (`environment.etc`)

### `/etc/profile`

```nix
environment.etc.profile.text = ''
    # /etc/profile: DO NOT EDIT -- this file has been generated automatically.
    # This file is read for login shells.

    # Only execute this file once per shell.
    if [ -n "$__ETC_PROFILE_SOURCED" ]; then return; fi
    __ETC_PROFILE_SOURCED=1

    # Prevent this file from being sourced by interactive non-login child shells.
    export __ETC_PROFILE_DONE=1

    ${cfg.shellInit}
    ${cfg.loginShellInit}

    # Read system-wide modifications.
    if test -f /etc/profile.local; then
        . /etc/profile.local
    fi

    if [ -n "''${BASH_VERSION:-}" ]; then
        . /etc/bashrc
    fi
'';
```

**Expanding `cfg.shellInit`:**

```sh
if [ -z "$__NIXOS_SET_ENVIRONMENT_DONE" ]; then
    . /nix/store/...-set-environment
fi

# (environment.shellInit is empty by default)
```

**So the full `/etc/profile` on a stock system is:**

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

# Read system-wide modifications.
if test -f /etc/profile.local; then
    . /etc/profile.local
fi

if [ -n "${BASH_VERSION:-}" ]; then
    . /etc/bashrc
fi
```

### `/etc/bashrc`

```nix
environment.etc.bashrc.text = ''
    # /etc/bashrc: DO NOT EDIT -- this file has been generated automatically.

    # Only execute this file once per shell.
    if [ -n "$__ETC_BASHRC_SOURCED" ] || [ -n "$NOSYSBASHRC" ]; then return; fi
    __ETC_BASHRC_SOURCED=1

    # If the profile was not loaded in a parent process, source
    # it.  But otherwise don't do it because we don't want to
    # clobber overridden values of $PATH, etc.
    if [ -z "$__ETC_PROFILE_DONE" ]; then
        . /etc/profile
    fi

    # We are not always an interactive shell.
    if [ -n "$PS1" ]; then
        ${cfg.interactiveShellInit}
    fi

    # Read system-wide modifications.
    if test -f /etc/bashrc.local; then
        . /etc/bashrc.local
    fi
'';
```

**Expanding `cfg.interactiveShellInit`** (with defaults):

```sh
# Disable hashing (i.e. caching) of command lookups.
set +h

# Provide a nice prompt if the terminal supports it.
if [ "$TERM" != "dumb" ] || [ -n "$INSIDE_EMACS" ]; then
  PROMPT_COLOR="1;31m"
  ((UID)) && PROMPT_COLOR="1;32m"
  if [ -n "$INSIDE_EMACS" ]; then
    PS1="\n\[\033[$PROMPT_COLOR\][\u@\h:\w]\\$\[\033[0m\] "
  else
    PS1="\n\[\033[$PROMPT_COLOR\][\[\e]0;\u@\h: \w\a\]\u@\h:\w]\\$\[\033[0m\] "
  fi
  if test "$TERM" = "xterm"; then
    PS1="\[\033]2;\h:\u:\w\007\]$PS1"
  fi
fi

alias -- ls='ls --color=tty'
alias -- ll='ls -l'
alias -- l='ls -alh'

# (environment.interactiveShellInit is empty by default)
```

**So `/etc/bashrc`** has the guard `if [ -n "$PS1" ]` wrapping all interactive content, plus a fallback to re-source `/etc/profile` if `__ETC_PROFILE_DONE` is missing.

### Interactive Guard Pattern

NixOS bash places the interactive guard **after** the `__ETC_PROFILE_DONE` fallback and **before** any interactive content (prompt, aliases, history). The guard is `if [ -n "$PS1" ]` which tests whether a prompt string is set. This ensures non-interactive shells (e.g., `bash -c 'echo hi'`) exit early from `/etc/bashrc` after the environment bootstrap but before any interactive setup.

This same pattern must be reproduced for any POSIX shell's system-wide rc file (`/etc/kshrc`, `/etc/yashrc`, etc.) to prevent non-interactive login shells from running interactive setup.

### `/etc/bash_logout`

```sh
if [ -n "$__ETC_BASHLOGOUT_SOURCED" ] || [ -n "$NOSYSBASHLOGOUT" ]; then return; fi
__ETC_BASHLOGOUT_SOURCED=1

printf '\e]0;\a'

if test -f /etc/bash_logout.local; then
    . /etc/bash_logout.local
fi
```

## 4. The `set-environment` Bootstrap

**File:** `nixos/modules/config/shells-environment.nix`

```nix
system.build.setEnvironment = pkgs.writeText "set-environment" ''
  # DO NOT EDIT -- this file has been generated automatically.

  # Prevent this file from being sourced by child shells.
  export __NIXOS_SET_ENVIRONMENT_DONE=1

  ${exportedEnvVars}

  ${cfg.extraInit}

  ${lib.optionalString cfg.homeBinInPath ''
    # ~/bin if it exists overrides other bin directories.
    export PATH="$HOME/bin:$PATH"
  ''}

  ${lib.optionalString cfg.localBinInPath ''
    export PATH="$HOME/.local/bin:$PATH"
  ''}
'';
```

Where `exportedEnvVars` is built from:

1. `environment.variables` (absolute values)
2. `environment.profileRelativeEnvVars` (paths relative to each profile)
3. All merged and rendered as `export VAR="value"` lines

On a stock system, this sets `__NIXOS_SET_ENVIRONMENT_DONE=1` plus `PATH`, `XDG_CONFIG_DIRS`, `XDG_DATA_DIRS`, `NIX_USER_PROFILE_DIR`, `NIX_PROFILES`, etc.

## 5. `/etc` Assembly Pipeline

**File:** `nixos/modules/system/etc/etc.nix`

Each `environment.etc.<name>.text = "..."` entry gets converted to a store path:

```nix
config = {
  target = lib.mkDefault name;
  source = lib.mkIf (config.text != null) (
    let name' = "etc-" + lib.replaceStrings [ "/" ] [ "-" ] name;
    in lib.mkDerivedConfig options.text (pkgs.writeText name')
  );
};
```

So `environment.etc.profile.text = "..."` becomes:

- `environment.etc.profile.source = pkgs.writeText "etc-profile" "..."`
- A store path like `/nix/store/...-etc-profile`

Then `system.build.etc` is a derivation that symlinks all these sources into `$out/etc/`:

```nix
system.build.etc = pkgs.runCommandLocal "etc" { ... } ''
  makeEtcEntry() {
    src="$1"
    target="$2"
    # ...
    ln -s "$src" "$out/etc/$target"
  }
  # ...
'';
```

At system activation time, `setup-etc.pl` (or the overlayfs remount logic) copies/symlinks these into the live `/etc`.

## 6. Summary: What Bash Actually Produces

| File               | Store Path                               | Live Path                | Content                                                                                    |
| ------------------ | ---------------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------ |
| `set-environment`  | `pkgs.writeText "set-environment" "..."` | (sourced, not in `/etc`) | `export __NIXOS_SET_ENVIRONMENT_DONE=1`, plus env vars                                     |
| `/etc/profile`     | `pkgs.writeText "etc-profile" "..."`     | `/etc/profile`           | Guard, `setEnvironment`, `shellInit`, `loginShellInit`, `profile.local`, **bashrc bridge** |
| `/etc/bashrc`      | `pkgs.writeText "etc-bashrc" "..."`      | `/etc/bashrc`            | Guard, profile fallback, `interactiveShellInit` (prompt + aliases), `bashrc.local`         |
| `/etc/bash_logout` | `pkgs.writeText "etc-bash_logout" "..."` | `/etc/bash_logout`       | Guard, title reset, `bash_logout.local`                                                    |

The `/etc/profile` → `/etc/bashrc` bridge is gated on `${BASH_VERSION:-}`.
