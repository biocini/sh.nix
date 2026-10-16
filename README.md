# sh.nix

sh.nix supplies [NixOS](https://nixos.org), [nix-darwin](https://github.com/nix-darwin/nix-darwin) and [home-manager](https://github.com/nix-community/home-manager) modules for shells other than bash, zsh and fish. It also supplies the library that builds these modules.

## Supported shells

| Shell     | Type      | Modules                                    |
| --------- | --------- | ------------------------------------------ |
| **ksh93** | POSIX     | `modules/ksh-base.nix` + `modules/ksh93.nix` |
| **rc**    | Non-POSIX | `modules/rc.nix`                           |

## Flake outputs

| Output                                | Contents                                                        |
| ------------------------------------- | --------------------------------------------------------------- |
| `packages.<system>.ksh`               | ksh93u+m, latest release                                        |
| `packages.<system>.ksh-nightly`       | ksh93u+m, latest commit on the `dev` branch                     |
| `packages.<system>.rc`                | rc (Byron Rakitzis), latest commit, with `/etc/rcrc` support    |
| `overlays.default`                    | Sets `ksh`, `ksh-nightly` and `rc` in nixpkgs to the packages above |
| `nixosModules.{ksh,rc}`               | NixOS modules                                                   |
| `darwinModules.{ksh,rc}`              | nix-darwin modules                                              |
| `homeManagerModules.{ksh,rc}`         | home-manager modules                                            |
| `lib`                                 | `mkShellModule`, `mkPosixShellModule`, `envBridge`              |

A module installs `programs.<name>.package`. The default value is `pkgs.<name>`. Apply `overlays.default` to use the packages of this flake.

The NixOS module and the nix-darwin module of one shell are mutually exclusive. They declare the same options, so the evaluation stops with an "option already declared" error if a configuration imports both. The home-manager module operates with either system module.

## Usage

```nix
{
  inputs.shnix.url = "github:biocini/sh.nix";
  inputs.shnix.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nix-darwin, home-manager, shnix, ... }: {
    darwinConfigurations.host = nix-darwin.lib.darwinSystem {
      modules = [
        { nixpkgs.overlays = [ shnix.overlays.default ]; }
        shnix.darwinModules.ksh
        { programs.ksh.enable = true; }
        home-manager.darwinModules.home-manager
        {
          home-manager.sharedModules = [ shnix.homeManagerModules.ksh ];
          home-manager.users.alice.programs.ksh = {
            enable = true;
            shellOptions = [ "vi" ];
          };
        }
      ];
    };
  };
}
```

## POSIX shells (ksh93)

### Generated files

| File            | Platform        | Contents                                                       |
| --------------- | --------------- | -------------------------------------------------------------- |
| `/etc/profile`  | NixOS, darwin   | Global environment, then a guard chain to each shell's rc file |
| `/etc/kshrc`    | NixOS, darwin   | History, prompt, aliases, `interactiveShellInit`               |
| `~/.kshrc`      | home-manager    | History, aliases, `initExtra`                                  |
| `~/.profile`    | home-manager    | `hm-session-vars.sh`, then the login code of each shell        |
| `~/.ksh_logout` | home-manager    | `logoutExtra`, if it is not empty                              |

### /etc/profile

All POSIX login shells read `/etc/profile`. The generated file does these steps in sequence:

1. It sources the system `set-environment` script, if a parent process did not source it.
2. On darwin, it runs `/usr/libexec/path_helper`. It adds to the end of `PATH` only the directories that are not already in `PATH`, so the Nix directories stay first.
3. It runs `environment.shellInit`, `environment.loginShellInit` and `/etc/profile.local`.
4. It runs a guard chain. bash is always the first entry and sources `/etc/bashrc`. Each other registered shell has a guard, for example `[ -n "${KSH_VERSION:-}" ]`. The matching entry exports `ENV=/etc/kshrc`, runs `programs.<name>.loginShellInit` and sources the rc file.

A shell name without a known guard uses `[ -n "${<NAME>_VERSION:-}" ]`. The known guards are in `lib/posix/guards.nix`.

On darwin, the module declares the SHA-256 of the stock macOS `/etc/profile`. When macOS restores the stock file, nix-darwin activation moves it to `/etc/profile.before-nix-darwin` and continues.

### rc files

A child process inherits `ENV=/etc/kshrc`. Other POSIX shells, for example dash, read `$ENV` when they start in interactive mode. Thus `/etc/kshrc` and `~/.kshrc` start with the ksh guard and return immediately in other shells.

The default prompt is `user@host:directory$ `. The shell expands `$USER` and `$PWD` each time it shows the prompt.

### ~/.profile

Each POSIX login shell reads `~/.profile`. sh.nix puts the `sessionVariables` and `profileExtra` of a shell in a block behind the guard of that shell.

When home-manager `programs.bash.enable` is true, home-manager bash writes `~/.profile`. sh.nix then adds its block to `programs.bash.profileExtra` and does not write `~/.profile`.

### Options

All platforms:

| Option         | Type          | Default                   | Description                     |
| -------------- | ------------- | ------------------------- | ------------------------------- |
| `enable`       | `bool`        | `false`                   | Install the shell and write its files |
| `package`      | `package`     | `pkgs.<name>`             | The shell package               |
| `histFile`     | `str`         | `"$HOME/.<name>_history"` | History file. The shell expands parameters in it. |
| `histSize`     | `int`         | `2000` (ksh: `10000`)     | History lines in memory         |
| `shellAliases` | `attrsOf str` | global aliases            | Aliases for interactive shells  |

NixOS and nix-darwin:

| Option                 | Type    | Default                            | Description                               |
| ---------------------- | ------- | ---------------------------------- | ----------------------------------------- |
| `loginShellInit`       | `lines` | `""`                               | Code in `/etc/profile` for this shell only |
| `interactiveShellInit` | `lines` | `environment.interactiveShellInit` | Code in the system rc file                |

home-manager:

| Option             | Type                           | Default | Description                                    |
| ------------------ | ------------------------------ | ------- | ---------------------------------------------- |
| `initExtra`        | `lines`                        | `""`    | Code in the user rc file                       |
| `profileExtra`     | `lines`                        | `""`    | Login code in `~/.profile` for this shell only |
| `sessionVariables` | `attrsOf (str \| int \| path)` | `{}`    | Variables that `~/.profile` exports for this shell only |
| `logoutExtra`      | `lines`                        | `""`    | Code that runs when the shell exits            |

ksh only, all platforms:

| Option         | Type          | Default | Description                                      |
| -------------- | ------------- | ------- | ------------------------------------------------ |
| `shellOptions` | `listOf str`  | `[]`    | Options for `set -o`                             |
| `functionsDir` | `nullOr str`  | `null`  | Directory that is added to the start of `FPATH`  |

These ksh options go into `interactiveShellInit` on NixOS and nix-darwin, and into `initExtra` on home-manager.

The default of `shellAliases` is `environment.shellAliases` on NixOS and nix-darwin, and `home.shellAliases` on home-manager. A value for `programs.<name>.shellAliases` replaces this default.

## rc

### Generated files

| File       | Platform      | Contents                                                       |
| ---------- | ------------- | -------------------------------------------------------------- |
| `/etc/rcrc` | NixOS, darwin | Global environment, `sessionVariables`, history, prompt, functions, `loginShellInit` |
| `~/.rcrc`  | home-manager  | home-manager session environment, `sessionVariables`, history, prompt, functions, `initExtra` |

The rc package of this flake reads `/etc/rcrc` and then `~/.rcrc` in login shells. If `$RCRC` is set, it reads only that file. The nixpkgs rc package does not read `/etc/rcrc`, so use `overlays.default` with the system modules.

### Environment

The rc files contain rc code only. rc does not run POSIX code.

`/etc/rcrc` sets the variables that set-environment exports for POSIX shells:

- `path`: on NixOS, `~/.local/bin` (`environment.localBinInPath`), `~/bin` (`environment.homeBinInPath`), the wrapper directory, and the `PATH` entries of `environment.profileRelativeEnvVars` for each profile. On nix-darwin, `environment.systemPath`.
- `environment.variables` and, on NixOS, the other `environment.profileRelativeEnvVars`.
- `NIX_PROFILES` and `NIX_USER_PROFILE_DIR`, from `environment.profiles`.

These assignments run only if the set-environment marker variable (`__NIXOS_SET_ENVIRONMENT_DONE` or `__NIX_DARWIN_SET_ENVIRONMENT_DONE`) is not set. Then they set it. A login shell that inherits the environment keeps it. On nix-darwin, `/etc/rcrc` then adds the directories from `/etc/paths` and `/etc/paths.d` that are not in `$path` to the end of `$path`.

`~/.rcrc` sets `home.sessionVariables`, puts `home.sessionPath` before `$path`, and puts each `home.sessionSearchVariables` entry before its variable. These assignments run only if `__HM_SESS_VARS_SOURCED` is not set.

`environment.extraInit`, `environment.shellInit`, `environment.loginShellInit`, `environment.interactiveShellInit` and `home.sessionVariablesExtra` contain POSIX code. The rc files do not contain this code. Write rc code with the same effect in `loginShellInit` or `initExtra`, for example:

```nix
programs.rc.loginShellInit = ''
  SSH_AUTH_SOCK = `{gpgconf --list-dirs agent-ssh-socket}
'';
```

### Options

| Option             | Platforms     | Type                                     | Default         | Description |
| ------------------ | ------------- | ---------------------------------------- | --------------- | ----------- |
| `historyFile`      | all           | `str`                                    | `".rc_history"` | A relative path is relative to `$home` |
| `prompt`           | all           | `listOf str`                             | `[ "; " "" ]`   | Primary and continuation prompt |
| `shellAliases`     | all           | `attrsOf str`                            | global aliases  | `ll = "ls -l"` gives `fn ll { ls -l $* }`. A value must not contain `}`. |
| `sessionVariables` | all           | `attrsOf (str \| int \| path \| listOf str)` | `{}`        | Set in each login shell, after the global environment |
| `loginShellInit`   | NixOS, darwin | `lines`                                  | `""`            | rc code in `/etc/rcrc` |
| `initExtra`        | home-manager  | `lines`                                  | `""`            | rc code in `~/.rcrc` |

Variable values use the rules of a POSIX double-quoted string. They expand when rc reads the file:

- sh.nix joins a list with `:`.
- `$NAME` and `${NAME}` give the value of `NAME`.
- `${NAME:-word}` gives `word` if `NAME` is unset or empty. `${NAME-word}` gives `word` if `NAME` is unset.
- `\$`, `` \` ``, `\"` and `\\` give the character after the backslash.
- All other text is literal. Command substitution (`$(...)`) is not supported.

