# Unified /etc/profile generator for NixOS.
# Reads the POSIX shell registry and generates a single /etc/profile
# with a guard chain that dispatches to each shell's rc file.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Import registry to ensure _shnix.posixShells option is declared
  registry = import ./registry.nix;

  dispatch = import ./dispatch.nix { inherit config lib; };
in
{
  imports = [ registry ];

  config = lib.mkIf (config._shnix.posixShells != { }) {
    environment.etc.profile.text = lib.mkForce ''
      # /etc/profile: DO NOT EDIT -- this file has been generated automatically.
      # This file is read for login shells.

      # Only execute this file once per shell.
      if [ -n "$__ETC_PROFILE_SOURCED" ]; then return; fi
      __ETC_PROFILE_SOURCED=1

      # Prevent this file from being sourced by interactive non-login child shells.
      export __ETC_PROFILE_DONE=1

      if [ -z "$__NIXOS_SET_ENVIRONMENT_DONE" ]; then
          . ${config.system.build.setEnvironment}
      fi

      ${config.environment.shellInit}
      ${config.environment.loginShellInit}

      # Read system-wide modifications.
      if test -f /etc/profile.local; then
          . /etc/profile.local
      fi

      # Dispatch to shell-specific rc
      ${dispatch}
    '';
  };
}
