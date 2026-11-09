# What building the Jellyfin Decoder as a mod showed us about the mod API

Written for RetroXR's developer, after "let me know if you find anything lacking in the API".

The mod is `xenu.jellyfin` (`~/gits/retroxr-jellyfin-decoder`): a VCR-like box that signs in to a Jellyfin server,
shows its libraries on the TV as a Teletext service, and plays the pick. It is built entirely as a mod, on the
VCR's own scene, with a clone of the TV remote. 428 test cases pass (pure logic, a fake Jellyfin server over real
HTTP, the object in the real game, the remote). Everything below is something that cost us code or a day, with the
size of the workaround and what would remove it. Ordered by how many mods it would help, not by how big it is.

Nothing here is a complaint: the mod API did what it says (register an object, a scene, a TV source by duck typing).
The gaps are in what the API does not say, or only says for consoles.

## 1. Rows in an OBJECT's menu (the new `menu_rows()` is for machines only) -- medium, helps every mod object

`RetroSystemModel.menu_rows()` / `set_menu_row()` (00256b3f) is what we wanted, but a mod object that is not a console
(a deck, a pod, a screwdriver, a poster) still has to build the whole panel by hand: a `FloatingObjectPanel3D` subclass,
a scene wrapping `XRToolsViewport2DIn3D`, and a 2D page built in code. Ours is **469 lines of script**
(`decoder_options_panel.gd` 131, `decoder_options_2d.gd` 338) plus two scenes, and the Synth's pod has the same trio.
The existing generic hooks (`options_info()` / `options_choices()` on `ObjectOptionsPanel`) are enough for a read-only
list, not for settings.

Proposal: the same two methods on ANY node that is an options host (`ObjectOptionsPanel` calls `menu_rows()` if the
object has it), same row dictionaries. What our menu needs that the row kinds do not have yet:

| need | where in our menu | proposed kind |
|---|---|---|
| a text field (server address, language codes, skip seconds) | `LineEdit` rows | `"input"` (`value`, `placeholder`, `numeric`) |
| a password (never shown, never saved) | `LineEdit.secret = true` | `"input"` with `"secret": true` |
| a choice whose options arrive later (the user list the server returns) | `VRDropdown.set_options()` | `"choice"` already fits: options are values |
| a button that starts something and a status line it updates | "Get a code", "Sign in", a coloured status | `"button"` and `"text"` fit; a colour (`"tone": "ok" / "warn"`) would help |
| a section that appears only in some states | sign-in page vs signed-in page | rows are re-read a few times a second: fits |

Also useful there: how to submit a field (Enter / focus lost) so a half-typed address is not sent.

## 2. A TV remote that can drive something other than the four built-in classes -- RESOLVED by 86a794ab (RemoteTarget)

Done upstream, and we moved to it: the 1,747-line clone of `tv_remote.gd` is gone; the decoder joins the group in `_init`
and answers `remote_layout` / `remote_activate` / `remote_cell_enabled` / `remote_cell_face(s)` / `remote_key_cell`
(`scripts/decoder_remote.gd`, ~100 lines), and the mod's remote object is the game's own remote plus a logo node. Two
small gaps remain (see "Left over" in the notes below): the desktop keyboard's digit and F1-F4 keys (the clone typed page
numbers with them, the base remote has no hook for a key event), and the set's keys: a deck's layout has none, so the decoder
carries cells `power`/`source`/`vol_*`/`mute` and forwards them to `connected_tv` itself; every deck mod will want the same,
so `RemoteTarget.tv_cells()` (a ready-made forwarding set for any device with a `connected_tv`) would save each of them the code.

## 3. `ApplianceModel`: dressing a model without reaching into it -- small, helps every re-skin

To turn the VCR into a different box we hide parts (`hide_part`, public: fine), adopt keys (`DeckFace.adopt_front_key`,
public: fine) and then had to:

- **force the close LOD at every distance**: LOD1/LOD2 are one Body with the cassette door baked in, so a hidden part
  still shows from 1.5 m. We call the private `model.call("_apply_ranges")` after setting `switch_distance` to 100000
  (`decoder_livery.gd:149`). Proposal: `ApplianceModel.pin_level(0)`.
- **erase printed text from the print atlas**: the atlas is a `CompressedTexture2D`, so we `get_image()`, `decompress()`
  (9.6 MB for LOD0), `fill_rect` the bands, and install a copy as a material override. It works but it is a lot of memory
  for a Quest and it needs the atlas layout by hand (`BANDS_TALL` ...). Proposal: either `ApplianceModel.blank_print(
  part, rects_in_uv)` done in a shader (a mask uniform), or let a pack ship a replacement atlas for a level.
- **find where something is printed**: we measured UVs of the BodyPrint quads (`tests/print_locate_probe.gd`). The
  contract JSON could list the print rectangles by name ("brand", "model_plate", ...).

## 4. Companions spawned together; state that survives a save -- small

- A mod object cannot ask for a second object to be spawned with it. The decoder and its remote are two spawn-menu
  entries; the player has to know. Proposal: `register_object(type, scene, {"label": ..., "with": ["xenu.jellyfin:remote"]})`.
- A mod object saves its type and pose only. Settings go in `api.store()` (right for credentials) but anything per-object
  (is it switched on, which page was it on, the VHS switch) cannot be saved with the room. Proposal: optional
  `func save_state() -> Dictionary` / `func load_state(d)` on the node, written beside the pose (values only).

## 5. Developing a mod from its own repository -- medium, helps every mod author

The loader requires `res://mods/<id>/...`, so a mod in its own repo is symlinked into a checkout
(`RetroXR/mods/xenu.jellyfin -> ~/gits/retroxr-jellyfin-decoder`). That works, and `docs/modding.md` says why. Friction:

