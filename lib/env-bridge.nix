# Pure data extraction from global environment configuration.
# No mkDefault, no option names, no shell assumptions.
#
# shellAliases: null (unset) entries are dropped and values are strings.
# loginShellInit is not bridged: the unified /etc/profile reads
# environment.loginShellInit directly.
#
# System platforms also give the data that set-environment exports:
#   setEnvironmentDone  the variable that set-environment exports to mark
#                       that it ran
#   path                PATH as a list of directories, first to last
#   variables           all other exported variables (strings or lists)
# The values can contain $HOME and $USER, which expand at shell runtime.
# environment.extraInit is POSIX code and is not bridged; the variables
# that NixOS and nix-darwin export from environment.profiles in
# extraInit are included.
let
  aliases =
    a:
    builtins.mapAttrs (_: toString) (
      builtins.removeAttrs a (builtins.filter (n: a.${n} == null) (builtins.attrNames a))
    );

  reverse =
    l:
    let
      n = builtins.length l;
    in
    builtins.genList (i: builtins.elemAt l (n - 1 - i)) n;

  splitPath = s: builtins.filter (d: builtins.isString d && d != "") (builtins.split ":" s);

  optional = cond: x: if cond then [ x ] else [ ];

  # Exported by the extraInit of the NixOS and nix-darwin environment
  # modules.
  profileVariables =
    profiles:
    if profiles == [ ] then
      { }
    else
      {
        NIX_USER_PROFILE_DIR = "/nix/var/nix/profiles/per-user/$USER";
        NIX_PROFILES = builtins.concatStringsSep " " (reverse profiles);
      };

  common =
    { config }:
    {
      inherit (config.environment) shellInit interactiveShellInit;
      shellAliases = aliases config.environment.shellAliases;
    };

  # NixOS set-environment: environment.variables, then each profile with
  # each suffix of environment.profileRelativeEnvVars. The wrapper
  # directory, ~/bin and ~/.local/bin go before PATH, in this order:
  # ~/.local/bin, ~/bin, wrappers.
  nixos =
    { config }:
    let
      env = config.environment;
      profiles = env.profiles or [ ];
      absolute = builtins.mapAttrs (_: v: if builtins.isList v then v else [ (toString v) ]) env.variables;
      suffixed = builtins.mapAttrs (
        _: suffixes: builtins.concatMap (p: map (s: p + s) suffixes) profiles
      ) (env.profileRelativeEnvVars or { });
      all = builtins.zipAttrsWith (_: builtins.concatLists) [
        absolute
        suffixed
      ];
      wrapperDir = config.security.wrapperDir or null;
    in
    common { inherit config; }
    // {
      setEnvironmentDone = "__NIXOS_SET_ENVIRONMENT_DONE";
      path =
        optional (env.localBinInPath or false) "$HOME/.local/bin"
        ++ optional (env.homeBinInPath or false) "$HOME/bin"
        ++ optional (wrapperDir != null) (toString wrapperDir)
        ++ builtins.concatMap splitPath (all.PATH or [ ]);
      variables =
        builtins.removeAttrs all [ "PATH" ] // profileVariables profiles;
    };

  # nix-darwin set-environment: environment.systemPath, then
  # environment.variables.
  darwin =
    { config }:
    let
      env = config.environment;
      systemPath =
        if builtins.isList (env.systemPath or "") then
          builtins.concatStringsSep ":" env.systemPath
        else
          env.systemPath or "";
    in
    common { inherit config; }
    // {
      setEnvironmentDone = "__NIX_DARWIN_SET_ENVIRONMENT_DONE";
      path = splitPath systemPath;
      variables = env.variables // profileVariables (env.profiles or [ ]);
    };
in
{
  # NixOS platform: extracts from config.environment.*
  inherit nixos;

  # nix-darwin platform: extracts from config.environment.*
  inherit darwin;

  # home-manager platform: extracts from config.home.*
  #   sessionVariablesDone    the variable that hm-session-vars.sh exports
  #                           to mark that it ran
  #   sessionSearchVariables  directories to put before each variable;
  #                           PATH holds home.sessionPath
  homeManager =
    { config }:
    let
      home = config.home;
      sessionPath = home.sessionPath or [ ];
    in
    {
      inherit (home) sessionVariables;
      shellAliases = aliases home.shellAliases;
      sessionVariablesDone = "__HM_SESS_VARS_SOURCED";
      sessionSearchVariables =
        (if sessionPath == [ ] then { } else { PATH = sessionPath; })
        // (home.sessionSearchVariables or { });
    };
}
