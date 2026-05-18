{ self, nixpkgs }:

let
  lib = nixpkgs.lib;
  system = "aarch64-linux";
  pkgs = nixpkgs.legacyPackages.${system};
  stubs = import ./stubs.nix { inherit pkgs lib; };

  evalNixos =
    modules:
    lib.evalModules {
      inherit modules;
      specialArgs = { inherit pkgs; };
    };

  evalDarwin =
    modules:
    lib.evalModules {
      inherit modules;
      specialArgs = { inherit pkgs; };
    };

  evalHm =
    modules:
    lib.evalModules {
      inherit modules;
      specialArgs = { inherit pkgs; };
    };
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
      expected = "unstable-2026-04-24";
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

    "darwin module sets LANG" = {
      expr =
        let
          cfg =
            (evalDarwin [
              stubs.nixos
              self.darwinModules.ksh
              { programs.ksh.enable = true; }
            ]).config;
        in
        cfg.environment.variables.LANG or null == "C.UTF-8";
      expected = true;
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
        lib.hasInfix ''PS1="''${USER}@''${HOSTNAME}:''${PWD}$ "'' cfg.environment.etc.kshrc.text;
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
        lib.hasInfix "fn ll { ls -l }" cfg.environment.etc.rcrc.text;
      expected = true;
    };

    "rc nixos module bridges environment.interactiveShellInit" = {
      expr =
        let
          cfg =
            (evalNixos [
              stubs.nixos
              self.nixosModules.rc
              {
                programs.rc.enable = true;
                environment.interactiveShellInit = "echo hello";
              }
            ]).config;
        in
        lib.hasInfix "echo hello" cfg.environment.etc.rcrc.text;
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
        lib.hasInfix "EDITOR = vim" cfg.environment.etc.rcrc.text;
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
        lib.hasInfix "fn ll { ls -l }" cfg.home.file.".rcrc".text;
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
        lib.hasInfix "EDITOR = vim" cfg.home.file.".rcrc".text;
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
  }
