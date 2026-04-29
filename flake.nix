{
  description = "POSIX shell modules and packages for NixOS / nix-darwin / home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-unit.url = "github:nix-community/nix-unit";
    nix-unit.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-unit,
    }:
    let
      kshBase = import ./modules/ksh-base.nix { shnixLib = self.lib; };
      ksh93Extra = import ./modules/ksh93.nix;
      forAllSystems = nixpkgs.lib.genAttrs flake-utils.lib.defaultSystems;
    in
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages = {
          ksh = pkgs.callPackage ./pkgs/ksh93/stable.nix { };
          ksh-nightly = pkgs.callPackage ./pkgs/ksh93/nightly.nix { };
          default = self.packages.${system}.ksh;
        };
      }
    )
    // {
      lib = import ./lib;

      overlays.default = final: prev: {
        ksh = final.callPackage ./pkgs/ksh93/stable.nix { };
        ksh-nightly = final.callPackage ./pkgs/ksh93/nightly.nix { };
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
                --override-input shnix ${self} \
                --flake ${self}#tests
              touch $out
            '';
      });
    };
}
