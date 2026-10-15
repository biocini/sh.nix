{ guards }:

let
  # Default prompt: user@host:cwd$ . Single quotes defer $USER and $PWD
  # to prompt time; the host name is resolved once.
  ps1Lines = ''
    _shnix_host=$(uname -n)
    PS1='$USER@'"''${_shnix_host%%.*}"':$PWD$ '
    unset _shnix_host
  '';

  aliasLines =
    lib: aliases:
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (k: v: "alias -- ${lib.escapeShellArg k}=${lib.escapeShellArg v}") aliases
    );

  # The rc file can reach other shells through an inherited ENV, so it
  # returns early unless this shell is running.
  shellGuardLines = lib: name: ''
    # Only read this file in ${name}.
    ${guards.guardFor lib name} || return
  '';
in
{
  systemRc =
    {
      name,
      etcRcPath,
      homeRcPath,
    }:
    { lib, cfg, ... }:
    let
      PNAME = lib.strings.toUpper name;
    in
    ''
      # /etc/${etcRcPath}: DO NOT EDIT -- this file has been generated automatically.
      # This file is read for interactive shells.

      ${shellGuardLines lib name}
      # Only execute this file once per shell.
      if [ -n "$__ETC_${PNAME}RC_SOURCED" ]; then return; fi
      __ETC_${PNAME}RC_SOURCED=1

      # If /etc/profile was not loaded in a parent process, source it.
      if [ -z "$__ETC_PROFILE_DONE" ]; then
        . /etc/profile
      fi

      # Commands that should be applied only for interactive shells.
      case $- in
        *i*) ;;
        *) return ;;
      esac

      # Setup command line history.
      HISTSIZE=${toString cfg.histSize}
      HISTFILE="${cfg.histFile}"

      ${ps1Lines}
      ${aliasLines lib cfg.shellAliases}

      ${cfg.interactiveShellInit}

      # Read system-wide modifications.
      if test -f /etc/${etcRcPath}.local; then
        . /etc/${etcRcPath}.local
      fi

      [ -r "$HOME/${homeRcPath}" ] && . "$HOME/${homeRcPath}"
    '';

  hmRc =
    { name, homeRcPath }:
    { lib, cfg, ... }:
    let
      PNAME = lib.strings.toUpper name;
    in
    ''
      # ~/${homeRcPath}: DO NOT EDIT -- this file has been generated automatically.

      ${shellGuardLines lib name}
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
      HISTFILE="${cfg.histFile}"

      ${aliasLines lib cfg.shellAliases}

      ${cfg.initExtra}
    '';
}
