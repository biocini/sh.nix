# MEMO: `enableKshIntegration` is not actually usable

**To:** sh.nix maintainer  
**From:** lane-core/ksh93.nix  
**Date:** 2026-04-24  
**Re:** `home.shell.enableKshIntegration` exists as an option but no home-manager modules consume it

---

## Problem

`sh.nix` generates `home.shell.enableKshIntegration` via:

```nix
integrationOptionName = "enable${lib.toUpper (lib.substring 0 1 name + lib.substring 1 (-1) name)}Integration";
# → "enableKshIntegration"

home.shell.${integrationOptionName} = lib.mkOption { ... };
```

This creates the global option, but **no home-manager tool modules read it**.

## Evidence

### 1. No references in home-manager

```
$ rg "enableKshIntegration" ~/.cache/checkouts/github.com/nix-community/home-manager/
(no matches)
```

### 2. Tool modules use per-shell helpers

Home-manager provides typed helpers in `modules/lib/shell.nix`:

```nix
mkBashIntegrationOption = mkShellIntegrationOption "Bash";
mkFishIntegrationOption = mkShellIntegrationOption "Fish";
mkIonIntegrationOption   = mkShellIntegrationOption "Ion";
mkNushellIntegrationOption = mkShellIntegrationOption "Nushell";
mkZshIntegrationOption   = mkShellIntegrationOption "Zsh";
# No mkKshIntegrationOption
```

Each produces an option that defaults to `config.home.shell.enable<Shell>Integration`. For example, `programs.direnv`:

```nix
enableBashIntegration = lib.hm.shell.mkBashIntegrationOption { inherit config; };
enableZshIntegration  = lib.hm.shell.mkZshIntegrationOption  { inherit config; };
enableFishIntegration = lib.hm.shell.mkFishIntegrationOption { inherit config; };
# No enableKshIntegration
```

And the config side:

```nix
bash.initExtra      = mkIf cfg.enableBashIntegration  ...;
zsh.initContent     = mkIf cfg.enableZshIntegration   ...;
fish.interactiveShellInit = mkIf cfg.enableFishIntegration ...;
# No ksh.interactiveShellInit
```

### 3. The README claim is misleading

The ksh93.nix README shows:

```nix
programs.direnv = {
  enable = true;
  enableKshIntegration = true;  # This option does not exist in direnv module
};
```

Evaluating this would fail with "The option `programs.direnv.enableKshIntegration' does not exist."

## What would fix this

### Short term (documentation)

Remove or qualify the `enableKshIntegration` claim in the README. Explain that users must manually add integration code:

```nix
programs.ksh.interactiveShellInit = ''
  eval "$(direnv hook ksh)"
'';
```

### Long term (upstream home-manager)

1. Add `mkKshIntegrationOption` to `modules/lib/shell.nix`
2. Update each tool module (direnv, starship, fzf, zoxide, etc.) to:
   - Declare `enableKshIntegration`
   - Emit to `programs.ksh.interactiveShellInit`

This is the same path Nushell took — it required individual PRs to each tool module.

### Alternative (sh.nix-side)

`sh.nix` could theoretically provide a compatibility shim that watches `programs.<tool>.enableBashIntegration` and mirrors the bash init code into ksh's `interactiveShellInit`. This is fragile (not all bash code works in ksh) and probably not desirable.

---

## Recommendation

1. **Immediate:** Remove the `enableKshIntegration` example from the ksh93.nix README
2. **Short-term:** Document manual integration snippets for common tools
3. **Long-term:** Submit home-manager PR adding `mkKshIntegrationOption` and updating high-traffic modules (direnv, starship, fzf, zoxide)
