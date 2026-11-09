#!/usr/bin/env python3
"""SVG logo -> an extruded mesh the mod builds at run time (assets/jellyfin_logo.json).

    python3 tools/make_logo_mesh.py path/to/jellyfin-seeklogo.svg [--depth 0.045] [--out assets/jellyfin_logo.json]

Why not a GLB: no Blender here, and the mesh is small. The tool does what a modeller's extrude does:
  1. flattens every path (M L H V C S Q T A Z, absolute and relative) into polylines;
  2. nests the rings (an even depth is an outline, an odd one a hole: this is nonzero AND evenodd for the
     logo's shapes, which never overlap);
  3. triangulates each outline with its holes (a hole is joined to the outline by the shortest segment
     that crosses nothing, then ear clipping), and CHECKS that the triangles' area is the shapes' area;
  4. extrudes: a front face, and side walls round every ring. No back face (it stands on a panel).

Colours: the logo's own. Paths filled `url(#a)` take the gradient of the file (read from the SVG: stops and
vector, with its transform) per vertex; `#FFF` is white. Side walls are the same colour, a little darker (WALL).

"word_from" is the index at which the lettering starts: the icon and the lettering are two surfaces, because they
want different brightness under the game's tone mapping.

Units: the logo's WIDTH is 1.0, y up, the face towards +Z, the back at z = 0 and the front at z = depth
(`--depth`, also in logo widths: 0.045 is 11 mm on a 250 mm logo; the mod scales it).
"""
import argparse
import json
import math
import re
import sys
import xml.etree.ElementTree as ET

# How much of the face colour the extrusion's walls keep: they show the depth without eating the lettering.
WALL = 0.55         # the icon's walls
WALL_WORD = 0.50    # the lettering's
NUM = re.compile(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?")


class Scanner:
    def __init__(self, d):
        self.d = d
        self.i = 0

    def skip(self):
        while self.i < len(self.d) and self.d[self.i] in " ,\t\r\n":
            self.i += 1

    def more(self):
        self.skip()
        return self.i < len(self.d)

    def peek_cmd(self):
        self.skip()
        if self.i < len(self.d) and self.d[self.i].isalpha():
            return self.d[self.i]
        return None

    def cmd(self):
        c = self.d[self.i]
        self.i += 1
        return c

    def number(self):
        self.skip()
        m = NUM.match(self.d, self.i)
        if not m:
            raise ValueError("number expected at %d: %r" % (self.i, self.d[self.i:self.i + 12]))
        self.i = m.end()
        return float(m.group())

    def flag(self):
        self.skip()
        c = self.d[self.i]
        if c not in "01":
            raise ValueError("flag expected at %d" % self.i)
        self.i += 1
        return int(c)


def cubic(p0, p1, p2, p3, n=10):
    out = []
    for k in range(1, n + 1):
        t = k / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def quad(p0, p1, p2, n=8):
    out = []
    for k in range(1, n + 1):
        t = k / n
        u = 1 - t
        out.append((u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1]))
    return out


