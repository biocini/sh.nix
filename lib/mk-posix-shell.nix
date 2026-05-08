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
in

import ./mk-shell-module.nix {
  inherit name;

  extraOptions = posOpts.posixOptions { inherit name; };
  extraHmOptions = posOpts.hmOptions;

  nixosConfig = posCfgs.nixos { inherit name etcRcPath; };
  darwinConfig = posCfgs.darwin { inherit name etcRcPath; };
  hmConfig = posCfgs.hm { inherit name; };

  nixosFiles = {
    ${etcRcPath} = {
      content = posFiles.nixosRc { inherit name etcRcPath homeRcPath; };
    };
    "profile" = {
      content = posFiles.nixosProfile { inherit name; };
    };
  };

  darwinFiles = {
    ${etcRcPath} = {
      content = posFiles.darwinRc { inherit name etcRcPath homeRcPath; };
    };
    "profile" = {
      content = posFiles.darwinProfile { inherit name; };
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
}
