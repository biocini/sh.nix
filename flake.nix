{
  description = "POSIX shell modules and packages for NixOS / nix-darwin / home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-unit,
    }:
    let
      kshBase = import ./modules/ksh-base.nix { shnixLib = self.lib; };
      ksh93Extra = import ./modules/ksh93.nix;
      rcModule = import ./modules/rc.nix { shnixLib = self.lib; };
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          ksh = pkgs.callPackage ./pkgs/ksh93/stable.nix { };
          ksh-nightly = pkgs.callPackage ./pkgs/ksh93/nightly.nix { };
          rc = pkgs.callPackage ./pkgs/rc/default.nix { };
          default = self.packages.${system}.ksh;
        }
      );

      lib = import ./lib;

      overlays.default = final: prev: {
        ksh = final.callPackage ./pkgs/ksh93/stable.nix { };
        ksh-nightly = final.callPackage ./pkgs/ksh93/nightly.nix { };
        rc = final.callPackage ./pkgs/rc/default.nix { };
      };

      nixosModules.ksh =
        { ... }:
        {
          imports = [
            kshBase.nixosModule
            ksh93Extra
          ];
        };

      darwinModules.ksh =
        { ... }:
        {
          imports = [
            kshBase.darwinModule
            ksh93Extra
          ];
        };

      homeManagerModules.ksh =
        { ... }:
        {
          imports = [
            kshBase.homeManagerModule
            ksh93Extra
          ];
        };

      nixosModules.rc = rcModule.nixosModule;
      darwinModules.rc = rcModule.darwinModule;
      homeManagerModules.rc = rcModule.homeManagerModule;

      tests = import ./tests { inherit self nixpkgs; };

      checks = forAllSystems (system: {
        nix-unit =
          nixpkgs.legacyPackages.${system}.runCommand "nix-unit-tests"
            {
              nativeBuildInputs = [ nix-unit.packages.${system}.default ];
            }
            ''
              export HOME=$(realpath .)
              nix-unit --eval-store "$HOME" \
                --extra-experimental-features flakes \
                --override-input nixpkgs ${nixpkgs} \
                --override-input nix-unit ${nix-unit} \
                --flake ${self}#tests
              touch $out
            '';
      });
    };
}
