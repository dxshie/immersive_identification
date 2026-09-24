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
              pkgs.stylua # format the .script (Lua) sources; config in stylua.toml
              pkgs.p7zip # `7z` -- build the FOMOD zip for distribution
            ];

            shellHook = ''
              echo "immersive-identification dev shell"
              echo "  nix run .#check-xml           # validate every XML file in the repo"
              echo "  nix run .#check-lua           # full Lua diagnostics via lua-language-server"
              echo "  nix run .#format              # StyLua-format every .script (Lua) source"
              echo "  nix run .#check-format        # verify .script formatting (CI-friendly)"
              echo "  nix run .#check-i18n          # verify eng/rus string-table parity + encoding"
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
              done < <(find gamedata fomod examples "FactionID Neutralized" "GAMMA Patches" "GRIP Patches" "HD Faction Patches" "Perception Skill Integration" "WD Compatibility" -name "*.xml" -print0)
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

          # StyLua globs *.lua by default; this engine's sources are *.script
          # (Lua 5.1), so both apps collect them explicitly. Config: stylua.toml.
          format = {
            type = "app";
            program = toString (pkgs.writeShellScript "format" ''
              set -euo pipefail
              find gamedata examples "FactionID Neutralized" "GAMMA Patches" "GRIP Patches" "HD Faction Patches" "Perception Skill Integration" "WD Compatibility" \
                -name "*.script" -print0 \
                | xargs -0 -r "${pkgs.stylua}/bin/stylua"
              echo "Formatted all .script files."
            '');
          };

          check-format = {
            type = "app";
            program = toString (pkgs.writeShellScript "check-format" ''
              set -euo pipefail
              find gamedata examples "FactionID Neutralized" "GAMMA Patches" "GRIP Patches" "HD Faction Patches" "Perception Skill Integration" "WD Compatibility" \
                -name "*.script" -print0 \
                | xargs -0 -r "${pkgs.stylua}/bin/stylua" --check
              echo "All .script files are formatted."
            '');
          };

          # Translation parity: every <string id> in each English string-table must have a
          # counterpart in the sibling Russian file (and vice-versa), and the Russian files must
          # stay windows-1251 encoded. Catches the recurring drift when strings are added/renamed
          # (esp. path-derived list-value ids and ui_mcm_menu_<page> labels) but only in `eng`.
          check-i18n = {
            type = "app";
            program = toString (pkgs.writeShellScript "check-i18n" ''
              set -euo pipefail
              status=0
              while IFS= read -r -d "" eng; do
                rus="''${eng/\/eng\//\/rus\/}"
                if [ ! -f "$rus" ]; then
                  echo "MISSING Russian file for: $eng" >&2; status=1; continue
                fi
                # grep -a: the rus files are windows-1251 (Cyrillic), which grep treats as binary.
                miss="$(comm -23 <(grep -aoE 'id="[^"]+"' "$eng" | sort -u) <(grep -aoE 'id="[^"]+"' "$rus" | sort -u))"
                orph="$(comm -13 <(grep -aoE 'id="[^"]+"' "$eng" | sort -u) <(grep -aoE 'id="[^"]+"' "$rus" | sort -u))"
                if [ -n "$miss" ]; then echo "== $rus: MISSING (in eng, not rus) =="; echo "$miss"; status=1; fi
                if [ -n "$orph" ]; then echo "== $rus: ORPHAN (in rus, not eng) =="; echo "$orph"; status=1; fi
                if ! head -1 "$rus" | grep -qi 'windows-1251'; then
                  echo "== $rus: expected windows-1251 XML declaration =="; status=1
                fi
              done < <(find gamedata examples "FactionID Neutralized" "GAMMA Patches" "GRIP Patches" "HD Faction Patches" "Perception Skill Integration" "WD Compatibility" -path "*/text/eng/*.xml" -print0)
              if [ "$status" -eq 0 ]; then echo "All string tables in eng/rus parity."; fi
              exit "$status"
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
              "${pkgs.p7zip}/bin/7z" a -tzip -x'!.gitkeep' "$out" fomod gamedata README.md "FactionID Neutralized" "GAMMA Patches" "GRIP Patches" "HD Faction Patches" "Perception Skill Integration" "WD Compatibility"
              echo "built $out"
            '');
          };
        });
    };
}
