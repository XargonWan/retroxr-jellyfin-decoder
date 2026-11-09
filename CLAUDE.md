# CLAUDE.md -- Jellyfin Decoder (RetroXR mod, id `xenu.jellyfin`)

A VCR-like decoder that signs in to a Jellyfin server (Quick Connect or user + password) and
shows its libraries on the TV as a Teletext / Televideo service, then plays the pick.

**Not a Godot project on its own.** It is authored inside a RetroXR checkout, through a symlink:
`RetroXR/mods/xenu.jellyfin -> /home/xargon/gits/retroxr-jellyfin-decoder` (`RetroXR/mods/` is
gitignored there). Scenes only resolve with the game's real classes and autoloads.

## Plan

`~/.claude/plans/pasted-content-id-74c9-fammi-un-tingly-dragon.md` (Italian). Phase 1 is this
mod; phase 2 (only if the RetroXR developer approves) moves it into the base game on branch
`feat/jellyfin-decoder`.

## Layout

- `scripts/jf_api.gd` -- pure: URLs, auth header, parsing of Jellyfin JSON into rows, tracks (incl. SDH),
  `latest_rows` (a season that gained episodes is ONE row, "+N EP"), `now_playing_of`.
- `scripts/jf_pages.gd` -- pure: teletext pages, cursor, Fastext colours, 3-digit page entry, track overlay
  (pages 777 subtitles / 778 audio), renders 24 lines of 40 columns.
- `scripts/jf_subtitles.gd` -- pure: WebVTT/SRT cues, `line_at(t)` / `recent(t)`.
- `scripts/jf_config.gd` (settings file, never the password), `jf_client.gd` (REST + Quick Connect).
- `scripts/jf_player.gd` (the engine seam) + `jf_vlc_player.gd` (libVLC). ExoPlayer comes behind the same seam.
- `scripts/teletext_canvas.gd` + `teletext_view.gd` -- the page as a 512x384 SubViewport texture (UPDATE_ONCE).
- `scripts/jellyfin_decoder.gd` -- the object: a `MediaTransport` on the VCR's own scene (`scenes/jellyfin_decoder.tscn`
  inherits `vcr_player.tscn`, swaps the script, frees the tape slot). `now_playing()` is what other mods ask.
- `scripts/decoder_remote.gd` -- what the decoder tells the game's TV remote through `RemoteTarget` (layout, enabled cells,
  state faces, activation; the set's keys forwarded to `connected_tv`). `scenes/jellyfin_remote.tscn` is the game's own
  `tv_remote.tscn` plus a child running `remote_livery.gd` (the logo); no clone, no script override. Needs a game build with
  `RemoteTarget` (RetroXR commit 86a794ab or later).
- `scripts/decoder_livery.gd` + `logo_mesh.gd` + `assets/jellyfin_logo.json` -- what makes it not a VCR: parts hidden
  (Door, CassetteHolder, TapeCarrier), the print atlas wiped where RETRO XR / VIDEO CASSETTE RECORDER were (in a COPY, as
  a material override: never the GLB), a faceplate over the bay AND the old display, the logo (a quarter of the strip)
  and the LED display (three quarters). Only the close model level is drawn (LOD1/2 have the door baked in).
  `tools/make_logo_mesh.py logo.svg` rebuilds the mesh (flatten, nest, triangulate with holes, extrude; checks areas).
  The logo is the official Jellyfin one (supplied by the user): check its licence/trademark terms before publishing.
- `scripts/decoder_keys.gd` -- the five navigation keys (cross + OK, at the faceplate's RIGHT end, on the strip, as big as the model's own
  16 x 8.6 mm keys; the display ends before them): copies of the adopted PLAY VRButton with a box cap and a glyph; the transport row is the model's REW (skip back) / PLAY / FF (skip forward) / STOP caps. EJECT, PAUSE and
  REC are removed (their slots closed by `BlankPlate`). A cap's origin is its FACE: the box is moved back half its depth.
- `scripts/decoder_options_panel.gd` / `decoder_options_2d.gd` -- the TAB menu.

## Tests (run_all.py = everything, 256 cases)

Godot does not run in the Claude sandbox; go through the host (the user allows `flatpak-spawn --host`).
**The host's `/tmp` is not the sandbox's**: anything the host must write for you to read (screenshots) goes in the home
dir (`~/.cache/jf-shots`). Redirect to a file, do not pipe into grep.

```
python3 tests/run_all.py                                  # pure, client, register, decoder, remote
python3 tests/run_net_tests.py --scene tests/decoder_tests.tscn   # one of them (a .gd runs as --script)
```

`run_net_tests.py` starts `tests/fake_jellyfin.py` (sign-in both ways, views, latest, next up, seasons, episodes, an
item with 2 audio + 3 subtitle streams, the WebVTT, the video from a 12 s file ffmpeg makes), points the mod's settings
at a scratch file (`XENU_JF_SETTINGS`) and runs Godot. **Always run a decoder scene through it**: a decoder that finds
the player's real settings goes looking for their real server.

