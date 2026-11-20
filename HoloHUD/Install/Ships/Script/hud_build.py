r"""HUD_BUILD.PY -- the flight HUD's image set for one screen size and one camera field of view, with Python alone.

The HUD (lib_hud.ks) draws every symbol from pre-drawn sprites sized in DEGREES of the view, so each screen size and
each HUD CAM field of view needs its own set: the sprites, sprites.txt and hud_layout.txt. gen_hud.py makes them on the
development side (numpy, matplotlib, Pillow and the simulators); this file makes the same set from a reference set with
the standard library only, so the installer can build the sets a player's screen needs instead of the release
shipping one per screen.

    python hud_build.py REF_DIR OUT_DIR --screen 1920x1080 --fov 70

REF_DIR is a set gen_hud.py made (hud/, 3840x2160 through 60 deg): its hud_runways.txt is copied and the layout lines
that do not depend on the screen or the field of view (the runway, the units, the texts) are taken from its
hud_layout.txt. Everything else is computed here with gen_hud.py's own formulas, and the sprites are drawn as
matplotlib's Agg renderer draws them (exact pixel-area coverage, butt caps, mitred polygons, horizontal and vertical
paths snapped to the pixel grid, each artist blended over the last). hud_build_check.py compares this file's sets
with gen_hud.py's on every screen and field of view.
"""
import math
import os
import struct
import sys
import zlib

HUD_RGB = (0x90, 0xff, 0x97)    # the HUD's green (gen_hud HUD #90ff97)

# ------------------------------------------------------------------ gen_hud.py's sizes, in degrees of the view
HUD_W_DEG = 16.0
HUD_H_DEG = 18.0
HUD_TOP_DEG = 2.0
HUD_CENTRE_DEG = HUD_H_DEG / 2.0 - HUD_TOP_DEG
CAM_PITCH_DEG = HUD_CENTRE_DEG
TEXT_DEG = 0.66
TAPE_HALF_DEG = 4.5
TAPE_KT = 25.0
TAPE_FT = 2500.0
TAPE_TICK_DEG = 0.2
TAPE_NUM_SCALE = 0.85
KEAS_X_DEG = -6.0
ALT_X_DEG = 5.6
CTL_SCALE = 0.95
CAP_EM = 1493.0 / 2048.0
PHASE_CAP_FRAC = 0.7
SB_ROW_DEG = HUD_H_DEG - HUD_TOP_DEG - 1.6
SB_TIP_DEG, SB_PTR_DEG = 0.1, 0.35
SB_SLIDER_DEG = 2.0 * (SB_TIP_DEG + SB_PTR_DEG)
PL_FULL, PL_TICKS = 110.0, (0.0, 67.0, 100.0)
YAW_STEP_DEG, YAW_MAX_DEG = 0.25, 5.0
CTL_ROW_DEG = SB_ROW_DEG + 0.95
AIM_R_DEG = 0.2
RWY_GLASS_TOP_DEG = 5.0
RWY_GLASS_TOP_HW_DEG = 4.3
FPM_R_DEG, FPM_WING_DEG, FPM_TAIL_DEG = 0.25, 0.4, 0.3
FPM_HALF_W_DEG = FPM_R_DEG + FPM_WING_DEG
FPM_TOP_DEG = FPM_R_DEG + FPM_TAIL_DEG
FLARE_TRI_DEG = 0.35
DECEL_H_DEG = 3.0
QA_FULL, QA_LIM, QA_CAUT = 60.0, 40.0, 30.0   # the ascent's q x alpha cue (gen_hud.py's)
VV_TEXT_GAP_DEG = 0.1
# sizes in px, the same on every screen
STROKE_PX = 3.0
KOS_ANGLE_STEP = 2
HZ_SEGS = 8
HZ_OVL_PX = 4.0
RWY_SEG_PX = (96.0, 32.0, 12.0, 6.0)
DPI = 100.0
MONO_ADV = 1233.0 / 2048.0      # DejaVu Sans Mono's advance, em (gen_taem_bg MONO_ADV; the layout prints it rounded)


