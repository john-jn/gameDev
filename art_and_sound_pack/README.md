# Art and Sound Pack

Everything the art and sound members need, in one folder.

| File | For | What it is |
|---|---|---|
| [ART_GUIDE.md](ART_GUIDE.md) | Art | The list of every asset, sizes, status and rules |
| [asset_sheet.png](asset_sheet.png) | Art | One-page picture of everything needed, with today's placeholders |
| [building_sheet_spec.png](building_sheet_spec.png) | Art | How the connecting building and road sprites work |
| [templates/building_autotile_template.png](templates/building_autotile_template.png) | Art | 512 x 640 template to paint over (one per building style) |
| [templates/road_autotile_template.png](templates/road_autotile_template.png) | Art | 512 x 512 template to paint over |
| [SOUND_GUIDE.md](SOUND_GUIDE.md) | Sound | The vibe, the full list of sound effects and music, mix levels |

The PNGs can be regenerated from `tools/make_asset_sheet.gd` and `tools/make_building_sheet.gd` (run with `godot --path . --script res://tools/<name>.gd`, without `--headless`).
