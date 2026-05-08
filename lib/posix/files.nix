rec {
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

  nixosRc =
    {
      name,
      etcRcPath,
      homeRcPath,
    }:
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

  nixosProfile =
    { name }:
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

  darwinRc =
    {
      name,
      etcRcPath,
      homeRcPath,
    }:
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

  darwinProfile =
    { name }:
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

  hmProfile =
    { name }:
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

  hmRc =
    { name, homeRcPath }:
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
}