class Geom:
    """The screen, the field of view and every size derived from them (gen_hud.py's module constants)."""

    def __init__(self, w, h, fov, mono_adv):
        self.W, self.H, self.FOV = w, h, fov
        self.F_PX = (h / 2.0) / math.tan(math.radians(fov / 2.0))
        self.U0, self.VS = w / 2.0, h / 2.0
        self.V0 = self.VS - self.px(CAM_PITCH_DEG)
        self.FIELD = (self.U0 - self.px(HUD_W_DEG / 2.0), self.V0 - self.px(HUD_TOP_DEG),
                      self.U0 + self.px(HUD_W_DEG / 2.0), self.V0 + self.px(HUD_H_DEG - HUD_TOP_DEG))
        self.MONO_ADV = mono_adv
        self.AUTO_W_DEG = 4 * mono_adv * TEXT_DEG * CTL_SCALE
        self.TAPE_BOX_OFF_DEG = 1.5 * mono_adv * TAPE_NUM_SCALE * TEXT_DEG + 0.13
        self.MODE_X_DEG = KEAS_X_DEG - self.AUTO_W_DEG / 2.0
        self.LOWER_SHIFT_DEG = self.MODE_X_DEG + (HUD_W_DEG / 2.0 - 0.6)
        self.SB_X0_DEG, self.SB_X1_DEG = -0.3 + self.LOWER_SHIFT_DEG, 3.5 + self.LOWER_SHIFT_DEG
        self.HZ_SEG_PX = (self.px(12.0) - self.px(1.2)) / HZ_SEGS

    def px(self, deg):
        return self.F_PX * math.tan(math.radians(deg))

    def layout(self):
        """gen_hud._layout_lines' values that depend on the screen or the field of view."""
        px, U0, V0 = self.px, self.U0, self.V0
        cap = PHASE_CAP_FRAC * SB_SLIDER_DEG
        return dict([
            ('SCREEN_W', self.W), ('SCREEN_H', self.H), ('CAM_FOV_V', self.FOV), ('F_PX', self.F_PX),
            ('U0', U0), ('V0', V0), ('VS', self.VS), ('CAM_PITCH_DEG', CAM_PITCH_DEG),
            ('FIELD_L', self.FIELD[0]), ('FIELD_T', self.FIELD[1]), ('FIELD_R', self.FIELD[2]),
            ('FIELD_B', self.FIELD[3]),
            ('FD_V', V0 + px(HUD_CENTRE_DEG)),
            ('LAD_NUM_ALONG', px(2.9)), ('LAD_NUM_UP', px(0.3)), ('LAD_NUM_FS', round(px(TEXT_DEG) * 0.8)),
            ('HZ_GAP', px(1.2)), ('HZ_SEG_PX', self.HZ_SEG_PX),
            ('NZ_DX', -px(1.2)), ('NZ_DY', px(0.7)), ('NZ_FS', round(px(TEXT_DEG) * 0.85)),
            ('VC', V0 + px(HUD_CENTRE_DEG)), ('HALF', px(TAPE_HALF_DEG)), ('XS', U0 + px(KEAS_X_DEG)),
            ('XA', U0 + px(ALT_X_DEG)),
            ('PER_KT', px(TAPE_HALF_DEG) / (TAPE_KT / 2.0)), ('PER_FT', px(TAPE_HALF_DEG) / (TAPE_FT / 2.0)),
            ('TAPE_FS', round(px(TEXT_DEG) * TAPE_NUM_SCALE)),
            ('BOX_KX', U0 + px(KEAS_X_DEG) - px(self.TAPE_BOX_OFF_DEG + 0.45)),
            ('BOX_AX', U0 + px(ALT_X_DEG) + px(self.TAPE_BOX_OFF_DEG)),
            ('BOX_Y', V0 + px(HUD_CENTRE_DEG) - px(0.1)),
            ('GSI_X', U0 + px(ALT_X_DEG) + px(self.TAPE_BOX_OFF_DEG + 0.45 + 0.2)),
            ('DIG_FS', round(px(TEXT_DEG) * 0.95)),
            ('SB_B0', U0 + px(self.SB_X0_DEG)), ('SB_B1', U0 + px(self.SB_X1_DEG)), ('SB_YB', V0 + px(SB_ROW_DEG)),
            ('SB_TIP', px(SB_TIP_DEG)),
            ('XM', U0 + px(self.MODE_X_DEG)), ('AUTO_W', 4 * self.MONO_ADV * px(TEXT_DEG) * CTL_SCALE),
            ('PH_Y', V0 + px(SB_ROW_DEG) + px(cap) / 2.0),
            ('PH_FS', round(px(TEXT_DEG) * (cap / CAP_EM / TEXT_DEG))),
            ('YC', V0 + px(CTL_ROW_DEG)), ('CTL_FS', round(px(TEXT_DEG) * CTL_SCALE)), ('ZOOM_DX', px(1.9)),
            ('YTOP', V0 - px(HUD_TOP_DEG - 0.7)), ('MSG_FS', round(px(TEXT_DEG))), ('DM_DY', px(0.75)),
            ('AIM_R', px(AIM_R_DEG)), ('AIM_MIN_SPAN', px(0.2)),
            ('GLASS_TOP', V0 - px(RWY_GLASS_TOP_DEG)), ('GLASS_HW', px(RWY_GLASS_TOP_HW_DEG)),
            ('VV_HW', px(FPM_HALF_W_DEG)), ('VV_TOP', px(FPM_TOP_DEG)), ('VV_GAP', px(VV_TEXT_GAP_DEG))])


