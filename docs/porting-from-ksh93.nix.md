# Porting Guide: ksh93.nix → unified sh.nix

`ksh93.nix` has been merged into `sh.nix`. The separate repository is no longer needed. This guide covers the minimal changes required in a downstream flake.

## What changed

| Before (`ksh93.nix`)           | After (unified `sh.nix`)                   |
| ------------------------------ | ------------------------------------------ |
| `github:lane-core/ksh93.nix`   | `github:lane-core/sh.nix` (same as before) |
| `ksh93.overlays.default`       | `shnix.overlays.default`                   |
| `ksh93.nixosModules.ksh`       | `shnix.nixosModules.ksh`                   |
| `ksh93.darwinModules.ksh`      | `shnix.darwinModules.ksh`                  |
| `ksh93.homeManagerModules.ksh` | `shnix.homeManagerModules.ksh`             |
| `ksh93.packages.${system}.ksh` | `shnix.packages.${system}.ksh`             |

Everything else — overlay package names (`ksh`, `ksh-nightly`), module options (`programs.ksh.*`), and generated file paths — is unchanged.

## Step-by-step

### 1. Drop the `ksh93` input

Remove `ksh93` from `inputs`. If you were not already using `sh.nix` directly, add it:

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";

    # Before (remove these two lines):
    # ksh93.url = "github:lane-core/ksh93.nix";
    # shnix.url = "github:lane-core/sh.nix";

    # After (one input covers both):
    shnix.url = "github:lane-core/sh.nix";
  };
}
```

If you already had `shnix` as an input, simply delete the `ksh93` line.

### 2. Update the overlay reference

```nix
# Before
nixpkgs.overlays = [ ksh93.overlays.default ];

# After
nixpkgs.overlays = [ shnix.overlays.default ];
```

The overlay still provides `pkgs.ksh` and `pkgs.ksh-nightly`.

### 3. Update module imports

```nix
# Before
modules = [
  ksh93.nixosModules.ksh   # or darwinModules.ksh / homeManagerModules.ksh
];

# After
modules = [
  shnix.nixosModules.ksh   # or darwinModules.ksh / homeManagerModules.ksh
];
```

### 4. Update per-system package references (if any)

```nix
# Before
packages.ksh = ksh93.packages.${system}.ksh;

# After
packages.ksh = shnix.packages.${system}.ksh;
```

### 5. Remove stale `ksh93` from `outputs` function arguments

```nix
# Before
outputs = { self, nixpkgs, home-manager, ksh93, shnix, ... }:

# After
outputs = { self, nixpkgs, home-manager, shnix, ... }:
```

### 6. Verify

```bash
nix flake lock --update-input shnix
nix build .#ksh          # or whatever attribute you use
nix flake check
```

No `programs.ksh` options or `.kshrc` contents need to change.

## Full before/after example

### Before

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    shnix.url = "github:lane-core/sh.nix";
    ksh93.url = "github:lane-core/ksh93.nix";
  };

  outputs = { self, nixpkgs, home-manager, shnix, ksh93, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ ksh93.overlays.default ];
      };
    in {
      darwinConfigurations.mymac = nix-darwin.lib.darwinSystem {
        inherit system pkgs;
        modules = [
          ksh93.darwinModules.ksh
          ./darwin.nix
        ];
      };
    };
}
```

### After

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    shnix.url = "github:lane-core/sh.nix";
  };

  outputs = { self, nixpkgs, home-manager, shnix, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ shnix.overlays.default ];
      };
    in {
      darwinConfigurations.mymac = nix-darwin.lib.darwinSystem {
        inherit system pkgs;
        modules = [
          shnix.darwinModules.ksh
          ./darwin.nix
        ];
      };
    };
}
```
