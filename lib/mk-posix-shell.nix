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
  posOpts = import ./posix/options.nix;
  posCfgs = import ./posix/configs.nix { inherit envBridge; };
  posFiles = import ./posix/files.nix;
  guards = import ./posix/guards.nix;

  # Module that registers this shell in the unified profile generator
  shellRegistration =
    { config, lib, ... }:
    {
      config._shnix.posixShells.${name} = lib.mkIf config.programs.${name}.enable {
        guard = guards.${name} or ''[ -n "$${lib.toUpper name}_VERSION" ]'';
        rcFile = "/etc/${etcRcPath}";
        priority = 100;
      };
    };

  # Base modules without profile generation (rc files only)
  base = import ./mk-shell-module.nix {
    inherit name;

    extraOptions = posOpts.posixOptions { inherit name; };
    extraHmOptions = posOpts.hmOptions;

    nixosConfig = posCfgs.nixos { inherit name; };
    darwinConfig = posCfgs.darwin { inherit name; };
    hmConfig = posCfgs.hm { inherit name; };

    nixosFiles = {
      ${etcRcPath} = {
        content = posFiles.nixosRc { inherit name etcRcPath homeRcPath; };
      };
    };

    darwinFiles = {
      ${etcRcPath} = {
        content = posFiles.darwinRc { inherit name etcRcPath homeRcPath; };
      };
    };

    hmFiles = {
      ".profile" = {
        content = posFiles.hmProfile { inherit name; };
      };
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
