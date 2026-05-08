{
  # Pure data extraction from global environment configuration.
  # Returns standardized attrsets for nixos, darwin, and homeManager platforms.
  #
  # Usage:
  #   let env = shnix.lib.envBridge.nixos { inherit config; };
  #   in programs.mysh.shellAliases = lib.mkDefault env.shellAliases;
  envBridge = import ./env-bridge.nix;

  # Generic shell module builder.
  # Accepts declarative file specs per platform and returns three modules.
  #
  # Usage:
  #   shnix.lib.mkShellModule {
  #     name = "rc";
  #     extraOptions = { lib, ... }: { ... };
  #     hmFiles = { ".rcrc" = { content = ...; }; };
  #   }
  mkShellModule = import ./mk-shell-module.nix;

  # POSIX-specialized wrapper around mkShellModule.
  # Provides POSIX-specific defaults, file templates, and environment integration.
  #
  # Usage:
  #   shnix.lib.mkPosixShellModule {
  #     name = "ksh";
  #     etcRcPath = "kshrc";
  #     homeRcPath = ".kshrc";
  #   }
  mkPosixShellModule = import ./mk-posix-shell.nix;
}
