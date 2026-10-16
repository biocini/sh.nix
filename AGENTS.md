# Agent Instructions — sh.nix

## Architecture

This project provides composable building blocks for shell module authors, not a monolithic framework.

- **`lib.mkShellModule`** — the universal assembler; knows nothing about shell syntax
- **`lib.envBridge`** — pure data extraction from `config.environment.*` / `config.home.*`
- **`lib/posix/`** — decomposed POSIX-family helpers (options, configs, file generators) consumed by `mkPosixShellModule`

New shells should use `envBridge` for all global environment integration. Do not reach into `config.environment.*` directly. See `docs/implementing-a-shell.md` for the downstream implementer guide.

## Supported shells

- **ksh93** (POSIX) — `modules/ksh-base.nix` + `modules/ksh93.nix`
- **rc** (non-POSIX) — `modules/rc.nix`, reference implementation using `mkShellModule` + `envBridge`

## Testing

The sole means of testing this flake during development is through the `nix flake` interface:

```bash
nix flake check
```

All tests live in `tests/default.nix`. Add tests for:

- New module outputs or options
- Generated file content changes
- Overlay changes
- Library API changes
- Environment bridge flows (aliases, variables, init scripts)

Tests use stub modules (`tests/stubs.nix`) to provide minimal NixOS-like and home-manager-like option declarations for `lib.evalModules`. Do not import full nixpkgs modules in tests. A stub option must accept every value type that the upstream option accepts. For example, nix-darwin sets list values in `environment.variables`.

**nix-unit naming**: Attribute names in `tests/default.nix` must start with `test` for nix-unit to discover them. The `lib.mapAttrs'` wrapper in `tests/default.nix` handles this automatically.

## Module Composition

Each shell exposes three modules: `nixosModules.<name>`, `darwinModules.<name>`, `homeManagerModules.<name>`.

- **nixosModule and darwinModule are mutually exclusive** — importing both for the same shell triggers an assertion failure. The two modules write the same `/etc` files with platform-specific content.
- **homeManagerModule composes with either** system module. It writes only files in `$HOME`. A POSIX shell writes `~/.<name>rc` and `~/.profile`; when home-manager `programs.bash` is enabled, it adds its login code to `programs.bash.profileExtra` and does not write `~/.profile`.

The module composition pattern in `flake.nix` must remain:

```nix
nixosModules.ksh = { ... }: {
  imports = [ kshBase.nixosModule ksh93Extra ];
};
```

Do **not** inline `mkPosixShellModule` in `flake.nix` — the returned functions must be imported from a separate file (`modules/ksh-base.nix`) so NixOS module file tracking works correctly. Inlining causes "option already declared" errors when both modules are present.

## CI Workflows

`.github/workflows/update-ksh93-*.yml` and `.github/workflows/update-rc-nightly.yml` run daily and commit directly to master.

- They use `set -euo pipefail` and hash validation (`[[ "$hash" =~ ^sha256-[A-Za-z0-9+/=]+$ ]]`)
- Nightly pins to commit SHA (not mutable `dev` ref) with a change guard
- Each workflow builds the updated package and runs `nix flake check` before it pushes
- `.github/workflows/check.yml` builds all packages and runs `nix flake check` on x86_64-linux, aarch64-linux and aarch64-darwin for each push to master and each pull request
- The workflows edit `pkgs/ksh93/stable.nix`, `pkgs/ksh93/nightly.nix` and `pkgs/rc/nightly.nix` with `sed`. Each of these files must contain exactly one `version = "…";`, one `hash = "…";` and (nightly) one `rev = "…";` line. Put shared build code in `pkgs/ksh93/generic.nix`.
- Do not change versions or hashes in `pkgs/` by hand; let the workflows do version updates
- Tests must not contain package versions, because the workflows change them
