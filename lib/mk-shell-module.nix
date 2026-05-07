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

{
  name,
  package ? null,
  extraOptions ? (_: { }),
  extraHmOptions ? (_: { }),
  defaults ? { },
  nixosConfig ? (_: { }),
  darwinConfig ? (_: { }),
  hmConfig ? (_: { }),
  nixosFiles ? { },
  darwinFiles ? { },
  hmFiles ? { },
}:

let
  pname = name;

  baseOptions =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.${pname};
    in
    {
      options.programs.${pname} = {
        enable = lib.mkEnableOption "${pname} shell";

        package = lib.mkOption {
          type = lib.types.package;
          default = if package != null then package else pkgs.${pname};
          defaultText = lib.literalExpression "pkgs.${pname}";
          description = "The ${pname} package to use.";
        };

        _nixosModuleLoaded = lib.mkOption {
          type = lib.types.bool;
          default = false;
          internal = true;
          visible = false;
        };

        _darwinModuleLoaded = lib.mkOption {
          type = lib.types.bool;
          default = false;
          internal = true;
          visible = false;
        };

        _homeManagerModuleLoaded = lib.mkOption {
          type = lib.types.bool;
          default = false;
          internal = true;
          visible = false;
        };
      }
      // extraOptions {
        inherit
          config
          lib
          pkgs
          cfg
          ;
      }
      // extraHmOptions {
        inherit
          config
          lib
          pkgs
          cfg
          ;
      };
    };

in
{
  nixosModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.${pname};
    in
    {
      imports = [ baseOptions ];
      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            environment.systemPackages = [ cfg.package ];
            assertions = [
              {
                assertion = !cfg._darwinModuleLoaded;
                message = "programs.${pname}: nixosModule cannot be used together with darwinModule";
              }
            ];
            programs.${pname} = {
              _nixosModuleLoaded = true;
            }
            // defaults;
          }
          (nixosConfig {
            inherit
              config
              lib
              pkgs
              cfg
              ;
          })
          (lib.mkIf (nixosFiles != { }) {
            environment.etc = lib.mapAttrs (n: v: {
              text = v.content {
                inherit
                  config
                  lib
                  pkgs
                  cfg
                  ;
              };
            }) nixosFiles;
          })
        ]
      );
    };

  darwinModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.${pname};
    in
    {
      imports = [ baseOptions ];
      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            environment.systemPackages = [ cfg.package ];
            assertions = [
              {
                assertion = !cfg._nixosModuleLoaded;
                message = "programs.${pname}: darwinModule cannot be used together with nixosModule";
              }
            ];
            programs.${pname} = {
              _darwinModuleLoaded = true;
            }
            // defaults;
          }
          (darwinConfig {
            inherit
              config
              lib
              pkgs
              cfg
              ;
          })
          (lib.mkIf (darwinFiles != { }) {
            environment.etc = lib.mapAttrs (n: v: {
              text = v.content {
                inherit
                  config
                  lib
                  pkgs
                  cfg
                  ;
              };
            }) darwinFiles;
          })
        ]
      );
    };

  homeManagerModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.${pname};
    in
    {
      imports = [ baseOptions ];
      config = lib.mkIf cfg.enable (
        lib.mkMerge [
          {
            home.packages = [ cfg.package ];
            programs.${pname} = {
              _homeManagerModuleLoaded = true;
            }
            // defaults;
          }
          (hmConfig {
            inherit
              config
              lib
              pkgs
              cfg
              ;
          })
          (lib.mkIf (hmFiles != { }) {
            home.file = lib.mapAttrs (n: v: {
              text = v.content {
                inherit
                  config
                  lib
                  pkgs
                  cfg
                  ;
              };
            }) hmFiles;
          })
        ]
      );
    };
}
