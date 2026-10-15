# Generates NixOS, nix-darwin, and home-manager modules for a POSIX-compatible
# shell, following the established conventions of programs.bash, programs.zsh,
# and programs.fish.
#
# Usage:
#   mkPosixShellModule {
#     name = "ksh";              # mandatory, sets programs.ksh namespace
#     etcRcPath = "kshrc";       # optional, default: name + "rc"
#     homeRcPath = ".kshrc";     # optional, default: "." + name + "rc"
#   }
# => { nixosModule, darwinModule, homeManagerModule }
#
# The default package is pkgs.<name>, resolved at module-evaluation time.
# Users can override programs.<name>.package to use a different variant.

{
  name,
  etcRcPath ? name + "rc",
  homeRcPath ? "." + name + "rc",
}:

let
  envBridge = import ./env-bridge.nix;
  guards = import ./posix/guards.nix;
  posOpts = import ./posix/options.nix;
  posCfgs = import ./posix/configs.nix { inherit envBridge guards; };
  posFiles = import ./posix/files.nix { inherit guards; };

  # Module that registers this shell in the unified profile generator
  shellRegistration =
    { config, lib, ... }:
    {
      config._shnix.posixShells.${name} = lib.mkIf config.programs.${name}.enable {
        guard = guards.guardFor lib name;
        rcFile = "/etc/${etcRcPath}";
        priority = 100;
      };
    };

  systemFiles = {
    ${etcRcPath} = {
      content = posFiles.systemRc { inherit name etcRcPath homeRcPath; };
    };
  };

  # Base modules without profile generation (rc files only)
  base = import ./mk-shell-module.nix {
    inherit name;

    extraOptions = posOpts.posixOptions { inherit name; };
    extraSystemOptions = posOpts.systemOptions;
    extraHmOptions = posOpts.hmOptions;

    nixosConfig = posCfgs.nixos { inherit name; };
    darwinConfig = posCfgs.darwin { inherit name; };
    hmConfig = posCfgs.hm { inherit name; };

    nixosFiles = systemFiles;
    darwinFiles = systemFiles;

    hmFiles = {
      ${homeRcPath} = {
        content = posFiles.hmRc { inherit name homeRcPath; };
      };
    };
  };
in
{
  nixosModule =
    { ... }:
    {
      imports = [
        base.nixosModule
        shellRegistration
        ./posix/profile-nixos.nix
      ];
    };

  darwinModule =
    { ... }:
    {
      imports = [
        base.darwinModule
        shellRegistration
        ./posix/profile-darwin.nix
      ];
    };

  homeManagerModule = base.homeManagerModule;
}