def arc(p0, rx, ry, rot, large, sweep, p1):
    """SVG arc (endpoint form) -> points after p0 up to and including p1."""
    if rx == 0 or ry == 0 or p0 == p1:
        return [p1]
    rx, ry = abs(rx), abs(ry)
    phi = math.radians(rot)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1 = cp * dx + sp * dy
    y1 = -sp * dx + cp * dy
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        s = math.sqrt(lam)
        rx, ry = rx * s, ry * s
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    co = math.sqrt(max(0.0, num / den)) * (-1 if large == sweep else 1)
    cx1 = co * rx * y1 / ry
    cy1 = -co * ry * x1 / rx
    cx = cp * cx1 - sp * cy1 + (p0[0] + p1[0]) / 2
    cy = sp * cx1 + cp * cy1 + (p0[1] + p1[1]) / 2

    def ang(ux, uy, vx, vy):
        a = math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
        return a

    t1 = ang(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    dt = ang((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if not sweep and dt > 0:
        dt -= 2 * math.pi
    elif sweep and dt < 0:
        dt += 2 * math.pi
    n = max(2, int(abs(dt) / math.radians(12)) + 1)
    out = []
    for k in range(1, n + 1):
        t = t1 + dt * k / n
        x = rx * math.cos(t)
        y = ry * math.sin(t)
        out.append((cp * x - sp * y + cx, sp * x + cp * y + cy))
    out[-1] = p1
    return out


def parse_path(d):
    """-> list of closed rings (lists of (x, y)), y as in the SVG (down)."""
    sc = Scanner(d)
    rings = []
    cur = []
    pos = (0.0, 0.0)
    start = pos
    last_c = None   # last cubic control (for S)
    last_q = None
    cmd = None
    while sc.more():
        c = sc.peek_cmd()
        if c is not None:
            cmd = sc.cmd()
        elif cmd is None:
            raise ValueError("path does not start with a command")
        rel = cmd.islower()
        C = cmd.upper()
        if C == "Z":
            if cur:
                rings.append(cur)
            cur = []
            pos = start
            last_c = last_q = None
            continue
        if C == "M":
            x, y = sc.number(), sc.number()
            if rel:
                x, y = pos[0] + x, pos[1] + y
            if cur:
                rings.append(cur)
            pos = start = (x, y)
            cur = [pos]
            cmd = "l" if rel else "L"   # further pairs are lineto
            last_c = last_q = None
        elif C == "L":
            x, y = sc.number(), sc.number()
            if rel:
                x, y = pos[0] + x, pos[1] + y
            pos = (x, y)
            cur.append(pos)
            last_c = last_q = None
        elif C == "H":
            x = sc.number()
            pos = (pos[0] + x if rel else x, pos[1])
            cur.append(pos)
            last_c = last_q = None
        elif C == "V":
            y = sc.number()
            pos = (pos[0], pos[1] + y if rel else y)
            cur.append(pos)
            last_c = last_q = None
        elif C in "CS":
            if C == "C":
                v = [sc.number() for _ in range(6)]
                p1 = (v[0], v[1])
                p2 = (v[2], v[3])
                p3 = (v[4], v[5])
                if rel:
                    p1 = (pos[0] + p1[0], pos[1] + p1[1])
                    p2 = (pos[0] + p2[0], pos[1] + p2[1])
                    p3 = (pos[0] + p3[0], pos[1] + p3[1])
            else:
                v = [sc.number() for _ in range(4)]
                p1 = (2 * pos[0] - last_c[0], 2 * pos[1] - last_c[1]) if last_c else pos
                p2 = (v[0], v[1])
                p3 = (v[2], v[3])
                if rel:
                    p2 = (pos[0] + p2[0], pos[1] + p2[1])
                    p3 = (pos[0] + p3[0], pos[1] + p3[1])
            cur.extend(cubic(pos, p1, p2, p3))
            pos = p3
            last_c = p2
            last_q = None
        elif C in "QT":
            if C == "Q":
                v = [sc.number() for _ in range(4)]
                p1 = (v[0], v[1])
                p2 = (v[2], v[3])
                if rel:
                    p1 = (pos[0] + p1[0], pos[1] + p1[1])
                    p2 = (pos[0] + p2[0], pos[1] + p2[1])
            else:
                v = [sc.number() for _ in range(2)]
                p1 = (2 * pos[0] - last_q[0], 2 * pos[1] - last_q[1]) if last_q else pos
                p2 = (v[0], v[1])
                if rel:
                    p2 = (pos[0] + p2[0], pos[1] + p2[1])
            cur.extend(quad(pos, p1, p2))
            pos = p2
            last_q = p1
            last_c = None
        elif C == "A":
            rx, ry, rot = sc.number(), sc.number(), sc.number()
            large, sweep = sc.flag(), sc.flag()
            x, y = sc.number(), sc.number()
            if rel:
                x, y = pos[0] + x, pos[1] + y
            cur.extend(arc(pos, rx, ry, rot, large, sweep, (x, y)))
            pos = (x, y)
            last_c = last_q = None
        else:
            raise ValueError("unsupported command %r" % cmd)
    if cur:
        rings.append(cur)
    return rings


# ---------------------------------------------------------------- geometry

def clean(ring):
    out = []
    for p in ring:
        if not out or abs(p[0] - out[-1][0]) > 1e-6 or abs(p[1] - out[-1][1]) > 1e-6:
            out.append(p)
    while len(out) > 1 and abs(out[0][0] - out[-1][0]) < 1e-6 and abs(out[0][1] - out[-1][1]) < 1e-6:
        out.pop()
    return out


def area(ring):
    a = 0.0
    for i in range(len(ring)):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % len(ring)]
        a += x1 * y2 - x2 * y1
    return a / 2


def inside(pt, ring):
    x, y = pt
    c = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            c = not c
    return c


def seg_cross(a, b, c, d):
    """Proper intersection of segments ab and cd (touching at an end does not count)."""
    def o(p, q, r):
        return (q[0] - p[0]) * (r[1] - p[1]) - (q[1] - p[1]) * (r[0] - p[0])
    d1, d2, d3, d4 = o(c, d, a), o(c, d, b), o(a, b, c), o(a, b, d)
    return d1 * d2 < -1e-12 and d3 * d4 < -1e-12


def bridge(poly, hole):
    """Join `hole` (clockwise, inside the counter-clockwise `poly`) into one weakly simple polygon."""
    pairs = []
    for hi, h in enumerate(hole):
        for pi, p in enumerate(poly):
            pairs.append(((h[0] - p[0]) ** 2 + (h[1] - p[1]) ** 2, hi, pi))
    pairs.sort()
    for _, hi, pi in pairs:
        a, b = hole[hi], poly[pi]
        ok = True
        for ring in (poly, hole):
            n = len(ring)
            for k in range(n):
                if seg_cross(a, b, ring[k], ring[(k + 1) % n]):
                    ok = False
                    break
            if not ok:
                break
        if not ok:
            continue
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        if not inside(mid, poly) or inside(mid, hole):
            continue
        # poly[..pi], hole from hi round to hi, poly[pi..]
        h = hole[hi:] + hole[:hi]
        return poly[:pi + 1] + h + [h[0]] + [poly[pi]] + poly[pi + 1:]
    raise RuntimeError("no bridge found for a hole")


def ear_clip(poly):
    """Triangles (as index triples into `poly`) of a counter-clockwise, weakly simple polygon."""
    idx = list(range(len(poly)))
    tris = []

    def ear(i0, i1, i2):
        a, b, c = poly[i0], poly[i1], poly[i2]
        cross = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
        if cross <= 1e-12:
            return False
        for j in idx:
            if j in (i0, i1, i2):
                continue
            p = poly[j]
            if p == a or p == b or p == c:
                continue
            d1 = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
            d2 = (c[0] - b[0]) * (p[1] - b[1]) - (c[1] - b[1]) * (p[0] - b[0])
            d3 = (a[0] - c[0]) * (p[1] - c[1]) - (a[1] - c[1]) * (p[0] - c[0])
            if d1 >= -1e-12 and d2 >= -1e-12 and d3 >= -1e-12:
                return False
        return True

    guard = 0
    while len(idx) > 3 and guard < 100000:
        guard += 1
        n = len(idx)
        clipped = False
        for k in range(n):
            i0, i1, i2 = idx[k - 1], idx[k], idx[(k + 1) % n]
            if ear(i0, i1, i2):
                tris.append((i0, i1, i2))
                idx.pop(k)
                clipped = True
                break
        if not clipped:
            # a degenerate sliver: drop the flattest vertex and go on
            best, bk = None, 0
            for k in range(n):
                a, b, c = poly[idx[k - 1]], poly[idx[k]], poly[idx[(k + 1) % n]]
                cr = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
                if best is None or cr < best:
                    best, bk = cr, k
            idx.pop(bk)
    if len(idx) == 3:
        tris.append((idx[0], idx[1], idx[2]))
    return tris


def shapes_of(rings):
    """Rings -> [(outline ccw, [holes cw])] by nesting depth."""
    rings = [clean(r) for r in rings if len(clean(r)) >= 3]
    depth = []
    for i, r in enumerate(rings):
        d = 0
        for j, o in enumerate(rings):
            if i != j and inside(r[0], o) and abs(area(o)) > abs(area(r)):
                d += 1
        depth.append(d)
    shapes = []
    for i, r in enumerate(rings):
        if depth[i] % 2 == 0:
            outline = r if area(r) > 0 else r[::-1]
            holes = []
            for j, h in enumerate(rings):
                if depth[j] == depth[i] + 1 and inside(h[0], r):
                    holes.append(h if area(h) < 0 else h[::-1])
            shapes.append((outline, holes))
    return shapes


# ---------------------------------------------------------------- gradient

def hex_color(s):
    s = s.lstrip("#")
    if len(s) == 3:
        s = "".join(ch * 2 for ch in s)
    return tuple(int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def read_gradient(root):
    ns = "{http://www.w3.org/2000/svg}"
    for g in root.iter(ns + "linearGradient"):
        stops = [(float(s.get("offset", "0")), hex_color(s.get("stop-color", "#fff"))) for s in g.iter(ns + "stop")]
        x1, y1, x2, y2 = (float(g.get(k)) for k in ("x1", "y1", "x2", "y2"))
        tx = ty = 0.0
        t = g.get("gradientTransform", "")
        m = re.match(r"translate\(\s*([-\d.]+)[ ,]+([-\d.]+)\s*\)", t)
        if m:
            tx, ty = float(m.group(1)), float(m.group(2))
        # the vector in the shapes' own space
        return {"id": g.get("id"), "stops": stops, "p0": (x1 + tx, y1 + ty), "p1": (x2 + tx, y2 + ty)}
    return None


def grad_at(g, p):
    vx, vy = g["p1"][0] - g["p0"][0], g["p1"][1] - g["p0"][1]
    t = ((p[0] - g["p0"][0]) * vx + (p[1] - g["p0"][1]) * vy) / (vx * vx + vy * vy)
    t = max(0.0, min(1.0, t))
    s = g["stops"]
    for i in range(len(s) - 1):
        if t <= s[i + 1][0]:
            k = (t - s[i][0]) / max(s[i + 1][0] - s[i][0], 1e-9)
            return tuple(s[i][1][c] * (1 - k) + s[i + 1][1][c] * k for c in range(3))
    return s[-1][1]


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("svg")
    ap.add_argument("--depth", type=float, default=0.045)
    ap.add_argument("--out", default="assets/jellyfin_logo.json")
    a = ap.parse_args()
    root = ET.parse(a.svg).getroot()
    ns = "{http://www.w3.org/2000/svg}"
    width = float(root.get("width"))
    height = float(root.get("height"))
    grad = read_gradient(root)
    sc = 1.0 / width

    pos, nor, col, idx = [], [], [], []
    total_area_svg = 0.0
    word_from = None   # where the plain-coloured (the lettering) triangles begin in the index list
    total_area_tri = 0.0

    def push(p3, n3, c):
        pos.extend([round(p3[0], 5), round(p3[1], 5), round(p3[2], 5)])
        nor.extend([round(n3[0], 4), round(n3[1], 4), round(n3[2], 4)])
        col.extend([round(c[0], 4), round(c[1], 4), round(c[2], 4)])
        return len(pos) // 3 - 1

    def to3(p, z):
        return ((p[0] - width / 2) * sc, (height / 2 - p[1]) * sc, z)

    for path in root.iter(ns + "path"):
        fill = path.get("fill", "#000")
        if word_from is None and not fill.startswith("url("):
            word_from = len(idx)
        rings = parse_path(path.get("d"))
        shapes = shapes_of(rings)
        for outline, holes in shapes:
            poly = list(outline)
            for h in sorted(holes, key=lambda r: -max(p[0] for p in r)):
                poly = bridge(poly, h)
            tris = ear_clip(poly)
            area_shape = area(outline) + sum(area(h) for h in holes)   # holes are clockwise: negative
            area_tri = sum(abs(area([poly[i], poly[j], poly[k]])) for i, j, k in tris)
            total_area_svg += area_shape
            total_area_tri += area_tri
            if abs(area_tri - area_shape) > 1e-3 * max(area_shape, 1.0):
                sys.exit("triangulation lost area: %.4f vs %.4f" % (area_tri, area_shape))

            def colour(p):
                return grad_at(grad, p) if fill.startswith("url(") else hex_color(fill)
            # front face. The SVG's y is down and ours up: the winding flips, so the triangles are reversed.
            base = {}
            for i, j, k in tris:
                for v in (i, j, k):
                    if v not in base:
                        base[v] = push(to3(poly[v], a.depth), (0, 0, 1), colour(poly[v]))
                # keep whichever winding faces +Z (the y flip reversed the svg's)
                pa, pb, pc = (to3(poly[v], 0.0) for v in (i, j, k))
                cross_z = (pb[0] - pa[0]) * (pc[1] - pa[1]) - (pb[1] - pa[1]) * (pc[0] - pa[0])
                if abs(cross_z) < 1e-8:
                    continue          # three points in a line: no area, nothing to draw
                idx.extend([base[i], base[j], base[k]] if cross_z > 0 else [base[i], base[k], base[j]])
            # side walls round every ring (outline and holes)
            for ring in [outline] + holes:
                n = len(ring)
                ccw_ours = area(ring) < 0     # the y flip reverses the svg's orientation
                for q in range(n):
                    p, r = ring[q], ring[(q + 1) % n]
                    dx, dy = (r[0] - p[0]) * sc, -(r[1] - p[1]) * sc
                    ln = math.hypot(dx, dy)
                    if ln < 1e-9:
                        continue
                    # outward: right of the direction for a counter-clockwise ring, left for a clockwise one
                    nx, ny = (dy / ln, -dx / ln) if ccw_ours else (-dy / ln, dx / ln)
                    c1, c2 = colour(p), colour(r)
                    wall = WALL if fill.startswith("url(") else WALL_WORD
                    dark = lambda c, k=wall: tuple(v * k for v in c)
                    v0 = push(to3(p, 0.0), (nx, ny, 0), dark(c1))
                    v1 = push(to3(r, 0.0), (nx, ny, 0), dark(c2))
                    v2 = push(to3(r, a.depth), (nx, ny, 0), dark(c2))
                    v3 = push(to3(p, a.depth), (nx, ny, 0), dark(c1))
                    if ccw_ours:
                        idx.extend([v0, v1, v2, v0, v2, v3])
                    else:
                        idx.extend([v0, v2, v1, v0, v3, v2])

    # Godot draws a face whose vertices run CLOCKWISE as seen from the front; everything above was wound counter-clockwise
    # (the right-hand rule, which is what the check below reads). Reversed here, once, for the whole mesh: with it the other
    # way round every face looks backwards, the front is culled and only the INSIDE of the walls shows, which is how
    # the letters came out as thin outlines.
    for t in range(0, len(idx), 3):
        idx[t + 1], idx[t + 2] = idx[t + 2], idx[t + 1]

    # winding check: every triangle's geometric normal must agree with its stored normal (front faces +Z).
    bad = 0
    for t in range(0, len(idx), 3):
        i0, i1, i2 = idx[t:t + 3]
        P = [pos[i * 3:i * 3 + 3] for i in (i0, i1, i2)]
        u = [P[1][c] - P[0][c] for c in range(3)]
        v = [P[2][c] - P[0][c] for c in range(3)]
        n = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]]
        sn = nor[i0 * 3:i0 * 3 + 3]
        if math.sqrt(sum(c * c for c in n)) < 1e-8:
            continue          # a sliver of no area faces nowhere
        if sum(n[c] * sn[c] for c in range(3)) > 0:     # the right-hand normal must now be AGAINST the stored one
            bad += 1
    if bad:
        # the side walls may be wound the other way: flip them wholesale if that is all of them
        sys.exit("%d of %d triangles are wound the wrong way for Godot (clockwise from the front)" % (bad, len(idx) // 3))
    out = {"word_from": word_from if word_from is not None else len(idx), "aspect": width / height, "width": 1.0, "height": height / width, "depth": a.depth,
           "positions": pos, "normals": nor, "colors": col, "indices": idx}
    with open(a.out, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    print("%d vertices, %d triangles, area %.2f (triangulated %.2f), %.0f KB -> %s" % (
        len(pos) // 3, len(idx) // 3, total_area_svg, total_area_tri, len(json.dumps(out)) / 1024, a.out))


main()
