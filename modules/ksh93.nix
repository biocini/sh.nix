# KornShell 93 (ksh93u+m) — ksh-specific options and config layered on top
# of the POSIX shell base.  Import this alongside the platform-specific base
# module (nixosModule / darwinModule / homeManagerModule).

{
  config,
  lib,
  options,
  ...
}:

let
  cfg = config.programs.ksh;

  initLines = lib.concatStringsSep "\n" (
    map (o: "set -o ${o}") cfg.shellOptions
    ++ lib.optional (cfg.functionsDir != null) ''export FPATH="${cfg.functionsDir}''${FPATH:+:$FPATH}"''
  );

  # Interactive init goes to initExtra on home-manager and to
  # interactiveShellInit on NixOS and nix-darwin.
  initOption = if options.programs.ksh ? initExtra then "initExtra" else "interactiveShellInit";
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
      description = "Directory for autoload functions (prepended to FPATH).";
    };
  };

  config.programs.ksh = {
    histSize = lib.mkDefault 10000;
    ${initOption} = lib.mkIf (cfg.enable && initLines != "") (lib.mkAfter initLines);
  };
}
