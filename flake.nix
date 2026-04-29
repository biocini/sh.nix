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
      ksh93Module = import ./modules/ksh93.nix;
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

      nixosModules.ksh = ksh93Module { shnixLib = self.lib; };
      darwinModules.ksh = ksh93Module { shnixLib = self.lib; };
      homeManagerModules.ksh = ksh93Module { shnixLib = self.lib; };
    };
}