Visual probes are windowed (never `--headless`; a dummy renderer returns blank images) and draw into their own
SubViewport (the game's loading overlay sits over the main window): `teletext_render_probe`, `options_render_probe`,
`decoder_render_probe` (`OUT=dir`, `--resolution 320x240 --position 20,20`).

`SCRIPT ERROR` lines about `PokeWake` / `VRSlider` / `AsyncTextureRead` come from a stale class cache in the checkout:
`flatpak-spawn --host godot --headless --path RetroXR --editor --quit` regenerates it, and **dirties some `.import`
files** (the TV, AV switch and cassette GLBs are Git LFS pointers in this checkout): `git checkout` those afterwards.

## Git, packing and releases (rules for every RetroXR mod repo)

- `build/` and `dist/` exist locally and are **gitignored**; pack into them freely, never commit them.
- Commits are **semantic and in English** (`feat(scope): ...`, `fix: ...`, `chore:`, `docs:`, `test:`, `res:`) and carry
  **no `Co-Authored-By`** trailer and no session link.
- **Push to `main`.** A push to main runs `.github/workflows/release.yml` (the Synth mod's, reused): it packs the mod with
  `tools/pack_mod.py` and publishes release `v<version in mod.json>` with the zip attached and notes from
  `tools/release_notes.py` (feat / fix / perf commits since the previous release). It publishes only if that tag does
  not exist yet: **bump `version` in `mod.json` in the commit that should release.**
- Pack locally: `python3 tools/pack_mod.py --out build/xenu.jellyfin-<version>.zip` (reads it back the way the loader
  does; 16:9 `thumbnail.png` required). To try it in the game copy the zip to `~/retroxr/mods/`. Never publish to mod.io
  from here: the user uploads the zip.

## Rules that bit before

- `const VlcPlayer = preload(...)` shadows the native class: it is `VlcEngine`. A script that calls through an
  untyped `RefCounted` cannot use `:=` on the result: type the member (`var _player: PlayerBase`).
- A remote that is not held drops its target every frame (`_process`): a test re-assigns `_target` after each `await`.
- A node that carries its size as a SCALE (the logo) loses it if you assign `transform`: build the basis as `turn * Basis.from_scale(node.scale)`.
- Positions on the VCR model (front z = 0.135, bay y -0.0014..0.0299, big RETRO XR quad 66 x 8 mm) come from
  `tests/print_locate_probe.gd` (BodyPrint UVs), not from guessing.
- What is on is ASKED (`now_playing()`), never announced into the world as text; the TAB menu shows it.

- Who owns which effect: the TV owns the CRT tube (scanlines, mask, curvature: every source gets it); a DECK owns the VHS
  look and hands it over with `get_video_stage()` ({shader, params}; the VCR's `vcr_effect.gdshader`). The decoder gives it
  for the film only (not the pages, not the film under a chooser), switch `vhs_effect` in its menu.
- Playback reports (`/Sessions/Playing`, `/Progress`, `/Stopped`) are what make Continue watching and the watched mark work:
  `_report()` / `_report_stopped()` in the decoder, one PlaySessionId per item, a transcoded stream has its own clock
  (`_pos_offset`) so ALWAYS use `_position_s()` / `_length_s()`, never the player's. The fake server records them
  (`/_test/reports`). Not reported: a box taken out of the room mid-film (the node dies with its requests).
- A mesh built outside Godot must be wound CLOCKWISE from the front (right-hand normal AGAINST the stored one): the first logo
  had it the other way, its front faces were culled, and the letters showed as thin outlines (the walls' insides) -- misread as
  "too thin / too dim" for a while and "fixed" with brightness. `_logo()` in pure_tests checks it. Rasterise the mesh against
  `rsvg-convert` of the SVG when a shape looks wrong, before touching materials.
- The game tone-maps with Filmic (`tonemap_mode = 2`): a plain white comes out ~0.8 grey even unshaded; the logo's lettering
  is driven to 1.15, the icon left at 1.0 (two surfaces; `word_from` in the JSON; 1.8 bloomed into a halo). The probe uses the same tone mapper.
- A film that "keeps stopping" is read from the log (`~/.local/share/godot/app_userdata/RetroXR/logs/`, 5 files kept: do not
  run tests in between): `stream check` (Range honoured? speed), `no new picture for N s at T`, `the player is buffering`,
  `the player reports STOPPED`, `switching to a transcoded stream`. A seek on a direct HTTP stream needs the server to honour
  Range; behind some proxies it does not (`tests/resume_tests.tscn --no-range` is that case; the test video needs
  `+faststart` or VLC cannot even open it without Range).
- A teletext SubViewport is `UPDATE_ONCE`, never `UPDATE_ALWAYS` (hangs headless runs).
- The password is never written to disk; only the access token (`api.store()`), never in the room
  save (slots get shared).
- Log a stream URL only through `JfApi.redact()`; the token rides in `api_key=` because libVLC
  cannot send a header.
- Mutation-test new cases: break the code, watch the case go red.

## Debt on purpose

The video player: libVLC here, ExoPlayer (Media3) as a phase-2 Android backend behind the same `jf_player` interface
(a mod cannot ship an Android plugin). The remote is no longer a debt: it was a 1,747-line clone of `tv_remote.gd` until the
game gained `RemoteTarget`, and the decoder now just answers it.
