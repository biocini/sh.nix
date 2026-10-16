{ shnixLib }:

let
  envBridge = import ../lib/env-bridge.nix;

  # rc quoting: a single-quoted word with each ' doubled.
  rcQuote = lib: s: "'" + lib.replaceStrings [ "'" ] [ "''" ] s + "'";

  # Converts values with POSIX double-quote syntax to rc words. Each value
  # gives one word:
  #   \$ \` \" \\           the literal character
  #   $NAME ${NAME}         $"NAME, the variable flattened to one string
  #   ${NAME:-word}         word if NAME is unset or empty, else $"NAME
  #   ${NAME-word}          word if NAME is unset, else $"NAME
  # With an empty word, both forms are $"NAME.
  # All other text is literal. A default needs rc code before the word
  # (pre) and after it (post), with a temporary variable that has the
  # prefix tmp.
  rcWords =
    lib: tmp: values:
    let
      name = "[A-Za-z_][A-Za-z0-9_]*";
      # A default word: text, escapes and references, without "}".
      word = "((\\\\.|[^}$\\\\]|\\$" + name + "|\\$\\{" + name + "})*)";
      re = ''\\([$`"\\])|\$\{(${name})(:?-)${word}}|\$\{(${name})}|\$(${name})'';

      # Items are { lit = string; } or { ref = rc word; }.
      item =
        acc: p:
        let
          g = lib.elemAt p;
          add = x: acc // { items = acc.items ++ [ x ]; };
          var = "${tmp}${toString acc.n}";
          dflt = rcWords lib "${var}_" [ (g 3) ];
          test = if g 2 == ":-" then "~ $#${g 1} 0 || ~ $\"${g 1} ''" else "~ $#${g 1} 0";
        in
        if lib.isString p then
          add { lit = p; }
        else if g 0 != null then
          add { lit = g 0; }
        else if g 1 != null && g 3 == "" then
          add { ref = "$\"${g 1}"; }
        else if g 1 != null then
          acc
          // {
            n = acc.n + 1;
            items = acc.items ++ [ { ref = "$\"${var}"; } ];
            pre =
              acc.pre
              ++ dflt.pre
              ++ [ "if (${test}) { ${var} = ${lib.head dflt.words} } else { ${var} = $\"${g 1} }" ]
              ++ dflt.post;
            post = acc.post ++ [ "${var} = ()" ];
          }
        else
          add { ref = "$\"" + (if g 5 != null then g 5 else g 6); };

      # Joins adjacent literals, quotes them and concatenates with ^.
      render =
        items:
        let
          merged = lib.foldl' (
            out: x:
            if x ? lit && out != [ ] && (lib.last out) ? lit then
              lib.init out ++ [ { lit = (lib.last out).lit + x.lit; } ]
            else
              out ++ [ x ]
          ) [ ] (lib.filter (x: !(x ? lit) || x.lit != "") items);
          word = x: if x ? lit then rcQuote lib x.lit else x.ref;
        in
        if merged == [ ] then "''" else lib.concatMapStringsSep "^" word merged;

      value =
        acc: v:
        let
          r = lib.foldl' item (acc // { items = [ ]; }) (builtins.split re v);
        in
        r // { words = acc.words ++ [ (render r.items) ]; };
    in
    builtins.removeAttrs
      (lib.foldl' value {
        n = 0;
        pre = [ ];
        post = [ ];
        words = [ ];
      } values)
      [
        "items"
        "n"
      ];

  # rc lines that assign values to a variable. More than one value gives
  # an rc list. A list value of a variable is joined with ":".
  rcAssignList =
    lib: name: values: tail:
    let
      r = rcWords lib "_shnix_${name}_" values;
      words = lib.concatStringsSep " " (r.words ++ tail);
    in
    r.pre ++ [ "${name} = ${if lib.length r.words + lib.length tail == 1 then words else "(${words})"}" ] ++ r.post;

  rcAssign =
    lib: name: v:
    rcAssignList lib name [ (if lib.isList v then lib.concatStringsSep ":" v else toString v) ] [ ];

  # The body of a block that runs once per login session: the marker
  # variable, then the assignments.
  onceBlock =
    lib: marker: lines:
    let
      body = [ "${marker} = 1" ] ++ lines;
    in
    ''
      if (~ $#${marker} 0) {
        ${lib.concatStringsSep "\n  " body}
      }
    '';

  # The environment that set-environment exports on NixOS and nix-darwin.
  systemEnvironment =
    lib: env:
    ''
      # Global environment. A shell that inherits it does not set it again.
    ''
    + onceBlock lib env.setEnvironmentDone (
      lib.optionals (env.path != [ ]) (rcAssignList lib "path" env.path [ ])
      ++ lib.concatLists (lib.mapAttrsToList (rcAssign lib) env.variables)
    );

  # path_helper(8) puts the directories from /etc/paths and /etc/paths.d
  # first. Here the Nix directories stay first and the other directories
  # go after them. The separator is a newline, so a directory name can
  # contain spaces.
  darwinPaths = ''

    # Directories from /etc/paths and /etc/paths.d that are not in $path.
    for (_d in `` ('
    ') {/bin/cat /etc/paths /etc/paths.d/* >[2]/dev/null}) {
      if (! ~ $_d $path) path = ($path $_d)
    }
    _d = ()
  '';

  # The environment of hm-session-vars.sh: home.sessionVariables, then
  # the directories of home.sessionSearchVariables before the current
  # value of each variable.
  hmEnvironment =
    lib: env:
    let
      search =
        name: dirs:
        let
          r = rcWords lib "_shnix_${name}_" [ (lib.concatStringsSep ":" dirs) ];
          value = lib.head r.words;
        in
        if name == "PATH" then
          rcAssignList lib "path" dirs [ "$path" ]
        else
          r.pre
          ++ [
            "if (~ $#${name} 0 || ~ $\"${name} '') { ${name} = ${value} } else { ${name} = ${value}^':'^$\"${name} }"
          ]
          ++ r.post;
    in
    ''
      # home-manager session environment. A shell that inherits it does not
      # set it again.
    ''
    + onceBlock lib env.sessionVariablesDone (
      lib.concatLists (
        lib.mapAttrsToList (rcAssign lib) env.sessionVariables
        ++ lib.mapAttrsToList search env.sessionSearchVariables
      )
    );

  # Generated rc file. The environment, vars and init come from the
  # platform config.
  rcFile =
    {
      header,
      environment,
      vars,
      init,
    }:
    { lib, cfg, ... }:
    let
      sessionVarsStr = lib.optionalString (vars != { }) (
        "# Session variables.\n"
        + lib.concatStringsSep "\n" (lib.concatLists (lib.mapAttrsToList (rcAssign lib) vars))
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

      ${environment}
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

  # /etc/rcrc. The global environment comes first;
  # programs.rc.sessionVariables override it.
  systemFiles =
    bridge: extra: {
      "rcrc" = {
        content =
          args@{ config, lib, ... }:
          rcFile {
            header = "/etc/rcrc";
            environment = systemEnvironment lib (bridge { inherit config; }) + extra;
            vars = args.cfg.sessionVariables;
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
          Environment variables to set in each rc login shell, after the
          global environment. Lists are joined with ":". Values use the
          rules of a POSIX double-quoted string: `$NAME`, `''${NAME}`,
          `''${NAME:-word}` and `''${NAME-word}` expand at shell runtime,
          and a backslash before `$`, `` ` ``, `"` or `\` gives that
          character. Command substitution is not supported.
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
          environment.extraInit, environment.shellInit,
          environment.loginShellInit and environment.interactiveShellInit
          hold POSIX code and are not copied to /etc/rcrc; put rc code
          with the same effect here.
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

  nixosFiles = systemFiles envBridge.nixos "";
  darwinFiles = systemFiles envBridge.darwin darwinPaths;

  hmFiles = {
    ".rcrc" = {
      content =
        args@{ config, ... }:
        rcFile {
          header = "~/.rcrc";
          environment = hmEnvironment args.lib (envBridge.homeManager { inherit config; });
          vars = args.cfg.sessionVariables;
          init = cfg: cfg.initExtra;
        } args;
    };
  };
}
