#!/usr/bin/env python3
"""Start tests/fake_jellyfin.py, run a Godot test against it, stop the server.

    python3 tests/run_net_tests.py                      # client_tests.gd
    python3 tests/run_net_tests.py --script tests/x.gd  # another script/scene under the mod
    HOST=1 python3 tests/run_net_tests.py               # Godot through flatpak-spawn --host

Reads GODOT and RETROXR_PROJECT from the environment. Output goes to a log file (a pipe straight
into grep hangs under flatpak-spawn); the lines tagged [jf-...] are printed.
"""
import argparse
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GODOT = os.environ.get("GODOT", os.path.expanduser("~/Godot/Godot_v4.7.2-stable_linux.x86_64"))
PROJECT = os.environ.get("RETROXR_PROJECT", os.path.expanduser("~/gits/RetroXR-xargon/RetroXR"))
MOD = "res://mods/xenu.jellyfin/"


def make_video(tmp):
    """A 60 s test video with two audio and three subtitle tracks (what the fake server's item lists)."""
    out = os.path.join(tmp, "test.mp4")
    srts = []
    for i, text in enumerate(["plain", "sdh", "italiano"]):
        p = os.path.join(tmp, "s%d.srt" % i)
        open(p, "w").write("1\n00:00:01,000 --> 00:00:04,000\n%s one\n\n2\n00:00:05,000 --> 00:00:08,000\n%s two\n" % (text, text))
        srts.append(p)
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=s=320x240:r=24:d=60",
           "-f", "lavfi", "-i", "sine=f=440:d=60", "-f", "lavfi", "-i", "sine=f=880:d=60"]
    for p in srts:
        cmd += ["-i", p]
    cmd += ["-map", "0:v", "-map", "1:a", "-map", "2:a"] + sum([["-map", "%d" % (3 + i)] for i in range(3)], [])
    cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-c:a", "aac", "-c:s", "mov_text", "-movflags", "+faststart", out]
    subprocess.run(cmd, check=True)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--script", "--scene", dest="script", default="tests/client_tests.gd")
    ap.add_argument("--video", default="")
    ap.add_argument("--no-range", action="store_true", help="the fake server ignores Range headers")
    ap.add_argument("--timeout", type=int, default=120)
    a = ap.parse_args()
    host = os.environ.get("HOST", "1") == "1"
    tmp = tempfile.mkdtemp(prefix="jf-net-")
    portfile = os.path.join(tmp, "port")
    settings = os.path.join(tmp, "settings.json")
    if not a.video and a.script.endswith(".tscn"):
        a.video = make_video(tmp)
    srv_cmd = [sys.executable, os.path.join(HERE, "fake_jellyfin.py"), "--portfile", portfile]
    if a.video:
        srv_cmd += ["--video", a.video]
    if a.no_range:
        srv_cmd += ["--no-range"]
    srv_log = open(os.path.join(tmp, "server.log"), "w")
    srv = subprocess.Popen(srv_cmd, stdout=srv_log, stderr=subprocess.STDOUT)
    try:
        for _ in range(50):
            if os.path.exists(portfile) and open(portfile).read().strip():
                break
            time.sleep(0.1)
        port = open(portfile).read().strip()
        url = "http://127.0.0.1:%s" % port
        script = MOD + a.script.replace("\\", "/")
        run_kind = "--script" if script.endswith(".gd") else ""
        godot = [GODOT, "--headless", "--path", PROJECT] + ([run_kind] if run_kind else []) + [script]
        env = {"XENU_JF_URL": url, "XENU_JF_SETTINGS": settings}
        if host:
            cmd = ["flatpak-spawn", "--host"] + ["--env=%s=%s" % kv for kv in env.items()] + godot
            full_env = None
        else:
            cmd = godot
            full_env = dict(os.environ, **env)
        log = os.path.join(tmp, "godot.log")
        with open(log, "w") as lf:
            try:
                rc = subprocess.run(cmd, stdout=lf, stderr=subprocess.STDOUT, env=full_env, timeout=a.timeout).returncode
            except subprocess.TimeoutExpired:
                print("[jf-net] FAIL the run did not finish in %d s (a call never answered?)" % a.timeout)
                rc = 1
        for line in open(log, errors="replace"):
            if "[jf-" in line or "[Jellyfin]" in line:
                print(line.rstrip())
        print("godot exit code", rc, "(logs in %s)" % tmp)
        return rc
    finally:
        srv.terminate()
        srv_log.close()


sys.exit(main())
