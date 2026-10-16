# Implementing a Shell Module with sh.nix

This guide shows how to make NixOS, nix-darwin and home-manager modules for a shell with the sh.nix library.

## Select the approach

| Shell family  | Approach                      | Examples        |
| ------------- | ----------------------------- | --------------- |
| **POSIX**     | `mkPosixShellModule`          | ksh, mksh, yash |
| **Non-POSIX** | `mkShellModule` + `envBridge` | rc, fish, elvish |

Use `mkPosixShellModule` for a shell that does all of these:

- It reads `/etc/profile` and `~/.profile` as a login shell.
- It reads the file in `$ENV` as an interactive shell.
- It accepts POSIX `sh` syntax for `export`, `alias`, `case`, `[ ]` and `return` in a sourced file.

Do not use `mkPosixShellModule` for bash or zsh. NixOS, nix-darwin and home-manager have their own modules for these shells.

---

## Case 1: POSIX shell

```nix
# modules/mysh-base.nix
{ shnixLib }:

shnixLib.mkPosixShellModule {
  name = "mysh";           # sets the programs.mysh namespace
  etcRcPath = "myshrc";    # /etc/myshrc
  homeRcPath = ".myshrc";  # ~/.myshrc
}
```

The modules have the POSIX options in the [README](../README.md#options). They also do these steps:

- They write `/etc/myshrc` (NixOS, nix-darwin), `~/.myshrc` and `~/.profile` (home-manager).
- They register the shell in the `/etc/profile` guard chain.
- They bridge `environment.shellAliases` or `home.shellAliases` to `programs.mysh.shellAliases`.
- They bridge `environment.interactiveShellInit` to `programs.mysh.interactiveShellInit`.

### Guard

`/etc/profile` uses a guard to find the running shell. The rc files use the same guard and return immediately in other shells. Known guards are in `lib/posix/guards.nix`:

```nix
known = {
  ksh = ''[ -n "''${KSH_VERSION:-}" ]'';
  yash = ''[ -n "''${YASH_VERSION:-}" ]'';
  # ...
};
```

A name that is not in `known` gets `[ -n "${<NAME>_VERSION:-}" ]`. If the shell does not set this variable, add an entry to `known`. Without a correct guard, `/etc/profile` does not source the rc file of the shell.

### Shell-specific options

Put options for one shell in a separate module. On NixOS and nix-darwin, interactive code goes into `interactiveShellInit`. On home-manager, it goes into `initExtra`. Use the `options` argument to select the option:

```nix
# modules/mysh.nix
{ config, lib, options, ... }:

let
  cfg = config.programs.mysh;
  initOption = if options.programs.mysh ? initExtra then "initExtra" else "interactiveShellInit";
in
{
  options.programs.mysh.viMode = lib.mkEnableOption "vi line editing";

  config.programs.mysh.${initOption} = lib.mkIf (cfg.enable && cfg.viMode) (
    lib.mkAfter "set -o vi"
  );
}
```

### flake.nix

```nix
let
  myshBase = import ./modules/mysh-base.nix { shnixLib = self.lib; };
  myshExtra = import ./modules/mysh.nix;
in
{
  nixosModules.mysh = { ... }: { imports = [ myshBase.nixosModule myshExtra ]; };
  darwinModules.mysh = { ... }: { imports = [ myshBase.darwinModule myshExtra ]; };
  homeManagerModules.mysh = { ... }: { imports = [ myshBase.homeManagerModule myshExtra ]; };
}
```

Import the result of `mkPosixShellModule` from a separate file. If you call it inline in `flake.nix`, the module system cannot identify the modules, and an import of two modules gives "option already declared" errors.

---

## Case 2: Non-POSIX shell

A non-POSIX shell uses `mkShellModule`. The module author supplies the options, the platform config and the file generators. `modules/rc.nix` is the reference implementation.

### envBridge

`envBridge` returns the global environment configuration as plain data:

```nix
envBridge.nixos { inherit config; }
# => { shellAliases, shellInit, interactiveShellInit, setEnvironmentDone, path, variables }

envBridge.homeManager { inherit config; }
# => { shellAliases, sessionVariables, sessionVariablesDone, sessionSearchVariables }
```

Use `envBridge` for all global environment data. Do not read `config.environment.*` or `config.home.*` directly.

`shellInit` and `interactiveShellInit` contain POSIX shell code. Do not copy them into the configuration of a non-POSIX shell. Give the shell its own option for code in its own syntax.

A login shell needs the global environment that POSIX shells get from set-environment and `hm-session-vars.sh`:

- Set `path` and `variables` only if the variable named by `setEnvironmentDone` is not set, and then set it. Do the same for the home-manager data and `sessionVariablesDone`.
- Put the directories of each `sessionSearchVariables` entry before the current value of its variable.
- The values use the syntax of POSIX double-quoted strings, for example `$HOME/.nix-profile/bin`. Convert the references to the syntax of the shell. `modules/rc.nix` has a converter for rc.

`variables` can contain lists on NixOS and nix-darwin. nix-darwin always sets `XDG_CONFIG_DIRS` and `XDG_DATA_DIRS` as lists. A variable option must accept lists, or the module must convert them.

### Options

`mkShellModule` has three option hooks:

| Hook                 | Platforms           |
| -------------------- | ------------------- |
| `extraOptions`       | all                 |
| `extraSystemOptions` | NixOS, nix-darwin   |
| `extraHmOptions`     | home-manager        |

```nix
extraOptions = { lib, ... }: {
  shellAliases = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
  };
};

extraSystemOptions = { lib, ... }: {
  loginShellInit = lib.mkOption { type = lib.types.lines; default = ""; };
};

extraHmOptions = { lib, ... }: {
  initExtra = lib.mkOption { type = lib.types.lines; default = ""; };
};
```

### Config

Each config function receives `{ config, lib, pkgs, cfg }`. `cfg` is `config.programs.<name>`. Set bridged values with `lib.mkDefault`, so that a value in `programs.<name>` replaces them:

```nix
nixosConfig = { config, lib, cfg, ... }:
  let env = envBridge.nixos { inherit config; }; in
  {
    environment.shells = [ "${cfg.package}/bin/rc" ];
    programs.rc.shellAliases = lib.mkDefault env.shellAliases;
  };
```

`mkShellModule` installs `cfg.package` on all platforms.

### Files

`nixosFiles` and `darwinFiles` write files in `/etc`. `hmFiles` writes files in `$HOME`. The name of each entry is the path, relative to `/etc` or `$HOME`. Each `content` function receives the same arguments as a config function:

```nix
hmFiles = {
  ".rcrc" = {
    content = { lib, cfg, ... }: ''
      # ~/.rcrc: DO NOT EDIT -- this file has been generated automatically.
      ${cfg.initExtra}
    '';
  };
};
```

Quote values with the rules of the target shell. `lib.escapeShellArg` is correct only for POSIX shells. For rc, double each `'` in a single-quoted word.

Use `lib.optionalString` to omit sections that are empty.

### flake.nix

```nix
let
  rcModule = import ./modules/rc.nix { shnixLib = self.lib; };
in
{
  nixosModules.rc = rcModule.nixosModule;
  darwinModules.rc = rcModule.darwinModule;
  homeManagerModules.rc = rcModule.homeManagerModule;
}
```

---

## Tests

Add tests to `tests/default.nix`. The helpers `nixosCfg`, `darwinCfg` and `hmCfg` evaluate one module with the stubs:

```nix
"mysh darwin rc file bridges environment.shellAliases" = {
  expr = lib.hasInfix "alias -- ll='ls -l'" (
    darwinCfg self.darwinModules.mysh {
      programs.mysh.enable = true;
      environment.shellAliases.ll = "ls -l";
    }
  ).environment.etc.myshrc.text;
  expected = true;
};
```

If a module reads an option that `tests/stubs.nix` does not declare, add the option to the stubs. Use the same type as the upstream option.

Run the tests:

```bash
nix flake check
```

---

## Rules

1. Use `envBridge` for all global environment data.
2. Do not copy POSIX code into the configuration of a non-POSIX shell.
3. Set bridged values with `lib.mkDefault`.
4. Omit empty sections in generated files.
5. Keep `mkShellModule` free of shell syntax. Put POSIX logic in `lib/posix/`.

## References

- `lib/mk-shell-module.nix` — module assembler
- `lib/env-bridge.nix` — global environment extraction
- `lib/posix/` — POSIX helpers
- `modules/rc.nix` — non-POSIX reference implementation
- `modules/ksh-base.nix` and `modules/ksh93.nix` — POSIX reference implementation
