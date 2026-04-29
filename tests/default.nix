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

  "overlay exposes ksh and ksh-nightly" = {
    expr = builtins.attrNames (self.overlays.default pkgs pkgs);
    expected = [
      "ksh"
      "ksh-nightly"
    ];
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

  "nixos module sets ENV" = {
    expr =
      let
        cfg =
          (evalNixos [
            stubs.nixos
            self.nixosModules.ksh
            { programs.ksh.enable = true; }
          ]).config;
      in
      cfg.environment.variables.ENV or null == "/etc/kshrc";
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

  "darwin module sets ENV and LANG" = {
    expr =
      let
        cfg =
          (evalDarwin [
            stubs.nixos
            self.darwinModules.ksh
            { programs.ksh.enable = true; }
          ]).config;
      in
      (cfg.environment.variables.ENV or null == "/etc/kshrc")
      && (cfg.environment.variables.LANG or null == "C.UTF-8");
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
}
