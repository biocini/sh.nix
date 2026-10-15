{ shnixLib }:

let
  envBridge = import ../lib/env-bridge.nix;

  # rc quoting: a single-quoted word with each ' doubled.
  rcQuote = lib: s: "'" + lib.replaceStrings [ "'" ] [ "''" ] s + "'";

  # Converts a POSIX-style value to an rc word. $NAME and ${NAME} become
  # rc variable references ($"NAME, flattened to one string); all other
  # text is quoted literally. Lists are joined with ":".
  rcValue =
    lib: v:
    let
      s = if lib.isList v then lib.concatStringsSep ":" v else toString v;
      parts = builtins.split "\\$\\{([A-Za-z_][A-Za-z0-9_]*)}|\\$([A-Za-z_][A-Za-z0-9_]*)" s;
      toWord =
        p:
        if lib.isList p then
          "$\"" + (if lib.elemAt p 0 != null then lib.elemAt p 0 else lib.elemAt p 1)
        else if p == "" then
          null
        else
          rcQuote lib p;
      words = lib.filter (w: w != null) (map toWord parts);
    in
    if words == [ ] then "''" else lib.concatStringsSep "^" words;

  # Generated rc file. vars and init come from the platform config.
  rcFile =
    {
      header,
      vars,
      init,
    }:
    { lib, cfg, ... }:
    let
      sessionVarsStr = lib.optionalString (vars != { }) (
        "# Session variables.\n"
        + lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "${k} = ${rcValue lib v}") vars)
        + "\n\n"
      );
      historyStr =
        if lib.hasPrefix "/" cfg.historyFile then
          rcQuote lib cfg.historyFile
        else
          "$home/" + rcQuote lib cfg.historyFile;
    in
    ''
      # ${header}: DO NOT EDIT -- this file has been generated automatically.

      ${sessionVarsStr}# History file.
      history=${historyStr}

      # Prompt.
      prompt=(${lib.concatMapStringsSep " " (rcQuote lib) cfg.prompt})

      # Functions (rc's equivalent of aliases).
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "fn ${k} { ${v} $* }") cfg.shellAliases)}

      ${init cfg}
    '';

  aliasAssertion = cfg: {
    assertion = builtins.all (v: builtins.match ".*}.*" v == null) (
      builtins.attrValues cfg.shellAliases
    );
    message = "rc shellAliases cannot contain '}' (breaks fn syntax)";
  };

  systemConfig =
    bridge:
    {
      config,
      lib,
      cfg,
      ...
    }:
    let
      env = bridge { inherit config; };
    in
    {
      assertions = [ (aliasAssertion cfg) ];
      environment.shells = [ "${cfg.package}${cfg.package.passthru.shellPath or "/bin/rc"}" ];
      programs.rc.shellAliases = lib.mkDefault env.shellAliases;
    };

  # /etc/rcrc. Global environment.variables are exported first;
  # programs.rc.sessionVariables override them.
  systemFiles = bridge: {
    "rcrc" = {
      content =
        args@{ config, ... }:
        rcFile {
          header = "/etc/rcrc";
          vars = (bridge { inherit config; }).variables // args.cfg.sessionVariables;
          init = cfg: cfg.loginShellInit;
        } args;
    };
  };
in

shnixLib.mkShellModule {
  name = "rc";

  extraOptions =
    { lib, ... }:
    {
      historyFile = lib.mkOption {
        type = lib.types.str;
        default = ".rc_history";
        description = ''
          Path to the rc history file. A relative path is relative to
          `$home` at shell runtime.
        '';
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
        description = ''
          Functions to define in rc (rc uses fn, not alias). Each function
          passes its arguments to the command: `ll = "ls -l"` gives
          `fn ll { ls -l $* }`.
        '';
      };

      sessionVariables = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.str
            lib.types.int
            lib.types.path
            (lib.types.listOf lib.types.str)
          ]
        );
        default = { };
        description = ''
          Environment variables to set in rc. Lists are joined with ":".
          `$NAME` and `''${NAME}` expand at shell runtime; all other text
          is literal.
        '';
      };
    };

  extraSystemOptions =
    { lib, ... }:
    {
      loginShellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          rc code for /etc/rcrc. rc reads /etc/rcrc only in login shells.
          This option is not bridged from environment.interactiveShellInit,
          because that option holds POSIX shell code.
        '';
      };
    };

  extraHmOptions =
    { lib, ... }:
    {
      initExtra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional rc code for ~/.rcrc.";
      };
    };

  nixosConfig = systemConfig envBridge.nixos;
  darwinConfig = systemConfig envBridge.darwin;

  hmConfig =
    {
      config,
      lib,
      cfg,
      ...
    }:
    let
      env = envBridge.homeManager { inherit config; };
    in
    {
      assertions = [ (aliasAssertion cfg) ];
      programs.rc.shellAliases = lib.mkDefault env.shellAliases;
    };

  nixosFiles = systemFiles envBridge.nixos;
  darwinFiles = systemFiles envBridge.darwin;

  hmFiles = {
    ".rcrc" = {
      content =
        args@{ config, ... }:
        rcFile {
          header = "~/.rcrc";
          vars = (envBridge.homeManager { inherit config; }).sessionVariables // args.cfg.sessionVariables;
          init = cfg: cfg.initExtra;
        } args;
    };
  };
}
