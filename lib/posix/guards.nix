# Default guard expressions for known POSIX shells.
# Each expression is a POSIX test that evaluates to true when the
# corresponding shell is running.
{
  bash = ''[ -n "''${BASH_VERSION:-}" ]'';
  ksh = ''[ -n "$KSH_VERSION" ]'';
  ksh93 = ''[ -n "$KSH_VERSION" ]''; # same variable as ksh
  mksh = ''[ -n "$KSH_VERSION" ]''; # same variable as ksh
  yash = ''[ -n "$YASH_VERSION" ]'';
}