# ------------------------------------------------------------------ the rasterizer (matplotlib's Agg, for these shapes)
def _clip_area(poly, x0, y0):
    """The area of convex polygon poly inside the pixel [x0, x0 + 1] x [y0, y0 + 1]."""
    pts = poly
    for axis, lim, keep_ge in ((0, x0, True), (0, x0 + 1.0, False), (1, y0, True), (1, y0 + 1.0, False)):
        out = []
        n = len(pts)
        if n == 0:
            return 0.0
        for k in range(n):
            p, q = pts[k], pts[(k + 1) % n]
            pin = (p[axis] >= lim) if keep_ge else (p[axis] <= lim)
            qin = (q[axis] >= lim) if keep_ge else (q[axis] <= lim)
            if pin:
                out.append(p)
            if pin != qin:
                t = (lim - p[axis]) / (q[axis] - p[axis])
                out.append((p[0] + t * (q[0] - p[0]), p[1] + t * (q[1] - p[1])))
        pts = out
    if len(pts) < 3:
        return 0.0
    s = 0.0
    for k in range(len(pts)):
        p, q = pts[k], pts[(k + 1) % len(pts)]
        s += p[0] * q[1] - q[0] * p[1]
    return abs(s) / 2.0


def _half_planes(poly):
    s = 0.0
    for k in range(len(poly)):
        p, q = poly[k], poly[(k + 1) % len(poly)]
        s += p[0] * q[1] - q[0] * p[1]
    hp = []
    for k in range(len(poly)):
        p, q = poly[k], poly[(k + 1) % len(poly)]
        eu, ev = q[0] - p[0], q[1] - p[1]
        nu, nv = (-ev, eu) if s > 0 else (ev, -eu)
        m = math.hypot(nu, nv)
        if m < 1e-12:
            continue
        hp.append((nu / m, nv / m, (nu * p[0] + nv * p[1]) / m))
    return hp


def _coverage(polys, n):
    """{(i, j): covered fraction} of an artist made of non-overlapping convex polygons, on an n x n canvas."""
    cov = {}
    for poly in polys:
        if len(poly) < 3:
            continue
        hp = _half_planes(poly)
        xs = [p[0] for p in poly]
        ys = [p[1] for p in poly]
        for j in range(max(0, int(math.floor(min(ys)))), min(n, int(math.floor(max(ys))) + 1)):
            cy = j + 0.5
            for i in range(max(0, int(math.floor(min(xs)))), min(n, int(math.floor(max(xs))) + 1)):
                cx = i + 0.5
                d = min(nu * cx + nv * cy - c for nu, nv, c in hp)
                if d >= 0.7072:
                    a = 1.0
                elif d <= -0.7072:
                    continue
                else:
                    a = _clip_area(poly, i, j)
                    if a <= 0.0:
                        continue
                cov[(i, j)] = cov.get((i, j), 0.0) + a
    return cov


def _mul(a, b):
    t = a * b + 128
    return ((t >> 8) + t) >> 8


class Canvas:
    """An n x n RGBA sprite, transparent white, painted artist by artist as Agg's plain-alpha blender paints."""

    def __init__(self, n):
        self.n = n
        self.A = [0] * (n * n)

    def paint(self, polys, holes=()):
        cov = _coverage(polys, self.n)
        for k, f in _coverage(holes, self.n).items():
            if k in cov:
                cov[k] = max(0.0, cov[k] - f)
        for (i, j), f in cov.items():
            cover = min(255, int(math.floor(f * 256.0 + 1e-7)))
            alpha = _mul(255, cover)
            if alpha == 0:
                continue
            k = j * self.n + i
            a = self.A[k]
            self.A[k] = (((alpha + a) << 8) - alpha * a) >> 8

    def bbox(self):
        """The ink's (l, t, r, b), r and b exclusive (Pillow's getbbox), or None."""
        n, A = self.n, self.A
        rows = [j for j in range(n) if any(A[j * n:(j + 1) * n])]
        if not rows:
            return None
        cols = [i for i in range(n) if any(A[j * n + i] for j in rows)]
        return cols[0], rows[0], cols[-1] + 1, rows[-1] + 1

    def png(self, path):
        n, A = self.n, self.A
        raw = bytearray()
        for j in range(n):
            raw.append(0)
            for i in range(n):
                a = A[j * n + i]
                raw += bytes((HUD_RGB[0], HUD_RGB[1], HUD_RGB[2], a) if a else (255, 255, 255, 0))
        _write_png(path, n, n, bytes(raw))


def _write_png(path, w, h, raw):
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw, 9)))
        f.write(chunk(b'IEND', b''))


