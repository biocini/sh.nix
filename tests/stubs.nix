{ pkgs, lib }:

{
  # Minimal NixOS-like infrastructure for module evaluation tests
  nixos = {
    options = {
      environment.systemPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };
      environment.variables = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.str
            lib.types.int
          ]
        );
        default = { };
      };
      environment.etc = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      environment.shellAliases = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
      };
      environment.shellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      environment.loginShellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      environment.interactiveShellInit = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      assertions = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
      };
      system.build.setEnvironment = lib.mkOption {
        type = lib.types.package;
        default = pkgs.writeTextFile {
          name = "set-environment";
          text = "";
          executable = true;
        };
      };
      system.build.setAliases = lib.mkOption {
        type = lib.types.package;
        default = pkgs.writeTextFile {
          name = "set-aliases";
          text = "";
          executable = true;
        };
      };
    };
  };

  # Minimal home-manager-like infrastructure
  homeManager = {
    options = {
      home.packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
      };
      home.file = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
      home.shellAliases = lib.mkOption {
        type = lib.types.attrsOf (lib.types.nullOr lib.types.str);
        default = { };
      };
      home.sessionVariables = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.oneOf [
            lib.types.str
            lib.types.int
            lib.types.path
          ]
        );
        default = { };
      };
      home.sessionVariablesPackage = lib.mkOption {
        type = lib.types.package;
        default = pkgs.writeTextFile {
          name = "hm-session-vars";
          text = "";
          executable = true;
        };
      };
      home.username = lib.mkOption {
        type = lib.types.str;
        default = "test";
      };
      home.homeDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/home/test";
      };
    };
  };
}
