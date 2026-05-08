{ shnixLib }:

let
  envBridge = import ../lib/env-bridge.nix;
in

shnixLib.mkShellModule {
  name = "rc";

  extraOptions =
    { lib, ... }:
    {
      historyFile = lib.mkOption {
        type = lib.types.str;
        default = "$home/.rc_history";
        description = "Path to the rc history file. Evaluated at shell runtime.";
      };

      prompt = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "; "
          ""
        ];
        description = "The two rc prompts as a list. First element is the primary prompt, second is the continuation prompt.";
      };

      shellAliases = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Functions to define in rc (rc uses fn, not alias).";
      };

      sessionVariables = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.str
            lib.types.int
            lib.types.path
          ]
        );
        default = { };
        description = "Environment variables to set in rc.";
      };

      initExtra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional rc commands for shell init.";
      };
    };

  nixosConfig =
    { config, lib, ... }:
    let
      env = envBridge.nixos { inherit config; };
    in
    {
      programs.rc = {
        shellAliases = lib.mkDefault env.shellAliases;
        initExtra = lib.mkDefault env.interactiveShellInit;
        sessionVariables = lib.mkDefault env.variables;
      };
    };

  darwinConfig =
    { config, lib, ... }:
    let
      env = envBridge.darwin { inherit config; };
    in
    {
      programs.rc = {
        shellAliases = lib.mkDefault env.shellAliases;
        initExtra = lib.mkDefault env.interactiveShellInit;
        sessionVariables = lib.mkDefault env.variables;
      };
    };

  hmConfig =
    { config, lib, ... }:
    let
      env = envBridge.homeManager { inherit config; };
    in
    {
      programs.rc = {
        shellAliases = lib.mkDefault env.shellAliases;
        sessionVariables = lib.mkDefault env.sessionVariables;
      };
    };

  nixosFiles = {
    "rcrc" = {
      content =
        { lib, cfg, ... }:
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

  darwinFiles = {
    "rcrc" = {
      content =
        { lib, cfg, ... }:
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

  hmFiles = {
    ".rcrc" = {
      content =
        { lib, cfg, ... }:
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
          # ~/.rcrc: DO NOT EDIT -- this file has been generated automatically.

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
}