class Frame:
    """matplotlib's data -> pixel transform for an n x n sprite (figure n / DPI in at DPI, axes [0, 0, 1, 1], x 0..n,
    y n..0) and Agg's flip, in the same float operations: the products are not exactly 1, and the pixel snap's
    half-pixel ties fall by them."""

    def __init__(self, n):
        W = (n / DPI) * DPI                 # the figure's bbox, px
        inv_w, inv_h = 1.0 / n, 1.0 / (0.0 - n)
        self.sx, self.tx = W * inv_w, W * (-0.0 * inv_w)
        self.sy, self.ty = W * inv_h, W * (-n * inv_h)
        self.h = float(n)                   # Agg's canvas height (matplotlib rounds the figure's px)

    def __call__(self, p):
        return (p[0] * self.sx + 0.0 + self.tx, 0.0 + p[1] * -self.sy + (-self.ty + self.h))


# matplotlib's Path.unit_circle: 8 cubic Bezier quarter-octants from (0, -1), anticlockwise
_MAGIC, _M45A, _M45B = 0.2652031, 0.5195798707848535, 0.8946336915882417
_SQH = 0.7071067811865476
_UNIT_CIRCLE = [(0.0, -1.0), (_MAGIC, -1.0), (_M45A, -_M45B), (_SQH, -_SQH), (_M45B, -_M45A), (1.0, -_MAGIC),
                (1.0, 0.0), (1.0, _MAGIC), (_M45B, _M45A), (_SQH, _SQH), (_M45A, _M45B), (_MAGIC, 1.0),
                (0.0, 1.0), (-_MAGIC, 1.0), (-_M45A, _M45B), (-_SQH, _SQH), (-_M45B, _M45A), (-1.0, _MAGIC),
                (-1.0, 0.0), (-1.0, -_MAGIC), (-_M45B, -_M45A), (-_SQH, -_SQH), (-_M45A, -_M45B), (-_MAGIC, -1.0),
                (0.0, -1.0)]


def _bezier_div(p1, p2, p3, p4, out, level=0):
    """Agg's curve4_div.recursive_bezier (approximation scale 1, no angle tolerance): the points between p1 and p4."""
    if level > 32:
        return
    x1, y1 = p1
    x2, y2 = p2
    x3, y3 = p3
    x4, y4 = p4
    x12, y12 = (x1 + x2) / 2, (y1 + y2) / 2
    x23, y23 = (x2 + x3) / 2, (y2 + y3) / 2
    x34, y34 = (x3 + x4) / 2, (y3 + y4) / 2
    x123, y123 = (x12 + x23) / 2, (y12 + y23) / 2
    x234, y234 = (x23 + x34) / 2, (y23 + y34) / 2
    x1234, y1234 = (x123 + x234) / 2, (y123 + y234) / 2
    dx, dy = x4 - x1, y4 - y1
    d2 = abs((x2 - x4) * dy - (y2 - y4) * dx)
    d3 = abs((x3 - x4) * dy - (y3 - y4) * dx)
    tol2 = 0.25
    if d2 > 1e-30 and d3 > 1e-30:
        if (d2 + d3) * (d2 + d3) <= tol2 * (dx * dx + dy * dy):
            out.append((x23, y23))
            return
    elif d2 > 1e-30:
        if d2 * d2 <= tol2 * (dx * dx + dy * dy):
            out.append((x23, y23))
            return
    elif d3 > 1e-30:
        if d3 * d3 <= tol2 * (dx * dx + dy * dy):
            out.append((x23, y23))
            return
    else:
        da = dx * dx + dy * dy
        if da == 0:
            d2 = (x1 - x2) ** 2 + (y1 - y2) ** 2
            d3 = (x4 - x3) ** 2 + (y4 - y3) ** 2
        else:
            da = 1.0 / da
            k2 = ((x2 - x1) * dx + (y2 - y1) * dy) * da
            k3 = ((x3 - x1) * dx + (y3 - y1) * dy) * da
            if 0 < k2 < 1 and 0 < k3 < 1:
                return
            d2 = (x2 - x1) ** 2 + (y2 - y1) ** 2 if k2 <= 0 else (x2 - x4) ** 2 + (y2 - y4) ** 2 if k2 >= 1 else                 (x2 - x1 - k2 * dx) ** 2 + (y2 - y1 - k2 * dy) ** 2
            d3 = (x3 - x1) ** 2 + (y3 - y1) ** 2 if k3 <= 0 else (x3 - x4) ** 2 + (y3 - y4) ** 2 if k3 >= 1 else                 (x3 - x1 - k3 * dx) ** 2 + (y3 - y1 - k3 * dy) ** 2
        if d2 > d3:
            if d2 < tol2:
                out.append((x2, y2))
                return
        elif d3 < tol2:
            out.append((x3, y3))
            return
    _bezier_div(p1, (x12, y12), (x123, y123), (x1234, y1234), out, level + 1)
    _bezier_div((x1234, y1234), (x234, y234), (x34, y34), p4, out, level + 1)


