{ envBridge }:

{
  nixos =
    { name, etcRcPath }:
    {
      config,
      lib,
      pkgs,
      cfg,
    }:
    let
      env = envBridge.nixos { inherit config; };
    in
    {
      environment.variables.ENV = lib.mkDefault "/etc/${etcRcPath}";
      programs.${name} = {
        shellInit = ''
          if [ -z "$__NIXOS_SET_ENVIRONMENT_DONE" ]; then
            . ${config.system.build.setEnvironment}
          fi
          ${env.shellInit}
        '';
        loginShellInit = env.loginShellInit;
        interactiveShellInit = env.interactiveShellInit;
        shellAliases = lib.mkDefault env.shellAliases;
      };
    };

  darwin =
    { name, etcRcPath }:
    {
      config,
      lib,
      pkgs,
      cfg,
    }:
    let
      env = envBridge.darwin { inherit config; };
    in
    {
      environment.variables.ENV = lib.mkDefault "/etc/${etcRcPath}";
      environment.variables.LANG = lib.mkDefault "C.UTF-8";
      programs.${name} = {
        shellInit = ''
          if [ -z "$__NIX_DARWIN_SET_ENVIRONMENT_DONE" ]; then
            . ${config.system.build.setEnvironment}
          fi
          ${env.shellInit}
        '';
        loginShellInit = env.loginShellInit;
        interactiveShellInit = env.interactiveShellInit;
      };
    };

  hm =
    { name }:
    {
      config,
      lib,
      pkgs,
      cfg,
    }:
    let
      env = envBridge.homeManager { inherit config; };
    in
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
    };
}
