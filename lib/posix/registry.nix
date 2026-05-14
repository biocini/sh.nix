# Declares the internal option where POSIX shells register themselves
# for unified /etc/profile generation.
{ lib, ... }:

{
  options._shnix.posixShells = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          guard = lib.mkOption {
            type = lib.types.str;
            description = "POSIX test expression for this shell (e.g. '[ -n \"\$KSH_VERSION\" ]')";
          };
          rcFile = lib.mkOption {
            type = lib.types.str;
            description = "Absolute path to the system-wide rc file (e.g. /etc/kshrc)";
          };
          priority = lib.mkOption {
            type = lib.types.int;
            default = 100;
            description = "Guard block ordering (lower = earlier)";
          };
        };
      }
    );
    default = { };
    internal = true;
    description = "Registry of POSIX shells for unified /etc/profile generation.";
  };
}
