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
  mkPs1Line =
    lib:
    "PS1="
    + lib.escapeShellArg (
      lib.concatStrings [
        "$"
        "{"
        "USER"
        "}"
        "@"
        "$"
        "{"
        "HOSTNAME"
        "}"
        ":"
        "$"
        "{"
        "PWD"
        "}"
        "$ "
      ]
    );
in

import ./mk-shell-module.nix {
  inherit name;

  extraOptions =
    { lib, ... }:
    {
      histFile = lib.mkOption {
        type = lib.types.str;
        default = "$HOME/.${name}_history";
        description = "Path to the history file. Evaluated at shell runtime.";
      };

      histSize = lib.mkOption {
        type = lib.types.int;
        default = 2000;
        description = "Number of history lines to keep in memory.";
      };

      shellAliases = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Aliases to define in interactive shells.";
      };

      initExtra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional commands for interactive shell init.";
      };

      shellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
        internal = true;
        visible = false;
      };

      loginShellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
        internal = true;
        visible = false;
      };

      interactiveShellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
        internal = true;
        visible = false;
      };
    };

  extraHmOptions =
    { lib, ... }:
    {
      profileExtra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional commands for login shell init.";
      };

      sessionVariables = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.str
            lib.types.int
            lib.types.path
          ]
        );
        default = { };
        description = "Environment variables to export at login.";
      };

      logoutExtra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Commands to run on shell exit. When non-empty, generates a logout
          file and wires it into the interactive init via a trap.
        '';
      };
    };

  nixosConfig =
    {
      config,
      lib,
      pkgs,
      cfg,
    }:
    {
      environment.variables.ENV = lib.mkDefault "/etc/${etcRcPath}";
      programs.${name} = {
        shellInit = ''
          if [ -z "$__NIXOS_SET_ENVIRONMENT_DONE" ]; then
            . ${config.system.build.setEnvironment}
          fi
          ${config.environment.shellInit}
        '';
        loginShellInit = config.environment.loginShellInit;
        interactiveShellInit = config.environment.interactiveShellInit;
        shellAliases = lib.mkDefault config.environment.shellAliases;
      };
    };

  darwinConfig =
    {
      config,
      lib,
      pkgs,
      cfg,
    }:
    {
      environment.variables.ENV = lib.mkDefault "/etc/${etcRcPath}";
      environment.variables.LANG = lib.mkDefault "C.UTF-8";
      programs.${name} = {
        shellInit = ''
          if [ -z "$__NIX_DARWIN_SET_ENVIRONMENT_DONE" ]; then
            . ${config.system.build.setEnvironment}
          fi
          ${config.environment.shellInit}
        '';
        loginShellInit = config.environment.loginShellInit;
        interactiveShellInit = config.environment.interactiveShellInit;
      };
    };

  hmConfig =
    {
      config,
      lib,
      pkgs,
      cfg,
    }:
    {
      programs.${name} = {
        shellAliases = lib.mkDefault config.home.shellAliases;
        initExtra = lib.mkIf (cfg.logoutExtra != "") (
          lib.mkAfter ''
            trap ". $HOME/.${name}_logout" EXIT
          ''
        );
      };
      home.file.".${name}_logout" = lib.mkIf (cfg.logoutExtra != "") {
        text = ''
          # ~/.${name}_logout: DO NOT EDIT -- this file has been generated automatically.

          ${cfg.logoutExtra}
        '';
      };
    };

  nixosFiles = {
    ${etcRcPath} = {
      content =
        {
          lib,
          cfg,
          config,
          ...
        }:
        let
          PNAME = lib.strings.toUpper name;
          aliasesStr = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (k: v: "alias ${k}=${lib.escapeShellArg v}") cfg.shellAliases
          );
          ps1Line = mkPs1Line lib;
        in
        ''
          # /etc/${etcRcPath}: DO NOT EDIT -- this file has been generated automatically.
          # This file is read for interactive shells.

          # Only execute this file once per shell.
          if [ -n "$__ETC_${PNAME}RC_SOURCED" ]; then return; fi
          __ETC_${PNAME}RC_SOURCED=1

          # If /etc/profile was not loaded in a parent process, source it.
          if [ -z "$__ETC_PROFILE_DONE" ]; then
            . /etc/profile
          fi

          # Setup command line history.
          HISTSIZE=${toString cfg.histSize}
          HISTFILE=${cfg.histFile}

          # Safe defaults.
          set -o noclobber
          ${ps1Line}

          ${aliasesStr}

          ${cfg.interactiveShellInit}

          # Read system-wide modifications.
          if test -f /etc/${etcRcPath}.local; then
            . /etc/${etcRcPath}.local
          fi

          [ -r "$HOME/${homeRcPath}" ] && . "$HOME/${homeRcPath}"
        '';
    };
    "profile" = {
      content =
        {
          lib,
          cfg,
          config,
          ...
        }:
        let
          PNAME = lib.strings.toUpper name;
        in
        lib.mkForce ''
          # /etc/profile: DO NOT EDIT -- this file has been generated automatically.
          # This file is read for login shells.

          # Only execute this file once per shell.
          if [ -n "$__ETC_PROFILE_SOURCED" ]; then return; fi
          __ETC_PROFILE_SOURCED=1

          # Prevent this file from being sourced by interactive non-login child shells.
          export __ETC_PROFILE_DONE=1

          ${cfg.shellInit}

          ${cfg.loginShellInit}

          # Read system-wide modifications.
          if test -f /etc/profile.local; then
            . /etc/profile.local
          fi

          [ -r "$ENV" ] && . "$ENV"
        '';
    };
  };

  darwinFiles = {
    ${etcRcPath} = {
      content =
        {
          lib,
          cfg,
          config,
          ...
        }:
        let
          PNAME = lib.strings.toUpper name;
          ps1Line = mkPs1Line lib;
        in
        ''
          # /etc/${etcRcPath}: DO NOT EDIT -- this file has been generated automatically.
          # This file is read for interactive shells.

          # Only execute this file once per shell.
          if [ -n "$__ETC_${PNAME}RC_SOURCED" ]; then return; fi
          __ETC_${PNAME}RC_SOURCED=1

          # If /etc/profile was not loaded in a parent process, source it.
          if [ -z "$__ETC_PROFILE_DONE" ]; then
            . /etc/profile
          fi

          # Setup command line history.
          HISTSIZE=${toString cfg.histSize}
          HISTFILE=${cfg.histFile}

          # Safe defaults.
          set -o noclobber
          ${ps1Line}

          . ${config.system.build.setAliases}

          ${cfg.interactiveShellInit}

          # Read system-wide modifications.
          if test -f /etc/${etcRcPath}.local; then
            . /etc/${etcRcPath}.local
          fi

          [ -r "$HOME/${homeRcPath}" ] && . "$HOME/${homeRcPath}"
        '';
    };
    "profile" = {
      content =
        {
          lib,
          cfg,
          config,
          ...
        }:
        let
          PNAME = lib.strings.toUpper name;
        in
        ''
          # /etc/profile: DO NOT EDIT -- this file has been generated automatically.
          # This file is read for login shells.

          # Only execute this file once per shell.
          if [ -n "$__ETC_PROFILE_SOURCED" ]; then return; fi
          __ETC_PROFILE_SOURCED=1

          # Prevent this file from being sourced by interactive non-login child shells.
          export __ETC_PROFILE_DONE=1

          if [ -x /usr/libexec/path_helper ]; then
            eval `/usr/libexec/path_helper -s`
          fi

          ${cfg.shellInit}

          ${cfg.loginShellInit}

          # Read system-wide modifications.
          if test -f /etc/profile.local; then
            . /etc/profile.local
          fi

          # Escape hatch for bash on darwin
          if [ "''${BASH-no}" != "no" ]; then
            [ -r /etc/bashrc ] && . /etc/bashrc
          elif [ -r "$ENV" ]; then
            . "$ENV"
          fi
        '';
    };
  };

  hmFiles = {
    ".profile" = {
      content =
        {
          lib,
          cfg,
          config,
          ...
        }:
        let
          sessionVariablesStr = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") cfg.sessionVariables
          );
        in
        ''
          # ~/.profile: DO NOT EDIT -- this file has been generated automatically.

          . "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"

          ${sessionVariablesStr}

          ${cfg.profileExtra}
        '';
    };
    ${homeRcPath} = {
      content =
        { lib, cfg, ... }:
        let
          PNAME = lib.strings.toUpper name;
          aliasesStr = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (k: v: "alias ${k}=${lib.escapeShellArg v}") cfg.shellAliases
          );
        in
        ''
          # ~/${homeRcPath}: DO NOT EDIT -- this file has been generated automatically.

          # Only execute this file once per shell.
          if [ -n "$__HOME_${PNAME}RC_SOURCED" ]; then return; fi
          __HOME_${PNAME}RC_SOURCED=1

          # Commands that should be applied only for interactive shells.
          case $- in
            *i*) ;;
            *) return ;;
          esac

          # Setup command line history.
          HISTSIZE=${toString cfg.histSize}
          HISTFILE=${cfg.histFile}

          ${aliasesStr}

          ${cfg.initExtra}
        '';
    };
  };
}
