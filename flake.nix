{
  description = "Dev shell for the Immersive Identification S.T.A.L.K.E.R. Anomaly/GAMMA mod: XML validation (this engine's UI/config XML comments reject a bare `--`, which xmllint catches instantly and eyeballing repeatedly missed), a Lua language server wired up against types/ (EmmyLua stubs for the engine's exposed Lua API, hand-extracted and cited against xray-monolith's C++ source), and FOMOD packaging via 7-Zip.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
      pkgsFor = system: import nixpkgs { inherit system; };
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShell {
            packages = [
              pkgs.libxml2 # xmllint -- validate gamedata/**/*.xml and fomod/*.xml
              pkgs.lua-language-server # reads .luarc.json + types/ in this repo
              pkgs.lua5_1 # `lua` / `luac` -- Lua 5.1, matching this engine's embedded runtime
              pkgs.p7zip # `7z` -- build the FOMOD zip for distribution
            ];

            shellHook = ''
              echo "immersive-identification dev shell"
              echo "  nix run .#check-xml           # validate every XML file in the repo"
              echo "  nix run .#check-lua           # full Lua diagnostics via lua-language-server"
              echo "  nix run .#package             # build immersive-identification-fomod-v<VERSION>.zip"
              echo "  luac -p gamedata/scripts/*.script   # Lua 5.1 syntax check"
              echo "  lua-language-server --version # point your editor's LSP client at this repo"
            '';
          };
        });

      apps = forAllSystems (system:
        let
          pkgs = pkgsFor system;
        in
        {
          check-xml = {
            type = "app";
            program = toString (pkgs.writeShellScript "check-xml" ''
              set -euo pipefail
              status=0
              while IFS= read -r -d "" f; do
                echo "== $f =="
                "${pkgs.libxml2}/bin/xmllint" --noout "$f" || status=1
              done < <(find gamedata fomod "FactionID Neutralized" "Perception Skill Integration" -name "*.xml" -print0)
              if [ "$status" -eq 0 ]; then
                echo "All XML valid."
              fi
              exit "$status"
            '');
          };

          check-lua = {
            type = "app";
            program = toString (pkgs.writeShellScript "check-lua" ''
              set -euo pipefail
              "${pkgs.lua-language-server}/bin/lua-language-server" \
                --check="$(pwd)" \
                --checklevel=Warning \
                --check_format=pretty
            '');
          };

          package = {
            type = "app";
            program = toString (pkgs.writeShellScript "package" ''
              set -euo pipefail
              version="$("${pkgs.libxml2}/bin/xmllint" --xpath 'string(//Version)' fomod/info.xml)"
              if [ -z "$version" ]; then
                echo "error: could not read <Version> from fomod/info.xml" >&2
                exit 1
              fi
              out="./package/immersive-identification-fomod-v''${version}.zip"
              rm -f "$out"
              "${pkgs.p7zip}/bin/7z" a -tzip -x'!.gitkeep' "$out" fomod gamedata README.md "FactionID Neutralized" "Perception Skill Integration"
              echo "built $out"
            '');
          };
        });
    };
}
