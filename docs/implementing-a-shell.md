# Implementing a Shell Module with sh.nix

This guide shows how to add first-class NixOS / nix-darwin / home-manager support for a new shell using sh.nix's composable abstractions.

## The Decision Tree

The first question is: **Is your shell POSIX-compatible?**

| Shell Family  | Approach                      | Examples                   |
| ------------- | ----------------------------- | -------------------------- |
| **POSIX**     | `mkPosixShellModule`          | ksh, bash, yash, dash, zsh |
| **Non-POSIX** | `mkShellModule` + `envBridge` | rc, fish, xonsh, elvish    |

POSIX shells share a common model: `/etc/profile` for login shells, `$ENV` pointing to an rc file for interactive shells, `export` for env vars, `alias` for aliases. If your shell fits this model, use `mkPosixShellModule`.

Non-POSIX shells have their own config syntax, file locations, and semantics. They compose the lower-level building blocks directly.

---

## Case 1: POSIX Shell (the easy way)

If your shell understands POSIX `sh` syntax and uses the standard profile/rc model:

```nix
# modules/mysh.nix
{ shnixLib }:

shnixLib.mkPosixShellModule {
  name = "mysh";           # sets programs.mysh namespace
  etcRcPath = "myshrc";    # /etc/myshrc
  homeRcPath = ".myshrc";  # ~/.myshrc
}
```

That's it. You get:

- `programs.mysh.enable`, `programs.mysh.package`
- `programs.mysh.shellAliases`, `programs.mysh.initExtra`
- `programs.mysh.histFile`, `programs.mysh.histSize`
- Automatic bridge from `environment.shellAliases` (NixOS/darwin) and `home.shellAliases` (HM)
- `/etc/profile`, `/etc/myshrc`, `~/.profile`, `~/.myshrc` generation

### Adding shell-specific options

If your shell has unique options beyond the POSIX baseline, layer them on top:

```nix
# modules/mysh-extra.nix
{ config, lib, ... }:

let cfg = config.programs.mysh; in
{
  options.programs.mysh = {
    viMode = lib.mkEnableOption "vi line editing";
    customOption = lib.mkOption { type = lib.types.str; default = ""; };
  };

  config.programs.mysh = lib.mkIf cfg.enable {
    initExtra = lib.mkAfter ''
      ${lib.optionalString cfg.viMode "set -o vi"}
      ${lib.optionalString (cfg.customOption != "") "echo ${lib.escapeShellArg cfg.customOption}"}
    '';
  };
}
```

Then compose in `flake.nix`:

```nix
let
  myshBase = import ./modules/mysh.nix { inherit shnixLib; };
  myshExtra = import ./modules/mysh-extra.nix;
in
{
  nixosModules.mysh = { ... }: { imports = [ myshBase.nixosModule myshExtra ]; };
  darwinModules.mysh = { ... }: { imports = [ myshBase.darwinModule myshExtra ]; };
  homeManagerModules.mysh = { ... }: { imports = [ myshBase.homeManagerModule myshExtra ]; };
}
```

---

## Case 2: Non-POSIX Shell (the composable way)

Non-POSIX shells use `mkShellModule` directly and compose it with `envBridge` for environment integration. You define your own options, your own file generators, and your own config bridges.

### Step 1: Import envBridge

```nix
let
  envBridge = import ../lib/env-bridge.nix;
in
```

`envBridge` extracts global environment config into plain attrsets:

```nix
# NixOS / nix-darwin
envBridge.nixos { inherit config; }
# => { shellAliases = { ... }; variables = { ... }; shellInit = "..."; loginShellInit = "..."; interactiveShellInit = "..."; }

# Home-manager
envBridge.homeManager { inherit config; }
# => { shellAliases = { ... }; sessionVariables = { ... }; }
```

### Step 2: Declare your options

```nix
extraOptions = { lib, ... }: {
  # rc-specific options
  historyFile = lib.mkOption {
    type = lib.types.str;
    default = "$home/.rc_history";
    description = "Path to the history file.";
  };

  prompt = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ "; " "" ];
    description = "The two rc prompts as a list.";
  };

  # Common options that most shells want
  shellAliases = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = "Functions to define (rc uses fn, not alias).";
  };

  sessionVariables = lib.mkOption {
    type = lib.types.attrsOf (lib.types.oneOf [ lib.types.str lib.types.int lib.types.path ]);
    default = { };
    description = "Environment variables to set.";
  };

  initExtra = lib.mkOption {
    type = lib.types.lines;
    default = "";
    description = "Additional commands for shell init.";
  };
};
```

### Step 3: Wire the environment bridge

Map global environment config to your shell-specific options:

```nix
nixosConfig = { config, lib, ... }:
  let env = envBridge.nixos { inherit config; }; in
  {
    programs.rc = {
      shellAliases = lib.mkDefault env.shellAliases;
      initExtra = lib.mkDefault env.interactiveShellInit;
      sessionVariables = lib.mkDefault env.variables;
    };
  };

darwinConfig = { config, lib, ... }:
  let env = envBridge.darwin { inherit config; }; in
  {
    programs.rc = {
      shellAliases = lib.mkDefault env.shellAliases;
      initExtra = lib.mkDefault env.interactiveShellInit;
      sessionVariables = lib.mkDefault env.variables;
    };
  };

hmConfig = { config, lib, ... }:
  let env = envBridge.homeManager { inherit config; }; in
  {
    programs.rc = {
      shellAliases = lib.mkDefault env.shellAliases;
      sessionVariables = lib.mkDefault env.sessionVariables;
    };
  };
```

### Step 4: Write file generators

File generators are functions that receive `{ lib, cfg, config, ... }` and return a string of shell-native config:

```nix
nixosFiles = {
  "rcrc" = {
    content = { lib, cfg, ... }:
      let
        sessionVarsStr = lib.optionalString (cfg.sessionVariables != { }) (
          "# Session variables.\n"
          + lib.concatStringsSep "\n" (
            lib.mapAttrsToList (k: v: "${k} = ${lib.escapeShellArg (toString v)}") cfg.sessionVariables
          )
          + "\n"
        );
      in
      ''
        # /etc/rcrc: DO NOT EDIT -- this file has been generated automatically.

        ${sessionVarsStr}# History file.
        history=${lib.escapeShellArg cfg.historyFile}

        # Prompt.
        prompt=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.prompt})

        # Functions (rc's equivalent of aliases).
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "fn ${k} { ${v} }") cfg.shellAliases)}

        ${cfg.initExtra}
      '';
  };
};
```

Key patterns:

