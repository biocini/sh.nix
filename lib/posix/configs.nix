{ envBridge, guards }:

let
  # NixOS and nix-darwin share one config; only the bridge differs.
  system =
    bridge:
    { name }:
    {
      config,
      lib,
      cfg,
      ...
    }:
    let
      env = bridge { inherit config; };
    in
    {
      environment.shells = [ "${cfg.package}${cfg.package.passthru.shellPath or "/bin/${name}"}" ];
      programs.${name} = {
        interactiveShellInit = env.interactiveShellInit;
        shellAliases = lib.mkDefault env.shellAliases;
      };
    };
in
{
  nixos = system envBridge.nixos;
  darwin = system envBridge.darwin;

  hm =
    { name }:
    {
      config,
      lib,
      cfg,
      ...
    }:
    let
      env = envBridge.homeManager { inherit config; };

      sessionVariablesStr = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg (toString v)}") cfg.sessionVariables
      );

      # Login code for this shell only. ~/.profile is read by every POSIX
      # login shell, so the block runs behind the shell guard.
      body = lib.concatStringsSep "\n" (
        lib.filter (s: s != "") [
          sessionVariablesStr
          cfg.profileExtra
        ]
      );
      profileBlock = lib.optionalString (body != "") ''
        if ${guards.guardFor lib name}; then
        ${body}
        fi
      '';

      # home-manager programs.bash owns ~/.profile when it is enabled.
      bashOwnsProfile = config.programs.bash.enable or false;
    in
    lib.mkMerge [
      {
        programs.${name} = {
          shellAliases = lib.mkDefault env.shellAliases;
          initExtra = lib.mkIf (cfg.logoutExtra != "") (
            lib.mkAfter ''
              trap ". $HOME/.${name}_logout" EXIT
            ''
          );
        };
        home.file.".${name}_logout" = lib.mkIf (cfg.logoutExtra != "") {
          text = ''
            # ~/.${name}_logout: DO NOT EDIT -- this file has been generated automatically.

            ${cfg.logoutExtra}
          '';
        };
      }
      (lib.mkIf bashOwnsProfile {
        programs.bash.profileExtra = lib.mkIf (profileBlock != "") (lib.mkAfter profileBlock);
      })
      (lib.mkIf (!bashOwnsProfile) {
        home.file.".profile".text = ''
          # ~/.profile: DO NOT EDIT -- this file has been generated automatically.

          . "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh"

          ${profileBlock}
        '';
      })
    ];
}
