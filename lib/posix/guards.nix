# Guard expressions for POSIX shells.
# Each expression is a POSIX test that evaluates to true when the
# corresponding shell is running.
rec {
  known = {
    bash = ''[ -n "''${BASH_VERSION:-}" ]'';
    ksh = ''[ -n "''${KSH_VERSION:-}" ]'';
    ksh93 = ''[ -n "''${KSH_VERSION:-}" ]''; # same variable as ksh
    mksh = ''[ -n "''${KSH_VERSION:-}" ]''; # same variable as ksh
    yash = ''[ -n "''${YASH_VERSION:-}" ]'';
  };

  # Guard for a shell name; unknown shells test $<NAME>_VERSION.
  guardFor = lib: name: known.${name} or ''[ -n "''${${lib.toUpper name}_VERSION:-}" ]'';
}