- Use `lib.escapeShellArg` to safely quote values
- Use `lib.optionalString` to omit sections when empty (avoids drift for users who don't set those options)
- Use `lib.concatMapStringsSep` for list rendering
- Use `lib.concatStringsSep "\n"` + `lib.mapAttrsToList` for attrset rendering

### Step 5: Assemble the module

```nix
{ shnixLib }:

let
  envBridge = import ../lib/env-bridge.nix;
in

shnixLib.mkShellModule {
  name = "rc";

  extraOptions = { lib, ... }: { /* ... your options ... */ };

  nixosConfig = { config, lib, ... }: { /* ... bridge ... */ };
  darwinConfig = { config, lib, ... }: { /* ... bridge ... */ };
  hmConfig = { config, lib, ... }: { /* ... bridge ... */ };

  nixosFiles = { /* ... file generators ... */ };
  darwinFiles = { /* ... file generators ... */ };
  hmFiles = { /* ... file generators ... */ };
}
```

Returns `{ nixosModule, darwinModule, homeManagerModule }`.

---

## Full Example: rc Shell

Here's the complete rc module as a reference implementation:

```nix
# modules/rc.nix
{ shnixLib }:

let
  envBridge = import ../lib/env-bridge.nix;
in

shnixLib.mkShellModule {
  name = "rc";

  extraOptions = { lib, ... }: {
    historyFile = lib.mkOption {
      type = lib.types.str;
      default = "$home/.rc_history";
      description = "Path to the rc history file.";
    };

    prompt = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "; " "" ];
      description = "The two rc prompts as a list.";
    };

    shellAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Functions to define in rc (rc uses fn, not alias).";
    };

    sessionVariables = lib.mkOption {
      type = lib.types.attrsOf (lib.types.oneOf [ lib.types.str lib.types.int lib.types.path ]);
      default = { };
      description = "Environment variables to set in rc.";
    };

    initExtra = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional rc commands for shell init.";
    };
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

  darwinConfig = { config, lib, ... }:
    let env = envBridge.darwin { inherit config; }; in
    {
      programs.rc = {
        shellAliases = lib.mkDefault env.shellAliases;
        initExtra = lib.mkDefault env.interactiveShellInit;
        sessionVariables = lib.mkDefault env.variables;
      };
    };

  hmConfig = { config, lib, ... }:
    let env = envBridge.homeManager { inherit config; }; in
    {
      programs.rc = {
        shellAliases = lib.mkDefault env.shellAliases;
        sessionVariables = lib.mkDefault env.sessionVariables;
      };
    };

  nixosFiles = {
    "rcrc" = {
      content = { lib, cfg, ... }:
        let
          sessionVarsStr = lib.optionalString (cfg.sessionVariables != { }) (
            "# Session variables.\n"
            + lib.concatStringsSep "\n" (
              lib.mapAttrsToList (k: v: "${k} = ${lib.escapeShellArg (toString v)}") cfg.sessionVariables
            )
            + "\n"
          );
        in
        ''
          # /etc/rcrc: DO NOT EDIT -- this file has been generated automatically.

          ${sessionVarsStr}# History file.
          history=${lib.escapeShellArg cfg.historyFile}

          # Prompt.
          prompt=(${lib.concatMapStringsSep " " lib.escapeShellArg cfg.prompt})

          # Functions (rc's equivalent of aliases).
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "fn ${k} { ${v} }") cfg.shellAliases)}

          ${cfg.initExtra}
        '';
    };
  };

  # darwinFiles and hmFiles follow the same pattern...
}
```

---

## Testing Your Module

Add tests in `tests/default.nix`:

```nix
"mysh nixos module produces /etc/myshrc" = {
  expr =
    let
      cfg = (evalNixos [
        stubs.nixos
        self.nixosModules.mysh
        { programs.mysh.enable = true; }
      ]).config;
    in
    builtins.hasAttr "myshrc" cfg.environment.etc;
  expected = true;
};

"mysh bridges environment.shellAliases" = {
  expr =
    let
      cfg = (evalNixos [
        stubs.nixos
        self.nixosModules.mysh
        {
          programs.mysh.enable = true;
          environment.shellAliases.ll = "ls -l";
        }
      ]).config;
    in
    lib.hasInfix "alias ll='ls -l'" cfg.environment.etc.myshrc.text;
  expected = true;
};
```

If your shell uses HM stubs, add `home.sessionVariables` to `tests/stubs.nix` first.

Run tests with:

```bash
nix flake check
```

---

## Exposing in flake.nix

```nix
{
  outputs = { self, nixpkgs, ... }:
    let
      rcModule = import ./modules/rc.nix { shnixLib = self.lib; };
    in
    {
      nixosModules.rc = rcModule.nixosModule;
      darwinModules.rc = rcModule.darwinModule;
      homeManagerModules.rc = rcModule.homeManagerModule;
    };
}
```

---

## Conceptual Examples: Future Shells

### Fish (native — no POSIX translation)

```nix
shnixLib.mkShellModule {
  name = "fish";

  extraOptions = { lib, ... }: {
    shellAbbrs = lib.mkOption { type = lib.types.attrsOf lib.types.str; default = { }; };
    # ... other fish-specific options ...
  };

  nixosConfig = { config, lib, ... }:
    let env = envBridge.nixos { inherit config; }; in
    {
      programs.fish = {
        shellAliases = lib.mkDefault env.shellAliases;
        interactiveShellInit = lib.mkDefault env.interactiveShellInit;
      };
    };

  nixosFiles = {
    "fish/config.fish" = {
      content = { lib, cfg, ... }:
        ''
          # /etc/fish/config.fish
          if test -z "$__NIXOS_SET_ENVIRONMENT_DONE"
            source ${config.system.build.setEnvironment}
          end
          ${cfg.interactiveShellInit}
        '';
    };
  };
}
```

### Elvish

```nix
shnixLib.mkShellModule {
  name = "elvish";

  extraOptions = { lib, ... }: {
    # elvish has no alias concept — everything is a function
    shellAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Functions to define in elvish.";
    };
  };

  hmConfig = { config, lib, ... }:
    let env = envBridge.homeManager { inherit config; }; in
    {
      programs.elvish = {
        shellAliases = lib.mkDefault env.shellAliases;
      };
    };

  hmFiles = {
    "elvish/rc.elv" = {
      content = { lib, cfg, ... }:
        ''
          # ~/.config/elvish/rc.elv
          ${lib.concatStringsSep "\n"
            (lib.mapAttrsToList (k: v: "fn ${k} { e:${v} }") cfg.shellAliases)}
        '';
    };
  };
}
```

---

## Key Design Principles

1. **Use `envBridge`** for all global environment integration. Don't reach into `config.environment.*` directly.
2. **Use `lib.mkDefault`** when bridging so users can override at the `programs.<name>` level.
3. **Omit empty sections** in file generators with `lib.optionalString` to avoid drift for users who don't set those options.
4. **Keep `mkShellModule` minimal** — it's just an assembler. Don't add shell-specific logic to it.
5. **Keep POSIX helpers reusable** — `mkPosixShellModule` is for the POSIX family. Non-POSIX shells compose `mkShellModule` + `envBridge` directly.

---

## References

- `lib/mk-shell-module.nix` — The universal assembler
- `lib/env-bridge.nix` — Pure data extraction from global config
- `lib/posix/` — POSIX-family helpers (options, configs, file generators)
- `modules/rc.nix` — Complete non-POSIX reference implementation
- `modules/ksh-base.nix` — Complete POSIX reference implementation
