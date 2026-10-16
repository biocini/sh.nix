# Generic shell module builder.
# Generates nixosModule, darwinModule, and homeManagerModule for any shell.
#
# Usage:
#   mkShellModule {
#     name = "rc";
#     extraOptions = { lib, ... }: { ... };
#     hmFiles = {
#       ".rcrc" = {
#         content = { lib, cfg, ... }: ''...'';
#       };
#     };
#   }
# => { nixosModule, darwinModule, homeManagerModule }
#
# Option hooks:
#   extraOptions        programs.<name>.* on all three platforms
#   extraSystemOptions  programs.<name>.* on NixOS and nix-darwin only
#   extraHmOptions      programs.<name>.* on home-manager only

{
  name,
  package ? null,
  extraOptions ? (_: { }),
  extraSystemOptions ? (_: { }),
  extraHmOptions ? (_: { }),
  nixosConfig ? (_: { }),
  darwinConfig ? (_: { }),
  hmConfig ? (_: { }),
  nixosFiles ? { },
  darwinFiles ? { },
  hmFiles ? { },
}:

let
  pname = name;

  # Calls an option or config hook with the standard arguments.
  withArgs =
    f:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    f {
      inherit config lib pkgs;
      cfg = config.programs.${pname};
    };

  baseOptions =
    args@{
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.programs.${pname} = {
        enable = lib.mkEnableOption "${pname} shell";

        package = lib.mkOption {
          type = lib.types.package;
          default = if package != null then package else pkgs.${pname};
          defaultText = lib.literalExpression "pkgs.${pname}";
          description = "The ${pname} package to use.";
        };
      }
      // withArgs extraOptions args;
    };

  systemOnlyOptions =
    args@{
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.programs.${pname} = withArgs extraSystemOptions args;
    };

  hmOnlyOptions =
    args@{
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.programs.${pname} = withArgs extraHmOptions args;
    };

  mkFiles = args: files: args.lib.mapAttrs (_: v: { text = withArgs v.content args; }) files;

  # NixOS and nix-darwin modules differ only in their flags, platform
  # config and /etc files.
  mkSystemModule =
    { platformConfig, files }:
    args@{
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.${pname};
    in
    {
      imports = [
        baseOptions
        systemOnlyOptions
      ];
      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          { environment.systemPackages = [ cfg.package ]; }
          (withArgs platformConfig args)
          (lib.mkIf (files != { }) { environment.etc = mkFiles args files; })
        ]
      );
    };
in
{
  nixosModule = mkSystemModule {
    platformConfig = nixosConfig;
    files = nixosFiles;
  };

  darwinModule = mkSystemModule {
    platformConfig = darwinConfig;
    files = darwinFiles;
  };

  homeManagerModule =
    args@{
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.${pname};
    in
    {
      imports = [
        baseOptions
        hmOnlyOptions
      ];
      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          { home.packages = [ cfg.package ]; }
          (withArgs hmConfig args)
          (lib.mkIf (hmFiles != { }) { home.file = mkFiles args hmFiles; })
        ]
      );
    };
}
