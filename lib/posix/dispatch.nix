# Shell-specific parts of /etc/profile.
#
#   login  environment.shellInit and environment.loginShellInit. When the
#          platform gives bashInit, bash runs bashInit instead.
#   rc     the guard chain. bash reads /etc/bashrc. Each registered shell
#          exports ENV and runs its loginShellInit; the shell reads ENV
#          after ~/.profile. bash is always first.
{
  config,
  lib,
  bashInit ? null,
}:

let
  guards = import ./guards.nix;

  shellList = lib.mapAttrsToList (name: shell: shell // { inherit name; }) config._shnix.posixShells;
  sortedShells = lib.sort (a: b: a.priority < b.priority) shellList;

  commonInit = ''
    ${config.environment.shellInit}
    ${config.environment.loginShellInit}
  '';

  # A branch with no commands is a syntax error.
  branch = s: if lib.trim s == "" then ":" else s;

  bashGuard = ''
    if ${guards.known.bash}; then
      [ -r /etc/bashrc ] && . /etc/bashrc
  '';

  makeGuard = shell: ''
    ${shell.guard}; then
      export ENV=${shell.rcFile}
      ${config.programs.${shell.name}.loginShellInit or ""}
  '';
in
{
  login =
    if bashInit == null then
      commonInit
    else
      ''
        if ${guards.known.bash}; then
          ${branch bashInit}
        else
          ${branch commonInit}
        fi
      '';

  rc = lib.concatStringsSep "\nelif " ([ bashGuard ] ++ map makeGuard sortedShells) + "\nfi";
}
