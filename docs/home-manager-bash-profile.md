# Home Manager `programs.bash` — Full Behavioral Breakdown

**Source:** `github.com/nix-community/home-manager/modules/programs/bash.nix`

---

## 1. Generated Files

| File              | Purpose                         | Guards                                  |
| ----------------- | ------------------------------- | --------------------------------------- |
| `~/.bash_profile` | Login shell init                | None (sources `.profile` and `.bashrc`) |
| `~/.profile`      | Session variables + login extra | `__HM_SESS_VARS_SOURCED`                |
| `~/.bashrc`       | Interactive shell init          | `[[ $- == *i* ]]`                       |
| `~/.bash_logout`  | Logout (optional)               | None                                    |

---

## 2. `~/.bash_profile` — The Entry Point

```sh
# include .profile if it exists
[[ -f ~/.profile ]] && . ~/.profile

# include .bashrc if it exists
[[ -f ~/.bashrc ]] && . ~/.bashrc
```

**Key behavior:** Home Manager's bash **always** sources `.bashrc` from `.bash_profile`, even though `.bash_profile` is for login shells and `.bashrc` is for interactive shells. This is bash-specific behavior — bash does not automatically source `.bashrc` from `.bash_profile`, so Home Manager bridges the gap.

**Contrast with NixOS:** NixOS bash uses `/etc/profile` → `/etc/bashrc` bridge. Home Manager uses `~/.bash_profile` → `~/.bashrc` bridge.

---

## 3. `~/.profile` — Session Variables + Login Extra

```sh
. "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"

${sessionVarsStr}

${cfg.profileExtra}
```

### `hm-session-vars.sh`

This is a generated script that lives in the Nix store:

```sh
# Only source this once.
if [ -n "$__HM_SESS_VARS_SOURCED" ]; then return; fi
export __HM_SESS_VARS_SOURCED=1

export EDITOR="nano"
export PATH="$HOME/.local/bin:${PATH:+:}$PATH"
...
```

**Key properties:**

- Sourced from `~/.profile`, which is sourced from `~/.bash_profile`
- Guarded by `__HM_SESS_VARS_SOURCED` — idempotent across multiple sourcings
- Contains all `home.sessionVariables` and `home.sessionSearchVariables` (including PATH)
- Is a package in the user environment, so the path is a Nix store path

### `sessionVarsStr`

Additional per-shell session variables from `programs.bash.sessionVariables`:

```sh
export FOO="bar"
```

**Note:** `sessionVariables` is separate from `home.sessionVariables`. The former is bash-specific; the latter is global to all Home Manager shells.

### `profileExtra`

User-defined extra login shell commands:

```nix
programs.bash.profileExtra = ''
  echo "Welcome to bash"
'';
```

---

## 4. `~/.bashrc` — Interactive Shell Init

```sh
${cfg.bashrcExtra}

# Commands that should be applied only for interactive shells.
[[ $- == *i* ]] || return

${historyControlStr}

${shoptsStr}

${aliasesStr}

${cfg.initExtra}
```

### `bashrcExtra`

Runs **before** the interactive guard:

```nix
programs.bash.bashrcExtra = ''
  # This runs in ALL shells, even non-interactive
'';
```

### Interactive guard: `[[ $- == *i* ]]`

Bash-specific syntax. After this point:

### `historyControlStr`

```sh
HISTFILESIZE=100000
HISTSIZE=10000
HISTFILE="/home/user/.bash_history"
HISTCONTROL="ignoredups:ignorespace"
HISTIGNORE='ls:cd:exit'
mkdir -p "$(dirname "$HISTFILE")"
```

### `shoptsStr`

```sh
shopt -s histappend
shopt -s extglob
shopt -s globstar
shopt -s checkjobs
```

### `aliasesStr`

```sh
alias -- ll='ls -l'
```

Uses `--` to allow aliases that start with `-`.

### `initExtra`

User-defined extra interactive shell commands. Completion sourcing is injected here via `mkOrder 100`:

```nix
programs.bash.initExtra = ''
  # This runs in interactive shells only
'';
```

---

## 5. Option Mapping

| Option             | Type          | Default  | Goes In          | Guard                                 |
| ------------------ | ------------- | -------- | ---------------- | ------------------------------------- |
| `profileExtra`     | `lines`       | `""`     | `~/.profile`     | None (login shell)                    |
| `sessionVariables` | `attrsOf`     | `{}`     | `~/.profile`     | None (after hm-session-vars)          |
| `bashrcExtra`      | `lines`       | `""`     | `~/.bashrc`      | **Before** interactive guard          |
| `initExtra`        | `lines`       | `""`     | `~/.bashrc`      | After interactive guard               |
| `logoutExtra`      | `lines`       | `""`     | `~/.bash_logout` | None                                  |
| `shellAliases`     | `attrsOf str` | `{}`     | `~/.bashrc`      | After interactive guard               |
| `shellOptions`     | `listOf str`  | `[...]`  | `~/.bashrc`      | After interactive guard               |
| `historySize`      | `nullOr int`  | `10000`  | `~/.bashrc`      | After interactive guard               |
| `historyFile`      | `nullOr str`  | `null`   | `~/.bashrc`      | After interactive guard               |
| `historyFileSize`  | `nullOr int`  | `100000` | `~/.bashrc`      | After interactive guard               |
| `historyControl`   | `listOf enum` | `[]`     | `~/.bashrc`      | After interactive guard               |
| `historyIgnore`    | `listOf str`  | `[]`     | `~/.bashrc`      | After interactive guard               |
| `enableCompletion` | `bool`        | `true`   | `~/.bashrc`      | After interactive guard (mkOrder 100) |

**Note:** There is NO `shellInit`, `loginShellInit`, or `interactiveShellInit` option in Home Manager bash. These are NixOS/nix-darwin concepts. Home Manager uses `profileExtra`, `bashrcExtra`, and `initExtra` instead.

---

## 6. Comparison: NixOS vs nix-darwin vs Home Manager

| Feature            | NixOS                              | nix-darwin                         | Home Manager                          |
| ------------------ | ---------------------------------- | ---------------------------------- | ------------------------------------- |
| Profile file       | `/etc/profile`                     | `/etc/profile` (stock)             | `~/.bash_profile`                     |
| RC file            | `/etc/bashrc`                      | `/etc/bashrc`                      | `~/.bashrc`                           |
| Session vars       | `/etc/set-environment`             | `/etc/set-environment`             | `hm-session-vars.sh` + `~/.profile`   |
| Login extra        | `environment.loginShellInit`       | dead option                        | `profileExtra`                        |
| Unconditional init | `environment.shellInit`            | dead option                        | `bashrcExtra` (before guard)          |
| Interactive init   | `environment.interactiveShellInit` | `environment.interactiveShellInit` | `initExtra` (after guard)             |
| Aliases            | Inline in `/etc/bashrc`            | `system.build.setAliases`          | Inline in `~/.bashrc`                 |
| Guard              | `if [ -n "$PS1" ]`                 | `[[ $- != *i* ]]`                  | `[[ $- == *i* ]]`                     |
| setEnvironment     | In `/etc/profile`                  | In `/etc/bashrc`                   | In `~/.profile` (via hm-session-vars) |
| Completion         | `pathsToLink`                      | `pathsToLink`                      | `enableCompletion` + `mkOrder 100`    |

---

## 7. Key Observations for sh.nix

### 7.1 No `shellInit` / `loginShellInit` / `interactiveShellInit` in HM

Home Manager bash does not expose these options at all. Our `hmProfile` and `hmRc` templates use:

- `profileExtra` → login shell init (analogous to `loginShellInit`)
- `initExtra` → interactive shell init (analogous to `interactiveShellInit`)

This is a naming mismatch. Our `mk-shell-module.nix` exposes `loginShellInit` and `interactiveShellInit` via `envBridge`, but Home Manager consumers would need to map these to `profileExtra` and `initExtra`.

