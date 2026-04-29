{
  description = "POSIX shell modules and packages for NixOS / nix-darwin / home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    let
      kshBase = self.lib.mkPosixShellModule {
        name = "ksh";
        etcRcPath = "kshrc";
        homeRcPath = ".kshrc";
      };
      ksh93Extra = import ./modules/ksh93.nix;
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

      nixosModules.ksh = {
        imports = [
          kshBase.nixosModule
          ksh93Extra
        ];
      };

      darwinModules.ksh = {
        imports = [
          kshBase.darwinModule
          ksh93Extra
        ];
      };

      homeManagerModules.ksh = {
        imports = [
          kshBase.homeManagerModule
          ksh93Extra
        ];
      };
    };
}
