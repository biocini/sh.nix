# Pure data extraction from global environment configuration.
# No mkDefault, no option names, no shell assumptions.
#
# shellAliases: null (unset) entries are dropped and values are strings.
# loginShellInit is not bridged: the unified /etc/profile reads
# environment.loginShellInit directly.
let
  aliases =
    a:
    builtins.mapAttrs (_: toString) (
      builtins.removeAttrs a (builtins.filter (n: a.${n} == null) (builtins.attrNames a))
    );

  system =
    { config }:
    {
      inherit (config.environment) shellInit interactiveShellInit variables;
      shellAliases = aliases config.environment.shellAliases;
    };
in
{
  # NixOS platform: extracts from config.environment.*
  nixos = system;

  # nix-darwin platform: same structure as NixOS
  darwin = system;

  # home-manager platform: extracts from config.home.*
  homeManager =
    { config }:
    {
      inherit (config.home) sessionVariables;
      shellAliases = aliases config.home.shellAliases;
    };
}