- The checkout's class cache goes stale (`PokeWake`, `VRSlider` "not declared") until `--editor --quit` is run, which
  dirties tracked `.import` files (GLBs that are Git LFS pointers) that then have to be checked out again.
- There is no runner for a mod's tests. Ours is `tests/run_net_tests.py` (starts a fake server, a scratch settings file,
  Godot, reads the log); Tardis and the Synth have their own. A generic `Tools/mods/run_mod_tests.py <mod id> <scene>`
  with a scratch `user://` would remove three copies of the same script.
- A mod test that touches a real user's settings is easy to write by accident (the decoder goes looking for the player's
  real server): a scratch data root per test run, built into the runner, prevents it.
- `class_name` is unusable in a mod (the cache is the project's), so every cross-file reference is a `preload` constant,
  and a constant named like a native class (`VlcPlayer`) fails with "shadows a native class". Worth one line in the docs.

## 6. Documentation that is not there (docs/modding.md says nothing about these) -- small, helps every mod author

`docs/modding.md` has no mention of: writing a **video source** (the set reads `get_video_texture()` and
`get_video_stage()` by name; `AvSourceContract.REQUIRED` is only in code; a source needs three `RcaPort`s and joins
the cable graph with no registration), an **object with its own menu** (`toggle_options_ui(camera)` found by walking up
from the pointed node; `options_info()`/`options_choices()`), **extending a shipped scene** (our scene inherits
`vcr_player.tscn` with a different root script; things to know: the scene is in group `vcr_player`, which other code
treats as "a VCRPlayer", so the mod removes it; `MediaTransport` is the right base, `VCRPlayer` is not), and the
**tone mapping** (Filmic: a plain white is ~0.8 grey even unshaded). A draft of the first two is at the end of this file.

## 7. Small things

- `uid://vcrplayer_001`, `uid://vcr_opts_panel_001`, `uid://vcrclock_001` (5 references) are hand-written, not valid
  Godot UIDs. A scene that inherits `vcr_player.tscn` logs `ext_resource, invalid UID ... using text path instead` on every
  load. It works; real UIDs would silence it.
- `VlcPlayer` feature detection: an older binary of the extension lacks `set_media_options`, so a mod has to
  `has_method` each call and cannot tell the player why a cache setting did nothing. A `VlcPlayer.api_level()` (or
  `ModApi.has_feature("vlc.media_options")`) would be honest. The Android debug build runs libVLC with `-vv`, and a
  stream URL carries the token (`api_key=`, libVLC cannot send a header): worth knowing for anyone streaming from an
  authenticated server.
- Two mods now read each other by convention: the decoder answers `now_playing()` and the Synth's body joins the group
  `companion_viewer` (the decoder then loads a text track for it). It works through duck typing and groups, no API. If
  you like it, it deserves a paragraph in the docs ("conventions between mods") so the next one reuses the names.

## What we can send you now

1. **`fix/remote-hud-size` (RetroXR branch, committed, not pushed)** -- the desktop button grid of the remote now shrinks
   to the window (`TVRemote.desktop_menu_scale`, a pure function) instead of running off the top and bottom of a small
   window. 14 new cases in `tv_remote_tests` (`fit/`); the full suite is 117 passing; a mutation of the call turns two
   cases red. No API change.
2. **A docs PR** for section 6 (draft below), and section 7's UIDs if you want them.
3. **Discussion first** for 1, 2, 3 and 4: they are API shape, your call. 1 and 2 are the ones with the most use.
4. **The decoder itself** is built so it could move into the game (the player sits behind one seam so ExoPlayer can
   replace libVLC on Quest, the remote clone is marked to be unified with `tv_remote.gd`); whether you want it in the
   base game or as a mod is yours to say.

## Draft for docs/modding.md: a device that shows a picture

A deck, a streamer or a camera is a source on the A/V cable graph. It needs no registration:

- three `RcaPort` children (`VideoOut`, `AudioLOut`, `AudioROut`); `AvSource.resolve(self, true)` finds the set it is
  cabled to. Extend `MediaTransport` (power, routing, the spatial audio at the set's speakers) rather than `VCRPlayer`.
- the set reads, by name: `get_video_texture() -> Texture2D` (null = nothing to show: stopped, or no picture cord),
  `get_video_stage(tv) -> Dictionary` (`{}`, or `{"shader": Shader, "params": {...}}` -- the VHS look is a deck's stage;
  the CRT tube is the set's and applies to every source), `set_audio_volume(v)` and `set_audio_channel_mode(m)`
  (`AvSourceContract.REQUIRED`). Optional: `sends_video_to(tv)`, `set_audio_head_lock` ...
- a texture that is a `SubViewport` of your own is fine (the decoder's Teletext pages are one): redraw it with
  `UPDATE_ONCE` on change, never `UPDATE_ALWAYS` (a headless run hangs), and hand out ONE `ViewportTexture` (the set
  compares texture identity).

## Draft: an object with a menu of its own

Define `func toggle_options_ui(camera: Node3D)` on the object's root; the menu key finds it by walking up from the
pointed node. Build a `FloatingObjectPanel3D` subclass over an `XRToolsViewport2DIn3D`; let its base anchor place it
(over the object, lifted clear of its top and kept clear) -- a hand-written anchor that works for a floor-standing pod puts
the menu two metres up for a box on a table. Use `VRDropdown`, never `OptionButton` (popups die in the XR viewport) and
plain `LineEdit` (the VR keyboard is patched in for every one, `secret = true` for passwords).
