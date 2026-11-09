#!/usr/bin/env python3
"""Every test of the mod, in order. Exit code 0 only if all pass.

    python3 tests/run_all.py            # Godot through flatpak-spawn --host (HOST=0 to run it directly)

Pure logic first (no server), then the REST client, then the objects in the real game. The fake Jellyfin
server and a scratch settings file are made for each run; the player's real settings are never touched.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64"))
PROJECT = os.environ.get("RETROXR_PROJECT", os.path.expanduser("~/gits/RetroXR-xargon/RetroXR"))


def pure() -> int:
    host = os.environ.get("HOST", "1") == "1"
    cmd = ([ "flatpak-spawn", "--host"] if host else []) + [GODOT, "--headless", "--path", PROJECT, "--script",
           "res://mods/xenu.jellyfin/tests/pure_tests.gd"]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=180)
    for line in (out.stdout + out.stderr).splitlines():
        if "[jf-test]" in line:
            print(line)
    return out.returncode


def main() -> int:
    results = [("pure_tests", pure())]
    for script, extra in [("tests/client_tests.gd", []), ("tests/register_tests.tscn", []), ("tests/decoder_tests.tscn", []),
            ("tests/resume_tests.tscn", ["--no-range"]), ("tests/remote_tests.tscn", [])]:
        rc = subprocess.run([sys.executable, os.path.join(HERE, "run_net_tests.py"), "--script", script,
                             "--timeout", "250"] + extra).returncode
        results.append((script, rc))
    print()
    for name, rc in results:
        print("%-28s %s" % (name, "ok" if rc == 0 else "FAILED (%d)" % rc))
    return 0 if all(rc == 0 for _, rc in results) else 1


sys.exit(main())
