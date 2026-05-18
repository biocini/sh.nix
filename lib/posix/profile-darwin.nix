# Unified /etc/profile generator for nix-darwin.
# Reads the POSIX shell registry and generates a single /etc/profile
# with a dynamic guard block dispatching to each shell's rc file.
#
# On macOS, /usr/libexec/path_helper prepends system paths (including
# /etc/paths.d/* entries) to PATH.  Nix-darwin's set-environment script
# hardcodes a complete PATH, so anything path_helper added beforehand is
# clobbered.  We call path_helper at runtime after set-environment and
# append only the paths that are not already present, preserving Nix
# path priority while recovering Apple-specific entries.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Import registry to ensure _shnix.posixShells option is declared
  registry = import ./registry.nix;

  # Build a sorted list of registered shells (name -> shell attrs)
  shellList = lib.mapAttrsToList (name: shell: shell // { inherit name; }) config._shnix.posixShells;
  sortedShells = lib.sort (a: b: a.priority < b.priority) shellList;

  # Bash guard — always included for compatibility with upstream programs.bash
  bashGuard = ''
    if [ -n "''${BASH_VERSION:-}" ]; then
      ${config.programs.bash.loginShellInit or ""}
      [ -r /etc/bashrc ] && . /etc/bashrc
  '';

  # Generate guard block for a single registered shell
  makeGuard = shell: ''
    ${shell.guard}; then
      export ENV=${shell.rcFile}
      ${config.programs.${shell.name}.loginShellInit or ""}
      [ -r ${shell.rcFile} ] && . ${shell.rcFile}
  '';

  otherGuards = lib.concatStringsSep "\nelif " (map makeGuard sortedShells);

  allGuards = if otherGuards == "" then bashGuard else bashGuard + "\nelif " + otherGuards;

  pathHelperRecovery = ''
    # Recover Apple-specific paths without prepending them.
    if [ -x /usr/libexec/path_helper ]; then
        _nix_path="$PATH"
        eval $(/usr/libexec/path_helper -s)
        _new_dirs=""
        IFS=:
        for _dir in $PATH; do
            case ":$_nix_path:" in
                *:"$_dir":*) ;;
                *) _new_dirs="$_new_dirs''${_new_dirs:+:}$_dir" ;;
            esac
        done
        unset IFS _dir
        PATH="$_nix_path''${_new_dirs:+:}$_new_dirs"
        unset _nix_path _new_dirs
    fi
  '';
in
{
  imports = [ registry ];

  config = lib.mkIf (config._shnix.posixShells != { }) (
    lib.mkMerge [
      {
        environment.etc.profile.text = lib.mkForce ''
          # /etc/profile: DO NOT EDIT -- this file has been generated automatically.
          # This file is read for login shells.

          # Only execute this file once per shell.
          if [ -n "$__ETC_PROFILE_SOURCED" ]; then return; fi
          __ETC_PROFILE_SOURCED=1

          # Prevent this file from being sourced by interactive non-login child shells.
          export __ETC_PROFILE_DONE=1

          if [ -z "$__NIX_DARWIN_SET_ENVIRONMENT_DONE" ]; then
              . ${config.system.build.setEnvironment}
          fi

          ${pathHelperRecovery}

          ${config.environment.shellInit}
          ${config.environment.loginShellInit}

          # Read system-wide modifications.
          if test -f /etc/profile.local; then
              . /etc/profile.local
          fi

          # Dispatch to shell-specific rc
          ${allGuards}
          fi
        '';
      }
    ]
  );
}
