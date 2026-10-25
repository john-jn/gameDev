# Tutorial video render

`demo_render.tscn` plays Evac Grid through the 3-minute demo script with captions,
then quits. Rendered with Godot's Movie Maker it produces
`demo_output/evac_grid_tutorial.avi` (30 fps, set under `[editor]` in project.godot).

1. Open `demo/demo_render.tscn` in the editor.
2. Turn on Movie Maker mode (film-strip icon, top right).
3. Run Current Scene (F6) and let it finish; the window closes by itself.

Normal play (`scenes/main.tscn`) never loads anything from this folder.
