{
  # Options for the POSIX shell module (available on all platforms)
  posixOptions =
    { name }:
    { lib, ... }:
    {
      histFile = lib.mkOption {
        type = lib.types.str;
        default = "$HOME/.${name}_history";
        description = "Path to the history file. Parameter expansion occurs at shell runtime.";
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
    };

  # NixOS and nix-darwin POSIX options
  systemOptions =
    { lib, ... }:
    {
      loginShellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Shell script code called during login shell initialisation.
          This runs in /etc/profile only when this shell is the login shell.
        '';
      };

      interactiveShellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Shell script code called during interactive shell initialisation.
          This runs in the system rc file after the interactive guard.
        '';
      };
    };

  # Home-manager-specific POSIX options
  hmOptions =
    { lib, ... }:
    {
      initExtra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Additional commands for interactive shell init.";
      };

      profileExtra = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Additional commands for login shell init. They run in ~/.profile
          only when this shell reads it.
        '';
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
        description = ''
          Environment variables to export at login. They are exported in
          ~/.profile only when this shell reads it. Each value is put in
          double quotes, so parameter expansion and command substitution
          occur at shell runtime.
        '';
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
