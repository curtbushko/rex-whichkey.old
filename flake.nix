{
  description = "Theme-aware which-key menus for Rex";

  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

  outputs = {nixpkgs, ...}: let
    systems = ["aarch64-darwin" "aarch64-linux" "x86_64-linux"];
    eachSystem = nixpkgs.lib.genAttrs systems;
    mkPackage = args: import ./nix/package.nix args;
  in {
    lib = {inherit mkPackage;};
    homeManagerModules.default = import ./nix/home-manager.nix;
    packages = eachSystem (system: let
      package = mkPackage {pkgs = nixpkgs.legacyPackages.${system};};
    in {
      default = package;
      rex-whichkey = package;
      plugin = package.plugin;
    });
    checks = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      package = mkPackage {inherit pkgs;};
      home-manager = import ./nix/tests/home-manager.nix {inherit pkgs;};
      lua-lint =
        pkgs.runCommand "rex-whichkey-lua-lint" {
          nativeBuildInputs = [pkgs.lua54Packages.luacheck];
        } ''
          cd ${./.}
          luacheck lua tests examples
          ${pkgs.lua5_1}/bin/luac -p lua/whichkey/areas.lua lua/whichkey/config.lua \
            lua/whichkey/mappings.lua lua/whichkey/plugin.lua lua/whichkey/resize.lua examples/init.lua
          touch "$out"
        '';
    });
    devShells = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      lua = pkgs.lua5_4.withPackages (ps: [ps.luautf8 ps.dkjson]);
    in {
      default = pkgs.mkShell {
        LUA51_LUAC = "${pkgs.lua5_1}/bin/luac";
        packages = [lua pkgs.go-task pkgs.alejandra pkgs.stylua pkgs.lua54Packages.luacheck pkgs.shellcheck pkgs.shfmt pkgs.coreutils pkgs.gawk];
      };
    });
    formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