def _circle_poly(fr, c, r):
    """The circle as Agg flattens matplotlib's: the unit circle scaled and moved, to pixels, each curve divided."""
    v = [fr((c[0] + r * x, c[1] + r * y)) for x, y in _UNIT_CIRCLE]
    out = [v[0]]
    for k in range(0, 24, 3):
        _bezier_div(v[k], v[k + 1], v[k + 2], v[k + 3], out)
        out.append(v[k + 3])
    pts = []
    for p in out:
        if not pts or abs(p[0] - pts[-1][0]) > 1e-9 or abs(p[1] - pts[-1][1]) > 1e-9:
            pts.append(p)
    if abs(pts[0][0] - pts[-1][0]) <= 1e-9 and abs(pts[0][1] - pts[-1][1]) <= 1e-9:
        pts.pop()
    return pts


def _snap_value(lw):
    return 0.5 if int(math.floor(lw + 0.5)) % 2 else 0.0


def _snapped(pts, lw):
    """Agg's PathSnapper (matplotlib's path.snap, auto): a path of horizontal and vertical lines only has its vertices
    moved to the pixel grid (the centre of a pixel for an odd line width)."""
    for k in range(1, len(pts)):
        if abs(pts[k][0] - pts[k - 1][0]) >= 1e-4 and abs(pts[k][1] - pts[k - 1][1]) >= 1e-4:
            return pts
    sv = _snap_value(lw)
    return [(math.floor(x + 0.5) + sv, math.floor(y + 0.5) + sv) for x, y in pts]


def _rect(a, b, lw):
    """The stroke of segment a-b with butt caps."""
    du, dv = b[0] - a[0], b[1] - a[1]
    m = math.hypot(du, dv)
    if m < 1e-12:
        return []
    nu, nv = -dv / m * lw / 2.0, du / m * lw / 2.0
    return [(a[0] + nu, a[1] + nv), (b[0] + nu, b[1] + nv), (b[0] - nu, b[1] - nv), (a[0] - nu, a[1] - nv)]


def _offset(poly, d):
    """Convex polygon poly with every edge moved d outward, mitred."""
    s = 0.0
    for k in range(len(poly)):
        p, q = poly[k], poly[(k + 1) % len(poly)]
        s += p[0] * q[1] - q[0] * p[1]
    lines = []
    for k in range(len(poly)):
        p, q = poly[k], poly[(k + 1) % len(poly)]
        eu, ev = q[0] - p[0], q[1] - p[1]
        m = math.hypot(eu, ev)
        nu, nv = (ev / m, -eu / m) if s > 0 else (-ev / m, eu / m)     # outward
        lines.append((p[0] + nu * d, p[1] + nv * d, eu, ev))
    out = []
    for k in range(len(lines)):
        x1, y1, e1u, e1v = lines[k - 1]
        x2, y2, e2u, e2v = lines[k]
        den = e1u * e2v - e1v * e2u
        t = ((x2 - x1) * e2v - (y2 - y1) * e2u) / den
        out.append((x1 + t * e1u, y1 + t * e1v))
    return out


class Pen:
    """gen_hud.py's Pen (seg, poly, circle, dot, box) onto a Canvas."""

    def __init__(self, cv):
        self.cv = cv
        self.fr = Frame(cv.n)

    def seg(self, a, b, ls='-', lw=STROKE_PX):
        a, b = _snapped([self.fr(a), self.fr(b)], lw)
        if ls == '-':
            self.cv.paint([_rect(a, b, lw)])
            return
        on, off = ls
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        if L < 1e-12:
            return
        ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        polys, s = [], 0.0
        while s < L:
            e = min(L, s + on)
            polys.append(_rect((a[0] + ux * s, a[1] + uy * s), (a[0] + ux * e, a[1] + uy * e), lw))
            s = e + off
        self.cv.paint(polys)

    def poly(self, pts, lw=STROKE_PX):
        pts = _snapped([self.fr(p) for p in pts] + [self.fr(pts[0])], lw)[:-1]
        self._ring(pts, lw)

    def _ring(self, pts, lw):
        # Agg strokes a closed path as an outer and an inner contour of opposite winding, filled nonzero: the outer
        # polygon less the inner one -- also when the stroke is wider than the shape and the inner contour has
        # turned inside out (the shape reflected through its centre: a small hole, not a filled shape)
        self.cv.paint([_offset(pts, lw / 2.0)], [_offset(pts, -lw / 2.0)])

    def circle(self, uv, r, lw=STROKE_PX):
        self._ring(_circle_poly(self.fr, uv, r), lw)

    def dot(self, uv, r):
        self.cv.paint([_circle_poly(self.fr, uv, r)])

    def box(self, u, v, w, h):
        pts = _snapped([self.fr(p) for p in ((u, v), (u + w, v), (u + w, v + h), (u, v + h), (u, v))], 0.0)[:-1]
        self.cv.paint([pts])


# ------------------------------------------------------------------ the sprites (gen_hud.kos_sprites, in tuples)
def _unit(th):
    return (math.cos(math.radians(th)), -math.sin(math.radians(th)))


