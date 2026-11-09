#!/usr/bin/env python3
"""A tiny stand-in for a Jellyfin server, for the mod's tests and probes.

    python3 tests/fake_jellyfin.py [--port 0] [--video PATH] [--portfile FILE]

Speaks just what the decoder calls: sign-in (password alice/secret, or Quick Connect, which
approves on the 2nd poll), views, latest, next up, children, seasons, episodes, one item with
audio and subtitle streams (one of them hearing-impaired), the WebVTT of those subtitles and
the video itself (--video; Range requests honoured).

Every request is logged to stdout as `REQ METHOD PATH AUTH` (the token redacted to `tok`), so a test
can read back what the client really sent.
"""
import argparse
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

REPORTS = []
TOKEN_PW = "tok-pw"
TOKEN_QC = "tok-qc"
QC = {"polls": 0}
VIDEO = {"path": "", "no_range": False}

USERS = [{"Id": "u1", "Name": "alice"}, {"Id": "u2", "Name": "bob"}]

LIBS = [
    {"Id": "lib-movies", "Name": "Movies", "CollectionType": "movies", "Type": "CollectionFolder", "IsFolder": True},
    {"Id": "lib-shows", "Name": "Anime", "CollectionType": "tvshows", "Type": "CollectionFolder", "IsFolder": True},
    {"Id": "lib-music", "Name": "Music", "CollectionType": "music", "Type": "CollectionFolder", "IsFolder": True},
]
MOVIES = [{"Id": "mv%d" % i, "Name": n, "Type": "Movie", "ProductionYear": y, "RunTimeTicks": 90 * 600000000}
          for i, (n, y) in enumerate([("Akira", 1988), ("Perfect Blue", 1997), ("Paprika", 2006)], 1)]
SERIES = {"Id": "series1", "Name": "Re:Zero", "Type": "Series", "IsFolder": True, "ProductionYear": 2016}
SEASON = {"Id": "season2", "Name": "Season 2", "Type": "Season", "IsFolder": True, "SeriesName": "Re:Zero",
          "SeriesId": "series1", "IndexNumber": 2}
EPISODES = [{"Id": "ep%d" % n, "Name": t, "Type": "Episode", "SeriesName": "Re:Zero", "SeriesId": "series1",
             "SeasonId": "season2", "SeasonName": "Season 2",
             "ParentIndexNumber": 2, "IndexNumber": n, "RunTimeTicks": 24 * 600000000}
            for n, t in [(1, "Re:Birth"), (2, "Re:Turn"), (3, "Re:Union")]]

STREAMS = [
    {"Type": "Video", "Index": 0, "Codec": "h264"},
    {"Type": "Audio", "Index": 1, "Language": "jpn", "Codec": "aac", "DisplayTitle": "Japanese - AAC - Stereo", "IsDefault": True},
    {"Type": "Audio", "Index": 2, "Language": "eng", "Codec": "ac3", "DisplayTitle": "English - AC3 - 5.1"},
    {"Type": "Subtitle", "Index": 3, "Language": "eng", "Codec": "subrip", "DisplayTitle": "English - SubRip"},
    {"Type": "Subtitle", "Index": 4, "Language": "eng", "Codec": "subrip", "DisplayTitle": "English - SDH", "IsHearingImpaired": True},
    {"Type": "Subtitle", "Index": 5, "Language": "ita", "Codec": "subrip", "DisplayTitle": "Italiano - SubRip"},
]
VTT = {
    3: "WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nI will save you this time.\n",
    4: ("WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nSubaru: I will save you this time.\n\n"
        "00:00:05.000 --> 00:00:07.000\n[wind howling]\n\n00:00:08.000 --> 00:00:12.000\nEmilia: Why would you say that?\n"),
    5: "WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nQuesta volta ti salvero.\n",
}


def episode_full(ep):
    d = dict(ep)
    d["MediaSources"] = [{"Id": "ms1", "MediaStreams": STREAMS}]
    return d


