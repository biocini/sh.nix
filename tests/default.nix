{ self, nixpkgs }:

let
  lib = nixpkgs.lib;
  system = "aarch64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
  stubs = import ./stubs.nix { inherit pkgs lib; };

  # pkgs comes from _module.args, as in NixOS, nix-darwin and home-manager:
  # a module receives it only when its argument pattern names it.
  evalModules = modules: lib.evalModules { modules = modules ++ [ { _module.args.pkgs = pkgs; } ]; };
  evalNixos = evalModules;
  evalDarwin = evalModules;
  evalHm = evalModules;

  # Evaluated config for one module and extra settings.
  nixosCfg =
    module: extra:
    (evalNixos [
      stubs.nixos
      module
      extra
    ]).config;
  darwinCfg =
    module: extra:
    (evalDarwin [
      stubs.nixos
      module
      extra
    ]).config;
  hmCfg =
    module: extra:
    (evalHm [
      stubs.homeManager
      module
      extra
    ]).config;

  kshrcOn = cfg: cfg.environment.etc.kshrc.text;
  rcrcOn = cfg: cfg.environment.etc.rcrc.text;
in
# nix-unit only discovers attributes whose names start with "test"
lib.mapAttrs'
  (name: value: {
    name = "test_" + lib.replaceStrings [ " " "." "-" "/" ] [ "_" "_" "_" "_" ] name;
    inherit value;
  })
  {
    "lib.mkPosixShellModule returns three modules" = {
      expr = builtins.attrNames (self.lib.mkPosixShellModule { name = "ksh"; });
      expected = [
        "darwinModule"
        "homeManagerModule"
        "nixosModule"
      ];
    };

    "lib.mkPosixShellModule honours custom paths" = {
      expr =
        let
          mods = self.lib.mkPosixShellModule {
            name = "yash";
            etcRcPath = "yashrc";
            homeRcPath = ".yashrc";
          };
          cfg =
            (evalNixos [
              stubs.nixos
              mods.nixosModule
              { programs.yash.enable = true; }
            ]).config;
        in
        builtins.hasAttr "yashrc" cfg.environment.etc;
      expected = true;
    };

    "overlay exposes ksh, ksh-nightly, and rc" = {
      expr = builtins.attrNames (self.overlays.default pkgs pkgs);
      expected = [
        "ksh"
        "ksh-nightly"
        "rc"
      ];
    };

    "rc overlay uses nightly version" = {
      expr =
        let
          overlayed = self.overlays.default pkgs pkgs;
        in
        overlayed.rc.version;
      expected = (import ../pkgs/rc/nightly.nix { inherit (pkgs) fetchFromGitHub; }).version;
    };

    "nixos module produces /etc/kshrc" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        builtins.hasAttr "kshrc" cfg.environment.etc;
      expected = true;
    };

    "nixos module produces /etc/profile" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        builtins.hasAttr "profile" cfg.environment.etc;
      expected = true;
    };

    "nixos module does not set global ENV" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        cfg.environment.variables.ENV or null == null;
      expected = true;
    };

    "profile sets ENV inside ksh guard" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        lib.hasInfix "export ENV=/etc/kshrc" cfg.environment.etc.profile.text;
      expected = true;
    };

    "nixos module registers shell in environment.shells" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        lib.elem "${pkgs.ksh}/bin/ksh" cfg.environment.shells;
      expected = true;
    };

    "darwin module produces /etc/kshrc" = {
      expr =
        let
          cfg =
            (evalDarwin [
              stubs.nixos
              self.darwinModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        builtins.hasAttr "kshrc" cfg.environment.etc;
      expected = true;
    };

    "darwin module produces /etc/profile" = {
      expr =
        let
          cfg =
            (evalDarwin [
              stubs.nixos
              self.darwinModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        builtins.hasAttr "profile" cfg.environment.etc;
      expected = true;
    };

    "darwin /etc/profile accepts stock macOS profile" = {
      expr =
        let
          cfg =
            (evalDarwin [
              stubs.nixos
              self.darwinModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        cfg.environment.etc.profile.knownSha256Hashes;
      expected = [ "a3fe9f414586c0d3cacbe3b6920a09d8718e503bca22e23fef882203bf765065" ];
    };

    "darwin module does not set LANG" = {
      expr =
        (darwinCfg self.darwinModules.ksh { programs.ksh.enable = true; }).environment.variables ? LANG;
      expected = false;
    };

    "darwin module does not set global ENV" = {
      expr =
        let
          cfg =
            (evalDarwin [
              stubs.nixos
              self.darwinModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        cfg.environment.variables.ENV or null == null;
      expected = true;
    };

    "home-manager module produces ~/.kshrc" = {
      expr =
        let
          cfg =
            (evalHm [
              stubs.homeManager
              self.homeManagerModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        builtins.hasAttr ".kshrc" cfg.home.file;
      expected = true;
    };

    "home-manager module produces ~/.profile" = {
      expr =
        let
          cfg =
            (evalHm [
              stubs.homeManager
              self.homeManagerModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        builtins.hasAttr ".profile" cfg.home.file;
      expected = true;
    };

    "ksh93 extra options are declared" = {
      expr =
        let
          opts =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).options.programs.ksh;
        in
        (opts ? shellOptions) && (opts ? functionsDir);
      expected = true;
    };

    "ksh93 histSize default is 10000" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        lib.hasInfix "HISTSIZE=10000" cfg.environment.etc.kshrc.text;
      expected = true;
    };

    "ksh PS1 expands variables at runtime" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        lib.hasInfix "PS1='$USER@'" cfg.environment.etc.kshrc.text;
      expected = true;
    };

    "profile contains bash guard" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        lib.hasInfix ''[ -n "''${BASH_VERSION:-}" ]'' cfg.environment.etc.profile.text;
      expected = true;
    };

    "profile contains interactive guard in kshrc" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        lib.hasInfix "case $- in" cfg.environment.etc.kshrc.text;
      expected = true;
    };

    "multi-shell profile has both guards" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
          profileText = cfg.environment.etc.profile.text;
        in
        (lib.hasInfix "KSH_VERSION" profileText) && (lib.hasInfix "BASH_VERSION" profileText);
      expected = true;
    };

    "nixos+darwin conflict is rejected" = {
      expr =
        let
          result = builtins.tryEval (
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
              self.darwinModules.ksh
              { programs.ksh.enable = true; }
            ]).config.environment.etc.kshrc.text
          );
        in
        !result.success;
      expected = true;
    };

    "lib.mkShellModule returns three modules" = {
      expr = builtins.attrNames (self.lib.mkShellModule { name = "rc"; });
      expected = [
        "darwinModule"
        "homeManagerModule"
        "nixosModule"
      ];
    };

    "rc hm module produces ~/.rcrc" = {
      expr =
        let
          cfg =
            (evalHm [
              stubs.homeManager
              self.homeManagerModules.rc
              { programs.rc.enable = true; }
            ]).config;
        in
        builtins.hasAttr ".rcrc" cfg.home.file;
      expected = true;
    };

    "rc hm module uses rc syntax" = {
      expr =
        let
          cfg =
            (evalHm [
              stubs.homeManager
              self.homeManagerModules.rc
              {
                programs.rc.enable = true;
                programs.rc.prompt = [
                  "% "
                  "  "
                ];
              }
            ]).config;
        in
        lib.hasInfix "prompt=('% ' '  ')" cfg.home.file.".rcrc".text;
      expected = true;
    };

    "rc nixos module installs package" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              { programs.rc.enable = true; }
            ]).config;
        in
        lib.elem pkgs.rc cfg.environment.systemPackages;
      expected = true;
    };

    "rc nixos module registers shell in environment.shells" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              { programs.rc.enable = true; }
            ]).config;
        in
        lib.elem "${pkgs.rc}/bin/rc" cfg.environment.shells;
      expected = true;
    };

    "rc nixos module produces /etc/rcrc" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              { programs.rc.enable = true; }
            ]).config;
        in
        builtins.hasAttr "rcrc" cfg.environment.etc;
      expected = true;
    };

    "rc darwin module produces /etc/rcrc" = {
      expr =
        let
          cfg =
            (evalDarwin [
              stubs.nixos
              self.darwinModules.rc
              { programs.rc.enable = true; }
            ]).config;
        in
        builtins.hasAttr "rcrc" cfg.environment.etc;
      expected = true;
    };

    "rc nixos+darwin conflict is rejected" = {
      expr =
        let
          result = builtins.tryEval (
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              self.darwinModules.rc
              { programs.rc.enable = true; }
            ]).config.environment.systemPackages
          );
        in
        !result.success;
      expected = true;
    };

    "rc nixos module bridges environment.shellAliases" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              {
                programs.rc.enable = true;
                environment.shellAliases.ll = "ls -l";
              }
            ]).config;
        in
        lib.hasInfix "fn ll { ls -l $* }" cfg.environment.etc.rcrc.text;
      expected = true;
    };

    "rc system module does not copy POSIX interactiveShellInit" = {
      expr = lib.hasInfix "posix-only" (
        rcrcOn (
          nixosCfg self.nixosModules.rc {
            programs.rc.enable = true;
            environment.interactiveShellInit = "posix-only";
          }
        )
      );
      expected = false;
    };

    "rc loginShellInit goes to /etc/rcrc" = {
      expr = lib.hasInfix "echo hello" (
        rcrcOn (
          darwinCfg self.darwinModules.rc {
            programs.rc.enable = true;
            programs.rc.loginShellInit = "echo hello";
          }
        )
      );
      expected = true;
    };

    "rc nixos module bridges environment.variables" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              {
                programs.rc.enable = true;
                environment.variables.EDITOR = "vim";
              }
            ]).config;
        in
        lib.hasInfix "EDITOR = 'vim'" cfg.environment.etc.rcrc.text;
      expected = true;
    };

    "rc hm module bridges home.shellAliases" = {
      expr =
        let
          cfg =
            (evalHm [
              stubs.homeManager
              self.homeManagerModules.rc
              {
                programs.rc.enable = true;
                home.shellAliases.ll = "ls -l";
              }
            ]).config;
        in
        lib.hasInfix "fn ll { ls -l $* }" cfg.home.file.".rcrc".text;
      expected = true;
    };

    "rc hm module bridges home.sessionVariables" = {
      expr =
        let
          cfg =
            (evalHm [
              stubs.homeManager
              self.homeManagerModules.rc
              {
                programs.rc.enable = true;
                home.sessionVariables.EDITOR = "vim";
              }
            ]).config;
        in
        lib.hasInfix "EDITOR = 'vim'" cfg.home.file.".rcrc".text;
      expected = true;
    };

    "rc module omits sessionVariables section when empty" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              { programs.rc.enable = true; }
            ]).config;
        in
        !(lib.hasInfix "# Session variables." cfg.environment.etc.rcrc.text);
      expected = true;
    };

    "rc alias with closing brace is rejected" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              {
                programs.rc.enable = true;
                programs.rc.shellAliases.bad = "echo } foo";
              }
            ]).config;
        in
        lib.any (a: !a.assertion) cfg.assertions;
      expected = true;
    };
    "fallback guard tests the shell version variable" = {
      expr =
        (nixosCfg (self.lib.mkPosixShellModule { name = "oksh"; }).nixosModule {
          programs.oksh.enable = true;
          programs.oksh.package = pkgs.hello;
        })._shnix.posixShells.oksh.guard;
      expected = ''[ -n "''${OKSH_VERSION:-}" ]'';
    };

    "kshrc returns early in other shells" = {
      expr = lib.hasInfix ''[ -n "''${KSH_VERSION:-}" ] || return'' (
        kshrcOn (darwinCfg self.darwinModules.ksh { programs.ksh.enable = true; })
      );
      expected = true;
    };

    "home-manager kshrc returns early in other shells" = {
      expr =
        lib.hasInfix ''[ -n "''${KSH_VERSION:-}" ] || return''
          (hmCfg self.homeManagerModules.ksh { programs.ksh.enable = true; }).home.file.".kshrc".text;
      expected = true;
    };

    "kshrc does not set noclobber" = {
      expr = lib.hasInfix "noclobber" (
        kshrcOn (nixosCfg self.nixosModules.ksh { programs.ksh.enable = true; })
      );
      expected = false;
    };

    "darwin kshrc writes programs.ksh.shellAliases" = {
      expr = lib.hasInfix "alias -- ll='ls -l'" (
        kshrcOn (
          darwinCfg self.darwinModules.ksh {
            programs.ksh.enable = true;
            programs.ksh.shellAliases.ll = "ls -l";
          }
        )
      );
      expected = true;
    };

    "darwin kshrc bridges environment.shellAliases" = {
      expr =
        let
          text = kshrcOn (
            darwinCfg self.darwinModules.ksh {
              programs.ksh.enable = true;
              environment.shellAliases = {
                la = "ls -a";
                nulled = null;
              };
            }
          );
        in
        lib.hasInfix "alias -- la='ls -a'" text && !(lib.hasInfix "nulled" text);
      expected = true;
    };

    "ksh shellOptions reach the system kshrc" = {
      expr = lib.hasInfix "set -o vi" (
        kshrcOn (
          darwinCfg self.darwinModules.ksh {
            programs.ksh.enable = true;
            programs.ksh.shellOptions = [ "vi" ];
          }
        )
      );
      expected = true;
    };

    "ksh functionsDir reaches the home-manager kshrc" = {
      expr =
        lib.hasInfix ''export FPATH="$HOME/.func''${FPATH:+:$FPATH}"''
          (hmCfg self.homeManagerModules.ksh {
            programs.ksh.enable = true;
            programs.ksh.functionsDir = "$HOME/.func";
          }).home.file.".kshrc".text;
      expected = true;
    };

    "system and home-manager options are separate" = {
      expr =
        let
          sys =
            (evalNixos [
              stubs.nixos
              self.nixosModules.ksh
            ]).options.programs.ksh;
          hm =
            (evalHm [
              stubs.homeManager
              self.homeManagerModules.ksh
            ]).options.programs.ksh;
        in
        {
          sysInitExtra = sys ? initExtra;
          sysInteractive = sys ? interactiveShellInit;
          hmInitExtra = hm ? initExtra;
          hmInteractive = hm ? interactiveShellInit;
        };
      expected = {
        sysInitExtra = false;
        sysInteractive = true;
        hmInitExtra = true;
        hmInteractive = false;
      };
    };

    "home-manager ~/.profile guards ksh login code" = {
      expr =
        let
          text =
            (hmCfg self.homeManagerModules.ksh {
              programs.ksh.enable = true;
              programs.ksh.sessionVariables.FOO = "bar";
            }).home.file.".profile".text;
        in
        lib.hasInfix ''if [ -n "''${KSH_VERSION:-}" ]; then'' text && lib.hasInfix "export FOO=bar" text;
      expected = true;
    };

    "home-manager bash receives ksh login code" = {
      expr =
        let
          cfg = hmCfg self.homeManagerModules.ksh {
            programs.ksh.enable = true;
            programs.ksh.profileExtra = "echo ksh-login";
            programs.bash.enable = true;
          };
        in
        {
          ownProfile = cfg.home.file ? ".profile";
          inBash = lib.hasInfix "echo ksh-login" cfg.programs.bash.profileExtra;
        };
      expected = {
        ownProfile = false;
        inBash = true;
      };
    };

    "rc darwin module accepts list variables" = {
      expr = lib.hasInfix "XDG_DATA_DIRS = '/a:/b'" (
        rcrcOn (
          darwinCfg self.darwinModules.rc {
            programs.rc.enable = true;
            environment.variables.XDG_DATA_DIRS = [
              "/a"
              "/b"
            ];
          }
        )
      );
      expected = true;
    };

    "rc variables expand references at runtime" = {
      expr = lib.hasInfix "P = '/etc/profiles/per-user/'^$\"USER^'/bin'\n" (
        rcrcOn (
          nixosCfg self.nixosModules.rc {
            programs.rc.enable = true;
            environment.variables.P = "/etc/profiles/per-user/\${USER}/bin";
          }
        )
      );
      expected = true;
    };

    "rc /etc/rcrc sets the NixOS environment once" = {
      expr =
        let
          text = rcrcOn (
            nixosCfg self.nixosModules.rc {
              programs.rc.enable = true;
              environment.profiles = [
                "$HOME/.nix-profile"
                "/run/current-system/sw"
              ];
              environment.profileRelativeEnvVars.PATH = [ "/bin" ];
              environment.profileRelativeEnvVars.XDG_DATA_DIRS = [ "/share" ];
              environment.homeBinInPath = true;
              environment.localBinInPath = true;
              security.wrapperDir = "/run/wrappers/bin";
            }
          );
        in
        map (l: lib.hasInfix l text) [
          "if (~ $#__NIXOS_SET_ENVIRONMENT_DONE 0) {\n  __NIXOS_SET_ENVIRONMENT_DONE = 1\n"
          ''path = ($"HOME^'/.local/bin' $"HOME^'/bin' '/run/wrappers/bin' $"HOME^'/.nix-profile/bin' '/run/current-system/sw/bin')''
          ''XDG_DATA_DIRS = $"HOME^'/.nix-profile/share:/run/current-system/sw/share''
          ''NIX_PROFILES = '/run/current-system/sw '^$"HOME^'/.nix-profile''
          "/etc/paths"
        ];
      expected = [
        true
        true
        true
        true
        false
      ];
    };

    "rc darwin /etc/rcrc takes PATH from systemPath and adds /etc/paths directories" = {
      expr =
        let
          text = rcrcOn (
            darwinCfg self.darwinModules.rc {
              programs.rc.enable = true;
              environment.systemPath = [
                "/a/bin:/b/bin"
                "/usr/bin"
              ];
            }
          );
        in
        map (l: lib.hasInfix l text) [
          "if (~ $#__NIX_DARWIN_SET_ENVIRONMENT_DONE 0) {"
          "path = ('/a/bin' '/b/bin' '/usr/bin')"
          "{/bin/cat /etc/paths /etc/paths.d/* >[2]/dev/null}"
          "if (! ~ $_d $path) path = ($path $_d)"
        ];
      expected = [
        true
        true
        true
        true
      ];
    };

    "rc ~/.rcrc sets the home-manager session environment once" = {
      expr =
        let
          text =
            (hmCfg self.homeManagerModules.rc {
              programs.rc.enable = true;
              home.sessionVariables.EDITOR = "vim";
              home.sessionPath = [ "$HOME/.local/bin" ];
              home.sessionSearchVariables.MANPATH = [ "/m" ];
            }).home.file.".rcrc".text;
        in
        lib.hasInfix ''
          if (~ $#__HM_SESS_VARS_SOURCED 0) {
            __HM_SESS_VARS_SOURCED = 1
            EDITOR = 'vim'
            if (~ $#MANPATH 0 || ~ $"MANPATH ''') { MANPATH = '/m' } else { MANPATH = '/m'^':'^$"MANPATH }
            path = ($"HOME^'/.local/bin' $path)
          }
        '' text;
      expected = true;
    };

    "rc values follow POSIX double-quote rules" = {
      expr =
        let
          text = rcrcOn (
            nixosCfg self.nixosModules.rc {
              programs.rc.enable = true;
              programs.rc.sessionVariables = {
                A = ''\$x \\ \" \a'';
                B = "\${X:-}/b";
                C = "\${X:-/d}";
                D = "\${X-$HOME/d}";
                E = "\${E:-\${HOME}/e}";
              };
            }
          );
        in
        lib.hasInfix ''
          A = '$x \ " \a'
          B = $"X^'/b'
          if (~ $#X 0 || ~ $"X ''') { _shnix_C_0 = '/d' } else { _shnix_C_0 = $"X }
          C = $"_shnix_C_0
          _shnix_C_0 = ()
          if (~ $#X 0) { _shnix_D_0 = $"HOME^'/d' } else { _shnix_D_0 = $"X }
          D = $"_shnix_D_0
          _shnix_D_0 = ()
          if (~ $#E 0 || ~ $"E ''') { _shnix_E_0 = $"HOME^'/e' } else { _shnix_E_0 = $"E }
          E = $"_shnix_E_0
          _shnix_E_0 = ()
        '' text;
      expected = true;
    };

    "rc quotes single quotes by doubling" = {
      expr = lib.hasInfix "Q = 'it''s'" (
        rcrcOn (
          nixosCfg self.nixosModules.rc {
            programs.rc.enable = true;
            programs.rc.sessionVariables.Q = "it's";
          }
        )
      );
      expected = true;
    };

    "rc history file is relative to $home" = {
      expr =
        let
          text =
            extra:
            rcrcOn
              (evalNixos [
                stubs.nixos
                self.nixosModules.rc
                { programs.rc.enable = true; }
                extra
              ]).config;
        in
        {
          default = lib.hasInfix "history=$home/'.rc_history'" (text { });
          absolute = lib.hasInfix "history='/var/h'" (text {
            programs.rc.historyFile = "/var/h";
          });
        };
      expected = {
        default = true;
        absolute = true;
      };
    };
  }
