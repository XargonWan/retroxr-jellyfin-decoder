JELLYFIN DECODER
================

Summary
-------
Connect your Jellyfin server to your TV, the old-school way. The Jellyfin Decoder is a VCR-style box
that signs in to your server and shows your whole library on the TV as a Teletext page: recently added,
what's next, continue watching, search, and every library. Pick a film or episode and it plays on the TV,
with audio and subtitle choices from the remote.

Description
-----------
The decoder is a box you spawn from the Objects tab of the spawn menu, next to a remote of its own
("Jellyfin Decoder Remote"). Cable its video and audio sockets to a TV the way you would a VCR, switch it on,
and it starts working.

Signing in
  Open the decoder's menu (point at it and press the left stick, or Tab on a computer). Type your server's
  address, then choose one of two ways in:
  - Quick Connect: the box shows a six-digit code on the TV. Type it on a device where you are already
    signed in to Jellyfin (Settings > Quick Connect). Quick Connect has to be switched on on your server.
  - User and password: pick your user from the list the server gives you and type the password. The password
    is never saved; the box keeps only the login token the server hands back.

The TV
  Page 100 is the index. From there:
  - Recently added (101): what is newest on your server. Several new episodes of one season are one line
    ("+3 EP") that opens the season.
  - What's next (102): the next episodes of the shows you watch.
  - Continue watching (103): films and episodes you left half way. Playing one picks up where you stopped.
  - Search (104): an on-screen keyboard in Teletext. Move with the arrows, OK types a letter, DEL rubs out
    one, CLEAR empties, SEARCH looks it up, BACK cancels. Digits on the remote type digits.
  - Every library on your server (110 and up). Series open to their seasons, seasons to their episodes.

Playing
  - OK starts an item. Playing, the remote's left and right skip back and forward (10 and 30 seconds by
    default, changed in the menu). PREV and NEXT go to the previous and next episode.
  - AUDIO and SUBTITLE cycle through the tracks; AUDIO LIST and SUB LIST open a chooser over the picture.
    Typing 778 or 777 on the remote opens the same choosers.
  - The picture gets a VHS look like the VCR's. You can switch it off in the menu.
  - The box tells your server what you are watching, as every Jellyfin app does, so Continue watching and
    your watched marks stay right.

On the box
  The front has the Jellyfin logo, a long LED display that says what is playing (the series, season and
  episode, and a counter), a cross of arrow keys with OK, the skip, play and stop keys, and the power switch.

Things to know
  - It needs a Jellyfin server you can reach from the room. Over the internet it works best with a stable
    connection; a film that keeps stopping is usually the connection, and the box switches to a transcoded
    stream on its own when the picture freezes.
  - Your password is never saved. The server address and the login token are, in the mod's own settings
    file, not in the room save.
  - Only the Jellyfin server you sign in to is contacted.

-----------------------------------------------------------------------------------------
TECHNICAL NOTES (for the curious, and for other mod authors)
-----------------------------------------------------------------------------------------

Files
  mod.json                  the manifest (id xenu.jellyfin)
  mod_main.gd               registers the decoder and its remote as objects
  scripts/jf_api.gd         pure: URLs, the auth header, parsing of Jellyfin's replies
  scripts/jf_pages.gd       pure: the Teletext pages, cursor, Fastext keys, the on-screen keyboard
  scripts/jf_subtitles.gd   pure: WebVTT / SRT cues, for the companion's line
  scripts/jf_client.gd      the REST client and Quick Connect
  scripts/jf_config.gd      the settings file (never the password)
  scripts/jf_player.gd      the video engine seam; jf_vlc_player.gd is libVLC behind it
  scripts/teletext_*.gd     the 40 x 24 page as a SubViewport texture
  scripts/jellyfin_decoder.gd  the object: a MediaTransport on the VCR's own scene
  scripts/decoder_remote.gd, remote_livery.gd  the game's own TV remote drives the decoder (RemoteTarget); the logo on it
  scripts/decoder_keys.gd, decoder_livery.gd, logo_mesh.gd  the front and the keys
  scripts/decoder_options_*.gd the TAB menu
  assets/jellyfin_logo.json    the logo, extruded from the official SVG (tools/make_logo_mesh.py)
  tests/                    the test suite (run_all.py; a fake Jellyfin server stands in for the real one)

Server endpoints used
  /System/Info/Public, /Users/Public, /QuickConnect/{Enabled,Initiate,Connect}, /Users/AuthenticateWithQuickConnect,
  /Users/AuthenticateByName, /Users/{id}/Views, /Users/{id}/Items (+ searchTerm), /Users/{id}/Items/Latest,
  /Users/{id}/Items/Resume, /Shows/NextUp, /Shows/{id}/Seasons, /Shows/{id}/Episodes, /Videos/{id}/stream,
  /Videos/{id}/master.m3u8, /Videos/{id}/{source}/Subtitles/{n}/0/Stream.vtt, /Sessions/Playing{,/Progress,/Stopped}.

Playback
  - A direct stream is checked when it starts (does the server honour HTTP Range requests, and how fast does it
    answer). If it does not, or the picture stalls for six seconds, playback switches to the server's transcoded
    stream from the same place.
  - libVLC's network cache is 1.5 s for local addresses and 5 s for everything else (set per open where the
    engine supports it).
  - The login token travels in the stream URL as api_key, because libVLC cannot send headers.

Tests
  python3 tests/run_all.py  -- pure logic, the REST client over real HTTP against tests/fake_jellyfin.py, the
  object and its remote in the game, and a server that ignores Range requests. Run with Godot 4.7.2.

Needs
  - A RetroXR build that has RemoteTarget (the remote's device protocol): the game's TV remote then drives the decoder.

Not yet done
  - Tested on desktop only. Not yet run on a headset or on Quest; the Quest will use a different video engine
    (ExoPlayer) later.
  - No cover art: text only, by design for now.
  - The decoder's model is the VCR's, dressed; it has no model of its own.
