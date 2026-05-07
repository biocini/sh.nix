{ shnixLib }:

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

      initExtra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional rc commands for shell init.";
      };
    };

  nixosFiles = {
    "rcrc" = {
      content =
        { lib, cfg, ... }:
        ''
          # /etc/rcrc: DO NOT EDIT -- this file has been generated automatically.

          # History file.
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
        ''
          # /etc/rcrc: DO NOT EDIT -- this file has been generated automatically.

          # History file.
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
        ''
          # ~/.rcrc: DO NOT EDIT -- this file has been generated automatically.

          # History file.
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
