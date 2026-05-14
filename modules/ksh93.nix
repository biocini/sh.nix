# KornShell 93 (ksh93u+m) — ksh-specific options and config layered on top
# of the POSIX shell base.  Import this alongside the platform-specific base
# module (nixosModule / darwinModule / homeManagerModule).

{ config, lib, ... }:

let
  cfg = config.programs.ksh;
in

{
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
          export FPATH=${cfg.functionsDir}''${FPATH:+:$FPATH}
        ''}
      ''
    );
  };
}