class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="application/json", extra=None):
        if not isinstance(body, bytes):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _auth(self):
        a = self.headers.get("Authorization", "")
        m = re.search(r'Token="([^"]*)"', a)
        qs = parse_qs(urlparse(self.path).query)
        tok = m.group(1) if m else (qs.get("api_key", [""])[0])
        return tok

    def _body(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n))
        except Exception:
            return {}

    def _items(self, items):
        return {"Items": items, "TotalRecordCount": len(items), "StartIndex": 0}

    def _route(self):
        u = urlparse(self.path)
        p, qs = u.path, parse_qs(u.query)
        tok = self._auth()
        print("REQ %s %s %s" % (self.command, p, "tok" if tok else "-"), flush=True)
        # a test hook: what the client reported about playback
        if p == "/_test/reports":
            return self._send(200, REPORTS)
        # open endpoints
        if p == "/System/Info/Public":
            return self._send(200, {"ServerName": "Fake Jellyfin", "Version": "10.9.0", "Id": "fake"})
        if p == "/Users/Public":
            return self._send(200, USERS)
        if p == "/QuickConnect/Enabled":
            return self._send(200, b"true")
        if p == "/QuickConnect/Initiate" and self.command == "POST":
            QC["polls"] = 0
            return self._send(200, {"Code": "123456", "Secret": "sec", "Authenticated": False})
        if p == "/QuickConnect/Connect":
            if qs.get("secret", [""])[0] != "sec":
                return self._send(404, {"error": "no such secret"})
            QC["polls"] += 1
            return self._send(200, {"Authenticated": QC["polls"] >= 2, "Secret": "sec", "Code": "123456"})
        if p == "/Users/AuthenticateWithQuickConnect" and self.command == "POST":
            if self._body().get("Secret") != "sec":
                return self._send(401, {"error": "bad secret"})
            return self._send(200, {"AccessToken": TOKEN_QC, "User": USERS[0]})
        if p == "/Users/AuthenticateByName" and self.command == "POST":
            b = self._body()
            if b.get("Username") == "alice" and b.get("Pw") == "secret":
                return self._send(200, {"AccessToken": TOKEN_PW, "User": USERS[0]})
            return self._send(401, {"error": "bad credentials"})
        # everything else wants a token
        if tok not in (TOKEN_PW, TOKEN_QC):
            return self._send(401, {"error": "no token"})
        if p in ("/Sessions/Playing", "/Sessions/Playing/Progress", "/Sessions/Playing/Stopped") and self.command == "POST":
            kind = {"/Sessions/Playing": "start", "/Sessions/Playing/Progress": "progress"}.get(p, "stopped")
            REPORTS.append({"kind": kind, "body": self._body()})
            return self._send(204, b"")
        if p == "/Users/u1/Items/Resume":
            e = dict(EPISODES[0])
            e["UserData"] = {"PlaybackPositionTicks": 50000000, "PlayedPercentage": 41.6}
            m = dict(MOVIES[1])
            m["UserData"] = {"PlaybackPositionTicks": 100000000, "PlayedPercentage": 10.0}
            return self._send(200, self._items([e, m]))
        if p == "/Users/u1/Views":
            return self._send(200, self._items(LIBS))
        if p == "/Users/u1/Items/Latest":
            return self._send(200, [EPISODES[2], EPISODES[1], MOVIES[2]])
        if p == "/Shows/NextUp":
            return self._send(200, self._items([EPISODES[1]]))
        if p == "/Users/u1/Items" and qs.get("searchTerm"):
            term = qs["searchTerm"][0].lower()
            pool = MOVIES + [SERIES] + EPISODES
            return self._send(200, self._items([i for i in pool if term in i["Name"].lower()]))
        if p == "/Users/u1/Items":
            parent = qs.get("ParentId", [""])[0]
            if parent == "lib-movies":
                return self._send(200, self._items(MOVIES))
            if parent == "lib-shows":
                return self._send(200, self._items([SERIES]))
            return self._send(200, self._items([]))
        if p == "/Shows/series1/Seasons":
            return self._send(200, self._items([SEASON]))
        if p == "/Shows/series1/Episodes":
            return self._send(200, self._items(EPISODES))
        m = re.match(r"^/Users/u1/Items/(\w+)$", p)
        if m:
            for ep in EPISODES:
                if ep["Id"] == m.group(1):
                    return self._send(200, episode_full(ep))
            for mv in MOVIES:
                if mv["Id"] == m.group(1):
                    return self._send(200, mv)
            return self._send(404, {})
        m = re.match(r"^/Videos/(\w+)/(\w+)/Subtitles/(\d+)/0/Stream\.vtt$", p)
        if m:
            t = VTT.get(int(m.group(3)))
            return self._send(200 if t else 404, (t or "").encode(), "text/vtt")
        m = re.match(r"^/Videos/(\w+)/(stream|master\.m3u8)$", p)
        if m:
            return self._video()
        return self._send(404, {"error": "unknown path " + p})

    def _video(self):
        path = VIDEO["path"]
        if not path or not os.path.exists(path):
            return self._send(404, {"error": "no video configured"})
        size = os.path.getsize(path)
        rng = None if VIDEO["no_range"] else self.headers.get("Range")
        start, end = 0, size - 1
        code = 200
        if rng:
            m = re.match(r"bytes=(\d+)-(\d*)", rng)
            if m:
                start = int(m.group(1))
                end = int(m.group(2)) if m.group(2) else size - 1
                code = 206
        with open(path, "rb") as f:
            f.seek(start)
            data = f.read(end - start + 1)
        extra = {"Accept-Ranges": "bytes"}
        if code == 206:
            extra["Content-Range"] = "bytes %d-%d/%d" % (start, end, size)
        self._send(code, data, "video/mp4", extra)

    do_GET = do_POST = do_HEAD = _route


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--video", default="")
    ap.add_argument("--portfile", default="")
    ap.add_argument("--no-range", action="store_true", help="ignore Range headers (answer 200 with the whole file)")
    a = ap.parse_args()
    VIDEO["path"] = a.video
    VIDEO["no_range"] = a.no_range
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    port = srv.server_address[1]
    if a.portfile:
        with open(a.portfile, "w") as f:
            f.write(str(port))
    print("LISTEN %d" % port, flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