def sprite_family(name):
    fam, _, deg = name.rpartition('_')
    return fam if fam and len(deg) == 3 and deg.isdigit() else ''


def sprite_defs(g):
    """[(name, R, draw(pen, a))]: every sprite, an n = 2R + 1 square drawn about its centre pixel's centre (a, a)."""
    px = g.px
    defs = []

    def add(name, R, draw):
        defs.append((name, R, draw))

    def fd_square(pen, u, v):
        s, wing, tail = px(0.28), px(0.45), px(0.35)
        pen.poly([(u - s, v - s), (u + s, v - s), (u + s, v + s), (u - s, v + s)])
        pen.seg((u - s - wing, v), (u - s, v))
        pen.seg((u + s, v), (u + s + wing, v))
        pen.seg((u, v - s), (u, v - s - tail))

    def fpm(pen, u, v):
        r, wing, tail = px(FPM_R_DEG), px(FPM_WING_DEG), px(FPM_TAIL_DEG)
        pen.circle((u, v), r)
        pen.seg((u - r - wing, v), (u - r, v))
        pen.seg((u + r, v), (u + r + wing, v))
        pen.seg((u, v - r), (u, v - r - tail))

    def diamond(pen, u, v):
        s = px(0.3)
        pen.poly([(u, v - s), (u + s, v), (u, v + s), (u - s, v)])

    dash = (px(0.35), px(0.25))     # LADDER_DASH, in px

    def rseg(pen, a, th, s):
        u = _unit(th)
        pen.seg((a - u[0] * s / 2.0, a - u[1] * s / 2.0), (a + u[0] * s / 2.0, a + u[1] * s / 2.0))

    def rung(pen, a, th, positive):
        u = _unit(th)
        nn = (u[1], -u[0])
        toward = (-nn[0], -nn[1]) if positive else nn
        for s in (-1, 1):
            i0 = (a + s * u[0] * px(2.0), a + s * u[1] * px(2.0))
            i1 = (a + s * u[0] * px(3.5), a + s * u[1] * px(3.5))
            pen.seg(i0, i1, ls='-' if positive else dash)
            pen.seg(i1, (i1[0] + toward[0] * px(0.4), i1[1] + toward[1] * px(0.4)))

    def hz(pen, a, th):
        u = _unit(th)
        half = g.HZ_SEG_PX / 2.0 + HZ_OVL_PX
        pen.seg((a - u[0] * half, a - u[1] * half), (a + u[0] * half, a + u[1] * half))

    Rr = int(math.ceil(math.hypot(px(3.5), px(0.4)) + STROKE_PX)) + 1
    Rh = int(math.ceil(g.HZ_SEG_PX / 2.0 + HZ_OVL_PX + STROKE_PX)) + 1
    for th in range(0, 360, KOS_ANGLE_STEP):
        add('rung_p_%03d' % th, Rr, lambda pen, a, th=th: rung(pen, a, th, True))
        add('rung_n_%03d' % th, Rr, lambda pen, a, th=th: rung(pen, a, th, False))
    for th in range(0, 180, KOS_ANGLE_STEP):
        add('hz_%03d' % th, Rh, lambda pen, a, th=th: hz(pen, a, th))
    for sl in RWY_SEG_PX:
        Rs = int(math.ceil(sl / 2.0 + STROKE_PX)) + 1
        for th in range(0, 180, KOS_ANGLE_STEP):
            add('rwy%02d_%03d' % (int(sl), th), Rs, lambda pen, a, th=th, sl=sl: rseg(pen, a, th, sl))
    arm = px(0.45)

    def boresight(pen, a):
        pen.seg((a - arm, a), (a + arm, a))
        pen.seg((a, a - arm), (a, a + arm))
    add('boresight', int(math.ceil(arm + STROKE_PX)) + 1, boresight)
    add('fd', int(math.ceil(px(0.28) + px(0.45) + STROKE_PX)) + 1, lambda pen, a: fd_square(pen, a, a))
    add('fd_sq', int(math.ceil(px(0.28) + px(0.45) + STROKE_PX)) + 1,
        lambda pen, a: pen.poly([(a - px(0.28), a - px(0.28)), (a + px(0.28), a - px(0.28)),
                                 (a + px(0.28), a + px(0.28)), (a - px(0.28), a + px(0.28))]))
    add('fpm', int(math.ceil(px(0.25) + px(0.4) + STROKE_PX)) + 1, lambda pen, a: fpm(pen, a, a))
    add('diamond', int(math.ceil(px(0.3) + 2.0 * STROKE_PX)) + 1, lambda pen, a: diamond(pen, a, a))
    add('aim_circle', int(math.ceil(px(AIM_R_DEG) + STROKE_PX)) + 1, lambda pen, a: pen.circle((a, a), px(AIM_R_DEG)))
    add('dot', int(math.ceil(STROKE_PX * 0.75)) + 2, lambda pen, a: pen.dot((a, a), STROKE_PX * 0.75))
    add('thr_mark', int(math.ceil(px(0.15) + STROKE_PX)) + 1,
        lambda pen, a: pen.seg((a, a - px(0.15)), (a, a + px(0.15))))
    add('tick', int(math.ceil(px(TAPE_TICK_DEG) + STROKE_PX)) + 1,
        lambda pen, a: pen.seg((a - px(TAPE_TICK_DEG), a), (a + px(TAPE_TICK_DEG), a), lw=STROKE_PX * 0.8))
    add('gsi', int(math.ceil(px(0.4) + 2.0 * STROKE_PX)) + 1,
        lambda pen, a: pen.poly([(a, a), (a + px(0.4), a - px(0.22)), (a + px(0.4), a + px(0.22))]))
    for nm, s in (('sb_ptr_dn', -1), ('sb_ptr_up', 1)):
        add(nm, int(math.ceil(px(SB_PTR_DEG) + 2.0 * STROKE_PX)) + 1,
            lambda pen, a, s=s: pen.poly([(a, a), (a - px(0.18), a + s * px(SB_PTR_DEG)),
                                          (a + px(0.18), a + s * px(SB_PTR_DEG))]))
    ft_a = px(FLARE_TRI_DEG)
    for nm, sg in (('flare_tri_l', -1), ('flare_tri_r', 1)):
        add(nm, int(math.ceil(ft_a * 0.6 + 2.0 * STROKE_PX)) + 1,
            lambda pen, a, sg=sg: pen.poly([(a - sg * ft_a * 0.5, a), (a + sg * ft_a * 0.5, a - ft_a * 0.55),
                                            (a + sg * ft_a * 0.5, a + ft_a * 0.55)]))

    def ftri(pen, a, th):
        u = _unit(th)
        nn = (u[1], -u[0])
        pen.poly([(a + u[0] * ft_a * 0.5, a + u[1] * ft_a * 0.5),
                  (a - u[0] * ft_a * 0.5 + nn[0] * ft_a * 0.55, a - u[1] * ft_a * 0.5 + nn[1] * ft_a * 0.55),
                  (a - u[0] * ft_a * 0.5 - nn[0] * ft_a * 0.55, a - u[1] * ft_a * 0.5 - nn[1] * ft_a * 0.55)])
    Rt = int(math.ceil(math.hypot(0.5, 0.55) * ft_a + 2.0 * STROKE_PX)) + 1
    for th in range(0, 360, KOS_ANGLE_STEP):
        add('ftri_%03d' % th, Rt, lambda pen, a, th=th: ftri(pen, a, th))
    dc_h = px(DECEL_H_DEG)

    def decel_scale(pen, a):
        pen.seg((a, a), (a, a - dc_h))
        for f in (0.0, 0.25, 0.5, 0.75, 1.0):
            pen.seg((a, a - dc_h * f), (a + px(0.2), a - dc_h * f), lw=STROKE_PX * 0.8)
    add('decel_scale', int(math.ceil(dc_h + STROKE_PX)) + 1, decel_scale)

    def qa_scale(pen, a):
        pen.seg((a, a), (a, a - dc_h))
        for f in (0.0, 0.25, 0.5, 0.75, 1.0):
            pen.seg((a, a - dc_h * f), (a + px(0.2), a - dc_h * f), lw=STROKE_PX * 0.8)
        pen.seg((a, a - dc_h * QA_CAUT / QA_FULL), (a, a - dc_h * QA_LIM / QA_FULL), lw=STROKE_PX * 2.2)
        pen.seg((a, a - dc_h * QA_LIM / QA_FULL), (a + px(0.45), a - dc_h * QA_LIM / QA_FULL))
    add('qa_scale', int(math.ceil(dc_h + STROKE_PX)) + 1, qa_scale)
    for nm, side in (('decel_ptr_l', -1), ('decel_ptr_r', 1)):
        add(nm, int(math.ceil(px(0.35) + 2.0 * STROKE_PX)) + 1,
            lambda pen, a, side=side: pen.poly([(a, a), (a + side * px(0.35), a - px(0.15)),
                                                (a + side * px(0.35), a + px(0.15))]))
    bw, bh = px(0.45), px(0.2)
    add('box', int(math.ceil(max(bw, bh))) + 2, lambda pen, a: pen.box(a, a, bw, bh))
    b0, b1 = g.U0 + px(g.SB_X0_DEG), g.U0 + px(g.SB_X1_DEG)
    L = b1 - b0

    def sb_scale(pen, a):
        pen.seg((a, a), (a + L, a))
        for i in range(5):
            x = a + L * i / 4.0
            pen.seg((x, a - px(0.18)), (x, a + px(0.18)), lw=STROKE_PX * 0.8)
    add('sb_scale', int(math.ceil(L + STROKE_PX)) + 1, sb_scale)

    def pl_scale(pen, a):
        pen.seg((a, a), (a + L, a))
        for v in PL_TICKS:
            x = a + L * v / PL_FULL
            pen.seg((x, a - px(0.18)), (x, a + px(0.18)), lw=STROKE_PX * 0.8)
    add('pl_scale', int(math.ceil(L + STROKE_PX)) + 1, pl_scale)
    for nn in range(1, int(round(YAW_MAX_DEG / YAW_STEP_DEG)) + 1):
        hl = px(nn * YAW_STEP_DEG) / 2.0
        add('yawln_%02d' % nn, int(math.ceil(hl + STROKE_PX)) + 1,
            lambda pen, a, hl=hl: pen.seg((a - hl, a), (a + hl, a)))
    return defs


