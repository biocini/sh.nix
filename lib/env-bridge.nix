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
        interactiveShellInit
        variables
        ;
      # Note: loginShellInit is handled by the unified profile generator
      # directly (unconditional in /etc/profile), not per-shell.
    };

  # nix-darwin platform: same structure as NixOS
  darwin =
    { config }:
    {
      inherit (config.environment)
        shellAliases
        shellInit
        interactiveShellInit
        variables
        ;
      # Note: loginShellInit is handled by the unified profile generator
      # directly (unconditional in /etc/profile), not per-shell.
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
