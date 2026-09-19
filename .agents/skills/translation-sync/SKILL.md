---
name: translation-sync
description: Keep the Immersive Identification string tables in sync across languages. Invoke this WHENEVER you add, rename, remove, or move any MCM/UI string in gamedata/configs/text/ (or the FOMOD components' text/ dirs) — including option labels (ui_mcm_ii_*), tooltips (*_desc), sidebar page labels (ui_mcm_menu_<page>), preset names (ui_mcm_prst_*), dropdown values (<page>_<opt>_lst_<label>), or faction/rank strings. The mod ships English + Russian; every id must exist in both, the Russian files are windows-1251 encoded, and several id families are PATH-DERIVED so they silently break when an option's MCM page changes.
---

# Translation sync (eng ⇄ rus)

The mod ships **English and Russian** string tables. Every `<string id>` must exist in **both**
files of each pair, and the Russian files are **windows-1251** encoded (Cyrillic). Strings are
easy to add/rename in `eng` only and forget `rus`, or to break a path-derived id — the symptom
in-game is a **raw id shown instead of text**.

## The file pairs

| eng | rus |
|---|---|
| `gamedata/configs/text/eng/st_ii_texts.xml` | `.../rus/st_ii_texts.xml` |
| `WD Compatibility/gamedata/configs/text/eng/st_ii_wd.xml` | `.../rus/st_ii_wd.xml` |
| `Perception Skill Integration/gamedata/configs/text/eng/st_ii_skill_perception_texts.xml` | `.../rus/...` |

## The check — run it after ANY string edit

```
nix run .#check-i18n
```

Verifies id parity (nothing in eng missing from rus, no orphans) **and** the windows-1251
declaration, for every pair. Must pass. (Also run `nix run .#check-xml` — a bare `--` inside an
XML comment crashes the loader.)

## Editing the windows-1251 Russian files

`grep`/`cat` treat them as binary. To **read**: `grep -a ... FILE | iconv -f windows-1251 -t utf-8`.
To **write** new Cyrillic strings, encode as cp1251 — do NOT save UTF-8 (it corrupts the file).
Reliable pattern:

```bash
nix shell nixpkgs#python3 --command python3 - <<'PY'
f="gamedata/configs/text/rus/st_ii_texts.xml"
s=open(f,encoding="cp1251").read()
anchor='<string id="ui_mcm_ii_SOMETHING_desc">'   # insert relative to an existing line
new='\t<string id="ui_mcm_ii_NEW"><text>Русский текст</text></string>\n'
# ...splice `new` next to the anchor line, keeping tabs/order matching eng...
open(f,"w",encoding="cp1251").write(s)
PY
```

Translate for real (idiomatic STALKER terminology) — don't leave English text in a rus `<text>`.

## The id families that silently break (MCM string-id rules)

These are **path-derived** — moving an option to a different MCM page changes its id:

- **Option label + tooltip**: `ui_mcm_<hint>` and `ui_mcm_<hint>_desc`. `hint` is usually
  `ii_<option_id>`. The label is the bare id; the tooltip is `..._desc`. (Never set `hint =
  "..._desc"` — that shows the description AS the caption.)
- **Dropdown/list values**: `<full_menu_path_with_/_as_>_<option_id>_lst_<label>`. E.g.
  `ui_style` on `uistyle/general` → `ii_uistyle_general_ui_style_lst_card`. **Move the option to a
  different page → every `_lst_` id changes** and must be renamed in both languages.
- **Sidebar page labels**: `ui_mcm_menu_<page_id>` — one per page AND sub-page (e.g. `hipfire`,
  `bodycam`, `crooks`). Add a new page → add this string, or the sidebar shows the raw id.
- **Preset names**: `ui_mcm_prst_<preset_id>`, matching `presets_ii.ltx` sections.
- **Page content header**: an `opt_title("ui_mcm_ii_<page>_title")` — a separate literal id.

## Workflow when you touch strings

1. Make the change in the **English** file.
2. Mirror **every** added/renamed/removed id in the **Russian** file (translated, cp1251).
3. If you renamed/moved an MCM **option's page**, re-derive and fix its `_lst_` value ids in both.
4. If you added an MCM **page/sub-page**, add its `ui_mcm_menu_<page>` label in both.
5. `nix run .#check-i18n` and `nix run .#check-xml` — both must pass.

See the user's `stalker-modding` skill (`references/mcm-and-ui.md`) for the full MCM string-id
resolution rules and the nesting path model.
