{
  # Options for the POSIX shell module (available on all platforms)
  posixOptions =
    { name }:
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

  # Home-manager-specific POSIX options
  hmOptions =
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
}
