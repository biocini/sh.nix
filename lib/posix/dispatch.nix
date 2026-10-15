# Guard chain for /etc/profile: dispatches each login shell to its rc file.
# bash is always first, for compatibility with upstream programs.bash.
{ config, lib }:

let
  guards = import ./guards.nix;

  shellList = lib.mapAttrsToList (name: shell: shell // { inherit name; }) config._shnix.posixShells;
  sortedShells = lib.sort (a: b: a.priority < b.priority) shellList;

  bashGuard = ''
    if ${guards.known.bash}; then
      ${config.programs.bash.loginShellInit or ""}
      [ -r /etc/bashrc ] && . /etc/bashrc
  '';

  makeGuard = shell: ''
    ${shell.guard}; then
      export ENV=${shell.rcFile}
      ${config.programs.${shell.name}.loginShellInit or ""}
      [ -r ${shell.rcFile} ] && . ${shell.rcFile}
  '';
in
lib.concatStringsSep "\nelif " ([ bashGuard ] ++ map makeGuard sortedShells) + "\nfi"