### 7.2 `bashrcExtra` is unique to HM

Home Manager has a concept of "extra commands that run before the interactive guard" (`bashrcExtra`). NixOS and nix-darwin have no equivalent. Our current `hmRc` template does not have a `bashrcExtra` equivalent.

### 7.3 `hm-session-vars.sh` is global

`home.sessionVariables` is shared across ALL Home Manager shells (bash, zsh, fish). It's sourced from `~/.profile`, which is sourced by all POSIX shells (not just bash). This is analogous to `environment.variables` on NixOS/nix-darwin.

Our current `hmProfile` sources `hm-session-vars.sh` and then adds `sessionVariables` (per-shell). This is correct.

### 7.4 Aliases are per-shell in HM

Home Manager bash aliases are generated inline in `~/.bashrc`. There's no `setAliases` file like nix-darwin has. Our `hmRc` template inlines aliases, which is correct.

### 7.5 No `__ETC_PROFILE_DONE` mechanism in HM

Home Manager does not set `__ETC_PROFILE_DONE` or `__ETC_PROFILE_SOURCED`. These are system-level (NixOS/nix-darwin) concepts. Our `hmProfile` and `hmRc` do not use them, which is correct.

---

## 8. How sh.nix's HM Module Currently Works

**Source:** `lib/posix/files.nix` (`hmProfile` and `hmRc`)

### `hmProfile` (`~/.profile`)

```sh
. "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"

${sessionVariablesStr}

${cfg.profileExtra}
```

This matches Home Manager bash's `~/.profile` almost exactly, except:

- sh.nix adds `sessionVariables` (per-shell session vars)
- Home Manager bash also adds `sessionVariables` (but we handle it via `extraHmOptions`)

### `hmRc` (`~/.${name}rc`)

```sh
if [ -n "$__HOME_${PNAME}RC_SOURCED" ]; then return; fi
__HOME_${PNAME}RC_SOURCED=1

case $- in
  *i*) ;;
  *) return ;;
esac

HISTSIZE=${toString cfg.histSize}
HISTFILE=${cfg.histFile}

${aliasesStr}

${cfg.initExtra}
```

Differences from Home Manager bash's `~/.bashrc`:
| Feature | sh.nix hmRc | Home Manager bashrc |
|---------|-------------|---------------------|
| Once-per-shell guard | `__HOME_*RC_SOURCED` | `__ETC_BASHRC_SOURCED` (HM doesn't set this) |
| Interactive guard | `case $- in *i*)` | `[[ $- == *i* ]]` |
| History | `HISTSIZE`, `HISTFILE` | `HISTSIZE`, `HISTFILE`, `HISTFILESIZE`, `HISTCONTROL`, `HISTIGNORE` |
| Aliases | `alias k=v` | `alias -- k=v` |
| shopt | Not set | `histappend`, `extglob`, `globstar`, `checkjobs` |
| Completion | Not handled | `enableCompletion` + `mkOrder 100` |
| bashrcExtra | Not supported | Supported (before guard) |

### `hmOnlyOptions`

Our `lib/posix/options.nix` `hmOptions` exposes:

- `profileExtra` → maps to login shell init
- `sessionVariables` → maps to per-shell session variables
- `logoutExtra` → generates `~/.${name}_logout` with trap

Home Manager bash does not have `logoutExtra`. It has `logoutExtra` directly in `programs.bash`. Our naming matches.

---

## 9. Implications for Unified Profile Design

The unified `/etc/profile` generator is **only for NixOS and nix-darwin**. Home Manager is NOT affected because:

1. Home Manager does not generate `/etc/profile` or `/etc/bashrc`
2. Home Manager uses `~/.bash_profile` → `~/.bashrc` bridge
3. Home Manager's session variable mechanism (`hm-session-vars.sh`) is independent

The unified profile generator should be imported ONLY by `nixosModule` and `darwinModule`, NOT by `homeManagerModule`.

Our current handoff memo already reflects this (the `homeManagerModule` is unchanged).