# ------------------------------------------------------------------ the set
def read_layout(path):
    """hud_layout.txt as [(kind, key, value text)] in order (comment lines dropped)."""
    out = []
    with open(path) as f:
        for line in f:
            tk = line.rstrip('\n').split(' ', 2)
            if len(tk) == 3 and tk[0] in ('N', 'T'):
                out.append((tk[0], tk[1], tk[2]))
    return out


def count(w, h, fov):
    """How many sprites build() draws for this screen and field of view (for a caller's progress bar)."""
    return len(sprite_defs(Geom(w, h, fov, MONO_ADV)))


def build(ref, dest, w, h, fov, log=print, tick=None):
    """Write the HUD set for a w x h screen at fov deg into dest; tick() after each sprite, when given."""
    lay = read_layout(os.path.join(ref, 'hud_layout.txt'))
    mono = float(dict((k, v) for _, k, v in lay)['MONO_ADV'])
    if abs(mono - MONO_ADV) > 1e-6:
        sys.exit('%s: MONO_ADV %g, not DejaVu Sans Mono\'s %g' % (ref, mono, MONO_ADV))
    g = Geom(w, h, fov, MONO_ADV)
    os.makedirs(dest, exist_ok=True)
    new = g.layout()
    with open(os.path.join(dest, 'hud_layout.txt'), 'w', newline='\n') as f:
        f.write('# lib_hud layout -- px on a %dx%d screen through a %.0f deg (vertical) camera; generated by '
                'hud_build.py from %s\n' % (w, h, fov, os.path.basename(os.path.normpath(ref))))
        for kind, key, val in lay:
            f.write('N %s %.6f\n' % (key, float(new[key])) if kind == 'N' and key in new else '%s %s %s\n' % (kind, key, val))
    with open(os.path.join(ref, 'hud_runways.txt'), 'rb') as f:
        rw = f.read()
    with open(os.path.join(dest, 'hud_runways.txt'), 'wb') as f:
        f.write(rw)
    rows = []
    defs = sprite_defs(g)
    for k, (name, R, draw) in enumerate(defs):
        n = 2 * R + 1
        cv = Canvas(n)
        draw(Pen(cv), n / 2.0)
        fam = sprite_family(name)
        if fam:
            os.makedirs(os.path.join(dest, fam), exist_ok=True)
        cv.png(os.path.join(dest, fam, name + '.png'))
        bb = cv.bbox() or (0, 0, 0, 0)
        rows.append('%s %d %.1f %.1f %d %d %d %d%s' % ((name, n, R + 0.5, R + 0.5) + tuple(bb)
                                                       + ((' ' + fam) if fam else '',)))
        if tick:
            tick()
        if log and (k + 1) % 200 == 0:
            log('  %d of %d sprites' % (k + 1, len(defs)))
    with open(os.path.join(dest, 'sprites.txt'), 'w', newline='\n') as f:
        f.write('# name size_px anchor_x anchor_y ink_l ink_t ink_r ink_b folder  (px from the top-left; ink r/b '
                'exclusive; folder: the sub-folder of a rotated family)\n')
        f.write('\n'.join(sorted(rows)) + '\n')
    _write_png(os.path.join(dest, 'clear.png'), 4, 4, b''.join(b'\x00' + b'\x00' * 16 for _ in range(4)))
    return len(defs)


def main(argv):
    args = list(argv)
    w, h, fov = 3840, 2160, 60.0
    if '--screen' in args:
        i = args.index('--screen')
        w, h = (int(x) for x in args[i + 1].lower().split('x'))
        del args[i:i + 2]
    if '--fov' in args:
        i = args.index('--fov')
        fov = float(args[i + 1])
        del args[i:i + 2]
    if len(args) != 2 or not 30.0 <= fov <= 90.0:
        sys.exit(__doc__)
    n = build(args[0], args[1], w, h, fov)
    print('%s: %d sprites, hud_layout.txt, hud_runways.txt (%dx%d, %g deg)' % (args[1], n, w, h, fov))


if __name__ == '__main__':
    main(sys.argv[1:])
