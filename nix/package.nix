{
  pkgs,
  rexCli ? "rex",
}: let
  lua = pkgs.lua5_4.withPackages (ps: [ps.luautf8 ps.dkjson]);
  library = ../lua/whichkey;
  helper = pkgs.writeShellApplication {
    name = "rex-whichkey";
    runtimeInputs = [pkgs.coreutils pkgs.gawk];
    extraShellCheckFlags = ["--external-sources"];
    text =
      builtins.replaceStrings
      ["@REX_WHICHKEY_DIRECTORY@" "@REX_WHICHKEY_LUA@"]
      ["${library}" "${lua}/bin/lua"]
      (builtins.readFile ../lua/whichkey/helper.sh);
    derivationArgs.postCheck = ''
      LUA_PATH="${library}/?.lua;;" ${lua}/bin/lua ${../tests/rex_layout.lua}
      REX_WHICHKEY_LUA_DIR="${library}" ${lua}/bin/lua ${../tests/rex_height.lua}
      LUA_PATH="${library}/?.lua;;" ${lua}/bin/lua ${../tests/rex_mappings.lua}
      REX_WHICHKEY_LUA_DIR="${library}" ${lua}/bin/lua ${../tests/rex_areas.lua}
      REX_WHICHKEY_LUA_DIR="${library}" ${lua}/bin/lua ${../tests/rex_plugin.lua}
      ${pkgs.bash}/bin/bash ${../tests/rex_theme_test.sh} ${library}/theme.sh
      REX_WHICHKEY_TEST_TRASH="$TMPDIR/.trash" ${pkgs.bash}/bin/bash ${../tests/rex_whichkey_test.sh} "$target"
    '';
  };
  plugin = pkgs.writeText "rex-whichkey-plugin.lua" (builtins.replaceStrings
    ["\"@REX_WHICHKEY_DIRECTORY@\"" "\"@REX_WHICHKEY_COMMAND@\"" "\"@REX_CLI@\""]
    [(builtins.toJSON "${library}") (builtins.toJSON "${helper}/bin/rex-whichkey") (builtins.toJSON rexCli)]
    (builtins.readFile ../lua/whichkey/plugin.lua));
in
  helper // {inherit plugin;}
