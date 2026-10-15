{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.rex-whichkey;
in {
  options.programs.rex-whichkey = {
    enable = lib.mkEnableOption "the Rex which-key plugin";
    rexCli = lib.mkOption {
      type = lib.types.str;
      default = "rex";
      description = "Rex CLI executable, either an absolute path or a command available in Rex's PATH.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = import ./package.nix {
        inherit pkgs;
        rexCli = cfg.rexCli;
      };
      description = "Plugin package exposing a plugin attribute containing its Lua entry point.";
    };
  };
  config = lib.mkIf cfg.enable {
    # Do not own init.lua: users may already have Rex bindings and actions there.
    xdg.configFile."rex/whichkey/plugin.lua".source = cfg.package.plugin;
  };
}
