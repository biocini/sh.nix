# Pure data extraction from global environment configuration.
# No mkDefault, no option names, no shell assumptions.
{
  # NixOS platform: extracts from config.environment.*
  nixos =
    { config }:
    {
      inherit (config.environment)
        shellAliases
        shellInit
        loginShellInit
        interactiveShellInit
        variables
        ;
    };

  # nix-darwin platform: same structure as NixOS
  darwin =
    { config }:
    {
      inherit (config.environment)
        shellAliases
        shellInit
        loginShellInit
        interactiveShellInit
        variables
        ;
    };

  # home-manager platform: extracts from config.home.*
  homeManager =
    { config }:
    {
      inherit (config.home)
        shellAliases
        sessionVariables
        ;
    };
}
