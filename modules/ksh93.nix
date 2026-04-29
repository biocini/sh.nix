# KornShell 93 (ksh93u+m) module — layers ksh-specific options on top of
# sh.nix's POSIX shell base.

{ shnixLib }:

let
  base = shnixLib.mkPosixShellModule {
    name = "ksh";
    etcRcPath = "kshrc";
    homeRcPath = ".kshrc";
  };
in

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.ksh;
in

{
  imports = [ base ];

  options.programs.ksh = {
    shellOptions = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "Shell options to enable via `set -o`.";
    };

    functionsDir = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Directory for autoload functions (sets FPATH).";
    };
  };

  config.programs.ksh = {
    histSize = lib.mkDefault 10000;

    initExtra = lib.mkIf cfg.enable (
      lib.mkAfter ''
        ${lib.concatMapStringsSep "\n" (o: "set -o ${o}") cfg.shellOptions}
        ${lib.optionalString (cfg.functionsDir != null) ''
          export FPATH=${cfg.functionsDir}:''${FPATH:-/usr/share/ksh/functions}
        ''}
      ''
    );
  };
}
