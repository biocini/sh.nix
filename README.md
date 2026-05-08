# sh.nix

First-class [NixOS](https://nixos.org) / [nix-darwin](https://github.com/LnL7/nix-darwin) / [home-manager](https://github.com/nix-community/home-manager) support for shells outside the big three (bash, zsh, fish).

## Problem

NixOS and home-manager provide rich, well-integrated `programs.bash`, `programs.zsh`, and `programs.fish` modules that handle:

- Writing system-wide and per-user initialization files
- Sourcing the POSIX `set-environment` / `hm-session-vars.sh` aggregators
- Propagating `environment.shellAliases` / `home.shellAliases`
- Registering the shell in `environment.shells`

Most other shells have **no equivalent modules**. Users must manually wire `home.file`, `environment.etc`, and session variables. Even fish's support is hacky (POSIX-to-fish translation via babelfish/foreign-env). Shells like **rc**, **elvish**, and **xonsh** have no NixOS or home-manager support at all.

## Solution

`sh.nix` provides composable building blocks for shell module authors:

- **`lib.mkPosixShellModule`** — generates full modules for POSIX-compatible shells
- **`lib.mkShellModule`** — the universal assembler for any shell
- **`lib.envBridge`** — pure data extraction from global environment config
- **`lib/posix/`** — reusable POSIX-family helpers (options, configs, file generators)

This architecture scales from POSIX shells (ksh, yash, dash) to entirely non-POSIX shells (rc, fish, xonsh, elvish) without leaky abstractions.

## Supported shells

| Shell     | Type      | Status          |
| --------- | --------- | --------------- |
| **ksh93** | POSIX     | Fully supported |
| **rc**    | Non-POSIX | Fully supported |

## Quick start: POSIX shell

For POSIX-compatible shells that understand `/etc/profile`, `$ENV`, `export`, and `alias`:

```nix
# modules/mysh.nix
{ shnixLib }:

shnixLib.mkPosixShellModule {
  name = "yash";              # sets programs.yash namespace
  etcRcPath = "yashrc";       # /etc/yashrc
  homeRcPath = ".yashrc";     # ~/.yashrc
}
```

This gives you `programs.yash.enable`, `programs.yash.shellAliases`, `programs.yash.initExtra`, and automatic bridges from `environment.shellAliases` (NixOS/darwin) and `home.shellAliases` (HM). It generates `/etc/profile`, `/etc/yashrc`, `~/.profile`, and `~/.yashrc`.

## Quick start: Non-POSIX shell

For shells with their own config syntax and semantics:

```nix
# modules/rc.nix
{ shnixLib }:

let
  envBridge = import ../lib/env-bridge.nix;
in

shnixLib.mkShellModule {
  name = "rc";

  extraOptions = { lib, ... }: {
    historyFile = lib.mkOption { type = lib.types.str; default = "$home/.rc_history"; };
    prompt = lib.mkOption { type = lib.types.listOf lib.types.str; default = [ "; " "" ]; };
    shellAliases = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = { }; };
    sessionVariables = lib.mkOption { type = lib.types.attrsOf (lib.types.oneOf [ lib.types.str lib.types.int lib.types.path ]); default = { }; };
    initExtra = lib.mkOption { type = lib.types.lines; default = ""; };
  };

  nixosConfig = { config, lib, ... }:
    let env = envBridge.nixos { inherit config; }; in
    {
      programs.rc = {
        shellAliases = lib.mkDefault env.shellAliases;
        initExtra = lib.mkDefault env.interactiveShellInit;
        sessionVariables = lib.mkDefault env.variables;
      };
    };

  nixosFiles = {
    "rcrc" = {
      content = { lib, cfg, ... }:
        ''
          # /etc/rcrc: DO NOT EDIT -- this file has been generated automatically.
          history=${lib.escapeShellArg cfg.historyFile}
          prompt=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.prompt})
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "fn ${k} { ${v} }") cfg.shellAliases)}
          ${cfg.initExtra}
        '';
    };
  };
}
```

The full working implementation is in [`modules/rc.nix`](modules/rc.nix). See [`docs/implementing-a-shell.md`](docs/implementing-a-shell.md) for a complete guide.

## The `envBridge` abstraction

`lib.envBridge` extracts global environment config into plain attrsets. It is the **only** truly universal component across all shell families:

```nix
let env = envBridge.nixos { inherit config; }; in
# env.shellAliases      — from config.environment.shellAliases
# env.variables         — from config.environment.variables
# env.shellInit         — from config.environment.shellInit
# env.loginShellInit    — from config.environment.loginShellInit
# env.interactiveShellInit — from config.environment.interactiveShellInit

let env = envBridge.homeManager { inherit config; }; in
# env.shellAliases      — from config.home.shellAliases
# env.sessionVariables  — from config.home.sessionVariables
```

Shell modules map these values to their shell-specific options using `lib.mkDefault`, so users can still override at `programs.<name>.shellAliases` if needed.

## Public API

### `lib.mkPosixShellModule { name, etcRcPath ?, homeRcPath ? }`

Generates `{ nixosModule, darwinModule, homeManagerModule }` for POSIX shells.

| Parameter    | Default             | Description                                  |
| ------------ | ------------------- | -------------------------------------------- |
| `name`       | —                   | Shell name, sets `programs.<name>` namespace |
| `etcRcPath`  | `name + "rc"`       | System-wide rc filename (no leading `/etc/`) |
| `homeRcPath` | `"." + name + "rc"` | User rc filename                             |

User-facing options under `programs.<name>`:

| Option         | Type          | Default                   | Description                              |
| -------------- | ------------- | ------------------------- | ---------------------------------------- |
| `enable`       | `bool`        | `false`                   | Enable the shell and generate init files |
| `package`      | `package`     | `pkgs.<name>`             | The shell package                        |
| `histFile`     | `str`         | `"$HOME/.<name>_history"` | History file path                        |
| `histSize`     | `int`         | `2000`                    | History lines in memory                  |
| `shellAliases` | `attrsOf str` | `{}`                      | Interactive shell aliases                |
| `initExtra`    | `lines`       | `""`                      | Extra interactive init                   |

Home-manager-specific options:

| Option             | Type                           | Default | Description                                   |
| ------------------ | ------------------------------ | ------- | --------------------------------------------- |
| `profileExtra`     | `lines`                        | `""`    | Extra login init                              |
| `sessionVariables` | `attrsOf (str \| int \| path)` | `{}`    | Login env vars                                |
| `logoutExtra`      | `lines`                        | `""`    | Logout commands (triggers logout file + trap) |

Internal options (used by the env bridge):

| Option                 | Assembled From                                       |
| ---------------------- | ---------------------------------------------------- |
| `shellInit`            | `setEnvironment` bootstrap + `environment.shellInit` |
| `loginShellInit`       | `environment.loginShellInit`                         |
| `interactiveShellInit` | `environment.interactiveShellInit`                   |

### `lib.mkShellModule { name, ... }`

The universal assembler. Accepts shell-specific options, config bridges, and file generators. Returns `{ nixosModule, darwinModule, homeManagerModule }`.

Parameters:

| Parameter        | Default | Description                                  |
| ---------------- | ------- | -------------------------------------------- |
| `name`           | —       | Shell name                                   |
| `package`        | `null`  | Default package (or `pkgs.<name>`)           |
| `extraOptions`   | `{}`    | Options available on all platforms           |
| `extraHmOptions` | `{}`    | Options available only in home-manager       |
| `defaults`       | `{}`    | Default values for `programs.<name>` options |
| `nixosConfig`    | `{}`    | Config bridge for NixOS                      |
| `darwinConfig`   | `{}`    | Config bridge for nix-darwin                 |
| `hmConfig`       | `{}`    | Config bridge for home-manager               |
| `nixosFiles`     | `{}`    | File generators for `/etc/*`                 |
| `darwinFiles`    | `{}`    | File generators for `/etc/*` on darwin       |
| `hmFiles`        | `{}`    | File generators for `~/.*`                   |

### `lib.envBridge`

Pure data extraction from global environment configuration.

```nix
envBridge.nixos { inherit config; }
# => { shellAliases, shellInit, loginShellInit, interactiveShellInit, variables }

envBridge.darwin { inherit config; }
# => { shellAliases, shellInit, loginShellInit, interactiveShellInit, variables }

envBridge.homeManager { inherit config; }
# => { shellAliases, sessionVariables }
```

### `lib.shell` — POSIX script helpers

```nix
sh = shnix.lib.shell { inherit lib; };

sh.export "FOO" "bar"
# => export FOO="bar"

sh.exportAll { FOO = "bar"; BAZ = 42; }
# => export FOO="bar"
#    export BAZ="42"

sh.mkAliases { ll = "ls -l"; g = null; }
# => alias -- ll='ls -l'
#    (null values filtered out)

sh.prependToVar ":" "PATH" [ "$HOME/bin" "$HOME/.local/bin" ]
# => $HOME/bin:$HOME/.local/bin${PATH:+:}$PATH
```

## Project structure

```
.
├── docs/
│   ├── implementation.md          # mkPosixShellModule internal spec
│   ├── implementing-a-shell.md    # Guide for downstream shell implementers
│   └── ...
├── lib/
│   ├── default.nix                # Public API exports
│   ├── env-bridge.nix             # Pure env config extraction
│   ├── mk-shell-module.nix        # Universal module assembler
│   ├── mk-posix-shell.nix         # POSIX shell wrapper
│   ├── shell-script.nix           # POSIX script generation helpers
│   └── posix/                     # POSIX-family decomposed helpers
│       ├── options.nix
│       ├── configs.nix
│       └── files.nix
├── modules/
│   ├── ksh-base.nix               # mkPosixShellModule for ksh
│   ├── ksh93.nix                  # ksh93-specific options layer
│   └── rc.nix                     # Non-POSIX rc module (reference impl)
├── pkgs/
│   ├── ksh93/                     # ksh93 packages (stable + nightly)
│   └── rc/                        # rc package (nightly + nixos-rcrc.patch)
├── tests/
│   ├── default.nix                # 28 nix-unit test cases
│   └── stubs.nix                  # Minimal NixOS/HM stubs
├── flake.nix
└── AGENTS.md
```

## Testing

```bash
nix flake check
```

Tests live in `tests/default.nix` and are discovered by `nix-unit` (attribute names must start with `test`). They use stub modules (`tests/stubs.nix`) to avoid importing full nixpkgs. Tests cover:

- Library API shape (`mkPosixShellModule`, `mkShellModule` return values)
- File generation for all three platforms
- Environment bridge flows (aliases, variables, init scripts)
- Module conflict assertions
- Empty-config drift avoidance

## Writing a new shell module

See [`docs/implementing-a-shell.md`](docs/implementing-a-shell.md) for a complete guide covering POSIX shells, non-POSIX shells, testing, and conceptual examples for fish, xonsh, and elvish.

## License

MIT
