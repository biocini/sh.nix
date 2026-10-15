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

## 7. sh.nix home-manager module

**Source:** `lib/posix/configs.nix` (`hm`) and `lib/posix/files.nix` (`hmRc`)

### Option mapping

home-manager bash has no `shellInit`, `loginShellInit` or `interactiveShellInit`. The sh.nix home-manager module uses the home-manager names:

| sh.nix option      | home-manager bash option | Location                      |
| ------------------ | ------------------------ | ----------------------------- |
| `profileExtra`     | `profileExtra`           | `~/.profile`, behind the shell guard |
| `sessionVariables` | `sessionVariables`       | `~/.profile`, behind the shell guard |
| `initExtra`        | `initExtra`              | `~/.<name>rc`                 |
| `logoutExtra`      | `logoutExtra`            | `~/.<name>_logout`, run by an `EXIT` trap |
| `shellAliases`     | `shellAliases`           | `~/.<name>rc`                 |

sh.nix has no equivalent of `bashrcExtra`.

### `~/.profile`

`~/.profile` is read by every POSIX login shell. sh.nix puts the login code of a shell in a block behind the guard of that shell:

```sh
# ~/.profile: DO NOT EDIT -- this file has been generated automatically.

. "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"

if [ -n "${KSH_VERSION:-}" ]; then
export FOO=bar
fi
```

home-manager bash sets `home.file.".profile".source` directly. When `programs.bash.enable` is true, sh.nix does not write `~/.profile`. It adds the same block to `programs.bash.profileExtra`.

### `~/.<name>rc`

```sh
# Only read this file in ksh.
[ -n "${KSH_VERSION:-}" ] || return

if [ -n "$__HOME_KSHRC_SOURCED" ]; then return; fi
__HOME_KSHRC_SOURCED=1

case $- in
  *i*) ;;
  *) return ;;
esac

HISTSIZE=${toString cfg.histSize}
HISTFILE="${cfg.histFile}"

${aliasesStr}

${cfg.initExtra}
```

| Feature              | sh.nix `~/.<name>rc`   | home-manager `~/.bashrc` |
| -------------------- | ---------------------- | ------------------------ |
| Shell guard          | `[ -n "${KSH_VERSION:-}" ] \|\| return` | None |
| Once-per-shell guard | `__HOME_*RC_SOURCED`   | None                     |
| Interactive guard    | `case $- in *i*)`      | `[[ $- == *i* ]]`        |
| History              | `HISTSIZE`, `HISTFILE` | `HISTSIZE`, `HISTFILE`, `HISTFILESIZE`, `HISTCONTROL`, `HISTIGNORE` |
| Aliases              | `alias -- k=v`         | `alias -- k=v`           |
| Completion           | Not handled            | `enableCompletion`       |

### Scope

The unified `/etc/profile` generator is part of the NixOS and nix-darwin modules only. home-manager does not write `/etc` files, and it does not use `__ETC_PROFILE_DONE` or `__ETC_PROFILE_SOURCED`.