## Library

### `lib.mkPosixShellModule { name, etcRcPath ?, homeRcPath ? }`

Returns `{ nixosModule, darwinModule, homeManagerModule }` for a POSIX shell. The modules have the options in [POSIX shells](#options), and they register the shell in the `/etc/profile` guard chain.

| Parameter    | Default             | Description                                  |
| ------------ | ------------------- | -------------------------------------------- |
| `name`       | —                   | Shell name. It sets the `programs.<name>` namespace. |
| `etcRcPath`  | `name + "rc"`       | System rc file name, relative to `/etc`      |
| `homeRcPath` | `"." + name + "rc"` | User rc file name, relative to `$HOME`       |

```nix
shnix.lib.mkPosixShellModule {
  name = "yash";
  etcRcPath = "yashrc";
  homeRcPath = ".yashrc";
}
```

### `lib.mkShellModule { name, ... }`

Returns `{ nixosModule, darwinModule, homeManagerModule }` for any shell. It does not know shell syntax.

| Parameter            | Default     | Description                                          |
| -------------------- | ----------- | ---------------------------------------------------- |
| `name`               | —           | Shell name                                           |
| `package`            | `null`      | Default package. `null` gives `pkgs.<name>`.         |
| `extraOptions`       | `(_: { })`  | Options on all platforms                             |
| `extraSystemOptions` | `(_: { })`  | Options on NixOS and nix-darwin                      |
| `extraHmOptions`     | `(_: { })`  | Options on home-manager                              |
| `nixosConfig`        | `(_: { })`  | Config for NixOS                                     |
| `darwinConfig`       | `(_: { })`  | Config for nix-darwin                                |
| `hmConfig`           | `(_: { })`  | Config for home-manager                              |
| `nixosFiles`         | `{ }`       | Files in `/etc` on NixOS                             |
| `darwinFiles`        | `{ }`       | Files in `/etc` on nix-darwin                        |
| `hmFiles`            | `{ }`       | Files in `$HOME`                                     |

Each option and config function receives `{ config, lib, pkgs, cfg }`, where `cfg` is `config.programs.<name>`. Each file is `{ content = { config, lib, pkgs, cfg }: "<text>"; }`.

### `lib.envBridge`

Extracts the global environment configuration as plain attribute sets:

```nix
envBridge.nixos { inherit config; }
# => { shellAliases, shellInit, interactiveShellInit, setEnvironmentDone, path, variables }

envBridge.darwin { inherit config; }
# => { shellAliases, shellInit, interactiveShellInit, setEnvironmentDone, path, variables }

envBridge.homeManager { inherit config; }
# => { shellAliases, sessionVariables, sessionVariablesDone, sessionSearchVariables }
```

- `shellAliases` does not contain null entries, and its values are strings.
- `path` is the `PATH` that set-environment exports, as a list of directories.
- `variables` contains the other variables that set-environment exports, including the variables that `environment.extraInit` exports from `environment.profiles`.
- `setEnvironmentDone` and `sessionVariablesDone` are the names of the marker variables of set-environment and `hm-session-vars.sh`.
- `sessionSearchVariables` maps each variable to the directories to put before its value. `PATH` holds `home.sessionPath`.
- Values can contain `$HOME`, `$USER` and other POSIX references.

See [`docs/implementing-a-shell.md`](docs/implementing-a-shell.md) for the full guide.

## Project structure

```
.
├── docs/
│   ├── implementing-a-shell.md    # Guide for shell module authors
│   ├── existing-env-gen.md        # Upstream bash/zsh init file generation
│   ├── nixos-bash-profile.md      # Upstream NixOS bash reference
│   ├── nix-darwin-bash-profile.md # Upstream nix-darwin bash reference
│   └── home-manager-bash-profile.md # Upstream home-manager bash reference
├── lib/
│   ├── default.nix                # Public library
│   ├── env-bridge.nix             # Global environment extraction
│   ├── mk-shell-module.nix        # Module assembler
│   ├── mk-posix-shell.nix         # POSIX shell wrapper
│   └── posix/
│       ├── options.nix            # POSIX options
│       ├── configs.nix            # Platform config
│       ├── files.nix              # rc file generators
│       ├── guards.nix             # Shell guard expressions
│       ├── registry.nix           # Registry of POSIX shells
│       ├── dispatch.nix           # /etc/profile guard chain
│       ├── profile-nixos.nix      # /etc/profile for NixOS
│       └── profile-darwin.nix     # /etc/profile for nix-darwin
├── modules/
│   ├── ksh-base.nix               # mkPosixShellModule for ksh
│   ├── ksh93.nix                  # ksh options
│   └── rc.nix                     # rc module
├── pkgs/
│   ├── ksh93/                     # generic.nix, stable.nix, nightly.nix
│   └── rc/                        # rc package and /etc/rcrc patch
├── tests/
│   ├── default.nix                # nix-unit tests
│   └── stubs.nix                  # Minimal NixOS, nix-darwin and home-manager options
└── flake.nix
```

## Testing

```bash
nix flake check
```

The tests are in `tests/default.nix`. nix-unit finds each attribute whose name starts with `test`. The tests use the stub modules in `tests/stubs.nix`, not the full NixOS, nix-darwin or home-manager modules.

GitHub workflows update `pkgs/ksh93` and `pkgs/rc` each day. A workflow builds the package and runs `nix flake check` before it pushes the update. The `check` workflow builds all packages and runs `nix flake check` on Linux (x86_64, aarch64) and macOS for each push to master and each pull request.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
