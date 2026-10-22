{pkgs}: let
  inherit (pkgs) lib;
  evaluate = options:
    lib.evalModules {
      specialArgs = {inherit pkgs;};
      modules = [
        {
          options.xdg.configFile = lib.mkOption {
            type = lib.types.attrsOf lib.types.anything;
            default = {};
          };
        }
        ../home-manager.nix
        {programs.rex-whichkey = options;}
      ];
    };
  disabled = evaluate {enable = false;};
  enabled = evaluate {
    enable = true;
    rexCli = "/test/rex";
  };
  installed = enabled.config.xdg.configFile."rex/whichkey/plugin.lua".source;
  expected =
    (import ../package.nix {
      inherit pkgs;
      rexCli = "/test/rex";
    }).plugin;
in
  assert disabled.config.xdg.configFile == {};
  assert !(enabled.config.xdg.configFile ? "rex/init.lua");
  assert toString installed == toString expected;
  assert toString enabled.config.xdg.configFile."rex/whichkey/rex-whichkey".source
  == "${enabled.config.programs.rex-whichkey.package}/bin/rex-whichkey";
    pkgs.runCommand "rex-whichkey-home-manager-check" {} ''
      test -f ${installed}
      grep -F 'local cli = "/test/rex"' ${installed}
      touch "$out"
    ''
