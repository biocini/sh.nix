# Agent Instructions — sh.nix

## Testing

Run the nix-unit test suite before submitting changes:

```bash
nix eval --impure --expr '
  let flake = builtins.getFlake "'$(pwd)'";
  in map (n: { name = n; pass = flake.tests."${n}".expr == flake.tests."${n}".expected; })
       (builtins.attrNames flake.tests)
'
```

All tests live in `tests/default.nix`. Add tests for:

- New module outputs or options
- Generated file content changes
- Overlay changes
- Library API changes

Tests use stub modules (`tests/stubs.nix`) to provide minimal NixOS-like and home-manager-like option declarations for `lib.evalModules`. Do not import full nixpkgs modules in tests.

## Module Composition

Each shell exposes three modules: `nixosModules.<name>`, `darwinModules.<name>`, `homeManagerModules.<name>`.

- **nixosModule and darwinModule are mutually exclusive** — importing both for the same shell triggers an assertion failure. This is by design: they both write `/etc/profile` and `/etc/<name>rc` with incompatible semantics.
- **homeManagerModule composes with either** system module. It writes `~/.<name>rc` and `~/.profile` and does not conflict.

The module composition pattern in `flake.nix` must remain:

```nix
nixosModules.ksh = { ... }: {
  imports = [ kshBase.nixosModule ksh93Extra ];
};
```

Do **not** inline `mkPosixShellModule` in `flake.nix` — the returned functions must be imported from a separate file (`modules/ksh-base.nix`) so NixOS module file tracking works correctly. Inlining causes "option already declared" errors when both modules are present.

## CI Workflows

`.github/workflows/update-ksh93-*.yml` run daily and commit directly to master.

- They use `set -euo pipefail` and hash validation (`[[ "$hash" =~ ^sha256-[A-Za-z0-9+/=]+$ ]]`)
- Nightly pins to commit SHA (not mutable `dev` ref) with a change guard
- Do not modify `packages/` directly; let the workflows handle version bumps

## Commit Attribution

Footer must read: `Generated-with: Nina (kimi-coding/kimi-for-coding) via pi`
