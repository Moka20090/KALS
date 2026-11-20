"""Draws the five ENTRY TRAJ background panels (traj1..5.png) and the sidecar traj_bg.txt the game needs to use them.

    python gen_traj_bg.py family.txt [outdir] [scale]

Reads family.txt (written by fam_build.ks on the coast) and writes the PNGs and traj_bg.txt into outdir (default: the
current folder). A panel holds the frame, the strip scales, the readout labels, the guided bank lines and the dashed
constant-drag lines; the game positions the live symbols over it. traj_bg.txt gives, in pixels, the plot field, the
readout rows, the clock and the strip scales inside the PNGs and, per panel, the data window it spans. A panel on a
non-default alpha scale is written as traj<n>_a<lo>-<hi>.png: the game caches images by path and must not keep showing a
picture of another scale.

The scale is the third argument, else $TRAJ_SCALE, else 0.667 (736 x 460 px, the size the shipped sprites are drawn for).
Before the sidecar is written the PNGs are read back and checked against it; a failed check prints why and exits 1.
Needs numpy, Pillow and matplotlib.
"""
import math
import os
import sys

FIG_W, FIG_H = 9.6, 6.0             # panel size at scale 1, in
BASE_DPI = 115.0                    # dots per inch at scale 1
DEFAULT_SCALE = 0.667               # panel scale when none is given
FIELD = [0.208, 0.095, 0.772, 0.735]    # plot field: left, bottom, width, height (figure fractions)
V_PAD_PX = 30.0                     # the orbiter bug's height plus a little: px at scale 1
                                    #   (20 at 0.667) the band sits inside the field's top and bottom: the bug (17 px
                                    #   tall at 1, 11.4 at 0.667) clear of traj_display's 14 px offscale inset at a
                                    #   panel switch. The sidecar's v_pad_px; C# TrajBg.V_PAD_PX the same
BG = '#070a07'                      # background: near-black
FG = '#3ce03c'                      # lines, scales and readout labels: green
FS = 1.22                           # multiplier on every font size
TXT_FS = 8.5                        # EVERY label's size, one character size as the orbiter's CRT: TAEM's 8.5
                                    #   (gen_taem_bg _txt) = 11 px at 0.667 = the readout values (traj_display TJ_TL_FONT /
                                    #   TJ_BR_FONT, in the labels' own face DejaVu Sans Mono Bold), so the page matches the others
HEAD_FS, TITLE_FS, LINE_FS = 10.0, 11.5, 7.5    # TAEM's page id, title and line labels (S-TURN, NOMINAL)
TEXT_WEIGHT = 'bold'                # all page text bold, as TAEM's (gen_taem_bg TEXT_WEIGHT)
LW = 3.0 * 26.0 / 25.0 * 72.0 / (BASE_DPI * DEFAULT_SCALE)   # TAEM's stroke (gen_taem_bg LW: the VERT SIT
                                    #   bug's outline, 3.1 px at 0.667), in pt so it scales: the frame and the strips
CURVE_LW = LW * 0.78                # the family's lines at the symbols' standard stroke (2.4 px; the frame and the
                                    #   strips at 3.1 px)

SLO, SHI = 0.085, 0.855             # bottom and top of the two strip scales (figure fraction)
A_STRIP_X = 0.086                   # alpha strip spine (figure fraction)
D_STRIP_X = 0.158                   # drag strip spine (the drag strip's "100" at TXT_FS clears the
                                    #   alpha strip's ticks; the game reads both from the sidecar)
A_LAB_OFF = 0.042                   # the alpha numbers are right-aligned this far left of its spine
A_TICKS = [25, 30, 35, 40, 45, 50]                  # alpha strip scale, deg
A_TICKS_BY_PANEL = {5: [10, 15, 20, 25, 30, 35]}    # panel 5 flies the low end of the AoA ramp, below the default scale
D_TICKS = [0, 10, 20, 30, 40, 50]                   # drag strip scale, ft/s2
D_LAB_OFF, D_LAB_FS = 0.022, TXT_FS  # the drag numbers' offset left of the spine and their font size
# $TRAJ_DMAX 100 (the TAL pages, whose drag runs higher) draws the drag strip 0..100 (majors every 20) with its numbers
# at font 7, 0.016 off the spine, so "100" clears the alpha strip's ticks; unset or 50 = the 0..50 strip (the
# deorbit pages)
import os as _os
if _os.environ.get('TRAJ_DMAX', '50') == '100':
    D_TICKS, D_LAB_OFF, D_LAB_FS = [0, 20, 40, 60, 80, 100], 0.016, TXT_FS
# $TRAJ_NO_DRAG 1 (the generic TAL panels in tal/) draws no dashed drag lines; unset = the six per panel
DRAG_LINES_ON = _os.environ.get('TRAJ_NO_DRAG', '') != '1'
MINOR_PER_MAJOR = 5                 # minor-tick intervals between strip numbers
DEFAULT_ASCALE = (A_TICKS[0], A_TICKS[-1])          # a panel on this alpha scale keeps the plain traj<n>.png name

TL_LABELS = ['U', 'D REF', r'$\overline{q}$', r'$\Delta$ AZ', 'DB']     # top-left readouts; the game draws the values
TL_Y = [0.845 - i*0.045 for i in range(len(TL_LABELS))]                 # their rows (figure fraction from the bottom)
# row 5 is MACH
BR_LABELS = [r'$\dot{H}$ BIAS', 'ROLL REF', 'CMD', 'BANK', 'MACH', 'H', r'$\dot{H}$', 'TRIM', 'LOAD FAC']   # bottom right
BR_BOTTOM, BR_PITCH = 0.075, 0.0345             # row of the last label, and the row spacing (figure fraction)
BR_Y = [BR_BOTTOM + (len(BR_LABELS) - 1 - i)*BR_PITCH for i in range(len(BR_LABELS))]
TL_RIGHT, BR_RIGHT = 0.335, 0.968   # right edges of the two value columns (figure fraction)
BR_BOX = (0.794, 0.060, 0.982, 0.385)   # the opaque box behind the bottom-right readouts, labels and values (left,
                                    #   bottom, right, top; figure fraction, snapped to whole pixels): drawn over the
                                    #   lines, so none runs through the readouts
CLOCK_RIGHT, CLOCK_TOP = 0.905, 0.065   # MET clock: right edge, and baseline row measured from the top (figure fraction)

PANEL_FRACS = [0.0, 0.344, 0.480, 0.638, 0.833, 1.0]    # panel boundaries as fractions of the guided-entry speed span
PHASE_34_V = 2000.0                 # m/s; the TRAJ 3/4 boundary sits where the AoA ramp starts
ZOOM_X1 = {1: 1.4, 2: 1.955, 3: 1.9, 4: 1.4, 5: 1.4}    # stretch of the long-range edge: clears the lower-right readouts
ZOOM_X0 = {1: 0.15, 2: 0.25, 3: 0.20, 4: 0.0, 5: 0.0}   # extension of the short-range edge (fraction of the window)
PREENTRY_GUARD = 62.0               # deg; a flown bank under the commanded one is an Nz arrest only above this
LINE_STEPS = 120                    # intervals in each drawn bank line
N_DRAG_LINES = 6                    # dashed constant-drag lines per panel
FAMILY_VERSION = 1                  # family.txt format version
AOA_HIGH, AOA_LOW = 40.0, 15.0      # deg; commanded AoA at and above AOA_HIGH_SPEED, and at AOA_LOW_SPEED
AOA_HIGH_SPEED, AOA_LOW_SPEED = 2000.0, 762.0   # m/s


def read_family(path):
    """family.txt -> (header dict, members); member = (bank deg, [(vrel m/s, drag m/s2, sink, range m, flown bank deg)])."""
    hdr = {}
    members = []
    cur = None
    with open(path) as f:
        for raw in f:
            raw = raw.strip()
            if not raw:
                continue
            parts = raw.split()
            if parts[0] == 'M':
                if cur is not None:
                    members.append(cur)
                cur = (float(parts[2]), [])
            elif cur is not None and len(parts) >= 5:
                cur[1].append(tuple(float(x) for x in parts[:5]))
            elif len(parts) >= 2:
                if parts[0] == 'vessel':
                    hdr['vessel'] = ' '.join(parts[1:])
                elif len(parts) == 2:
                    hdr[parts[0]] = float(parts[1])
                else:
                    hdr[parts[0]] = [float(x) for x in parts[1:]]
    if cur is not None:
        members.append(cur)
    return hdr, members


def validate_family(hdr, members):
    """The reason the family cannot be used, or '' when it can."""
    if hdr.get('version') != FAMILY_VERSION:
        return 'unknown version'
    for k in ('tcoast', 'geo_t0', 'tbuild', 'r0', 'v0', 'plan_burn_ut', 'plan_aim', 'members', 'aero_ver'):
        if k not in hdr:
            return 'missing key ' + k
    if len(members) < 2:
        return 'only %d member(s)' % len(members)
    if len(members) != int(hdr['members']):
        return 'header says %d members, found %d' % (int(hdr['members']), len(members))
    for i in range(1, len(members)):
        if members[i][0] < members[i-1][0]:
            return 'members not in bank order'
    return ''


def aoa_schedule(v):
    """Commanded AoA (deg) at relative speed v (m/s): flat above AOA_HIGH_SPEED, linear down to AOA_LOW at AOA_LOW_SPEED."""
    if v >= AOA_HIGH_SPEED:
        return AOA_HIGH
    frac = min(max((v - AOA_LOW_SPEED) / (AOA_HIGH_SPEED - AOA_LOW_SPEED), 0.0), 1.0)
    return AOA_LOW + (AOA_HIGH - AOA_LOW) * frac


def panel_bands(v_init, v_taem):
    """The five panels' (vhi, vlo) velocity bands, m/s, from the guided-entry speed span."""
    span = v_init - v_taem
    fr = PANEL_FRACS
    if span > 0:
        target = (v_init - PHASE_34_V) / span           # where the 3/4 boundary should sit
        old34 = PANEL_FRACS[3]
        if 0.0 < target < 1.0:
            fr = [f * target / old34 if f <= old34 else target + (f - old34) * (1.0 - target) / (1.0 - old34)
                  for f in PANEL_FRACS]
    return [(v_init - fr[n]*span, v_init - fr[n+1]*span) for n in range(5)]


def row_at(rows, v, col):
    """Column col of a member's rows at velocity v: linear between rows (high velocity first), clamped at both ends."""
    if v >= rows[0][0]:
        return rows[0][col]
    if v <= rows[-1][0]:
        return rows[-1][col]
    for i in range(1, len(rows)):
        if rows[i][0] <= v:
            a, b = rows[i - 1], rows[i]
            f = (a[0] - v) / max(a[0] - b[0], 1e-9)
            return a[col] + (b[col] - a[col]) * f
    return rows[-1][col]


def v_pad(vhi, vlo, ph, pad):
    """The velocity (m/s) a pad of pad px adds above vhi and below vlo in a field ph px tall."""
    return pad / (ph - 2.0*pad) * (vhi - vlo)


def family_lines(fam, vlo):
    """Each member as (bank, [(v, range m)]): LINE_STEPS + 1 points from its top velocity down to max(vlo, its lowest)."""
    out = []
    for bank, rows in fam:
        top = max(r[0] for r in rows)
        lo = max(vlo, min(r[0] for r in rows))
        pts = []
        for i in range(LINE_STEPS + 1):
            v = top + (lo - top) * i / LINE_STEPS
            pts.append((v, row_at(rows, v, 3)))
        out.append((bank, pts))
    return out


def drag_ladder(fam, vhi, vlo):
    """N_DRAG_LINES geometrically spaced drag targets (ft/s2) across the members' drag span at the band's mid velocity."""
    vmid = 0.5*(vhi + vlo)
    vals = [row_at(rows, vmid, 1)*3.28084 for _, rows in fam]
    lo, hi = min(vals), max(vals)
    lo, hi = lo*1.12, hi*0.94           # pulled in: a target at the span's edge exists over a vanishing velocity window
    if hi <= lo:
        return []
    return [lo * (hi/lo) ** (k/(N_DRAG_LINES-1)) for k in range(N_DRAG_LINES)]


def drag_loci(fam, drags_ft, vlo, vhi, step=20.0):
    """Constant-drag loci {ft/s2: [(v, range m)]}, stepping down from vhi where the target is inside the members' drag span."""
    out = {}
    for dt_ft in drags_ft:
        dt = dt_ft / 3.28084            # the family stores m/s2
        pts = []
        v = vhi
        while v > vlo:
            col = [(row_at(rows, v, 1), row_at(rows, v, 3)) for _, rows in fam]
            dmin = min(c[0] for c in col)
            dmax = max(c[0] for c in col)
            if dmin + 1e-3 < dt < dmax - 1e-3:      # margin: drag is only nearly monotone across members
                hit = None
                for i in range(1, len(col)):        # the last bracketing pair wins
                    d0, r0 = col[i-1]
                    d1, r1 = col[i]
                    if (d0 - dt) * (d1 - dt) <= 0 and abs(d1 - d0) > 1e-6:
                        hit = r0 + (dt - d0) / (d1 - d0) * (r1 - r0)
                if hit is not None:
                    pts.append((v, hit))
            v -= step
        if len(pts) >= 3:
            out[dt_ft] = pts
    return out


def fsz(base):
    """A font size scaled by FS."""
    return base * FS


def strip(ax, x, lo, hi, ticks, label, ticks_left=False, lab_off=0.022, lab_fs=TXT_FS):
    """One vertical strip scale at x spanning lo..hi (figure fractions): spine, minor and major ticks, numbers, title."""
    sgn = -1.0 if ticks_left else 1.0               # minor ticks go left of the spine for the drag strip
    ax.plot([x, x], [lo, hi], color=FG, lw=LW, zorder=5, solid_capstyle='butt')
    ax.annotate(label, xy=(x, hi + (hi-lo)*0.045), color=FG, fontsize=fsz(TXT_FS),
                ha='center', va='bottom', zorder=5, annotation_clip=False)
    span = ticks[-1] - ticks[0]
    n_minor = MINOR_PER_MAJOR*(len(ticks)-1)
    for i in range(n_minor + 1):
        v = ticks[0] + span*i/n_minor
        y = lo + (hi-lo)*(v-ticks[0])/span
        ax.plot([x, x + sgn*0.010], [y, y], color=FG, lw=LW, zorder=5, solid_capstyle='butt')
    for t in ticks:
        y = lo + (hi-lo)*(t-ticks[0])/span
        ax.plot([x - (0.014 if sgn < 0 else 0.010), x + (0.010 if sgn < 0 else 0.014)],
                [y, y], color=FG, lw=LW, zorder=5, solid_capstyle='butt')
        ax.annotate('%g' % t, xy=(x - lab_off, y), color=FG, fontsize=fsz(lab_fs),
                    ha='right', va='center', zorder=5, annotation_clip=False)


def outward(k0, n):
    """The indices 0..n-1 from k0 outward: k0, k0+1, k0-1, k0+2, k0-2, ..."""
    out = [k0]
    for d in range(1, n):
        if k0 + d < n:
            out.append(k0 + d)
        if k0 - d >= 0:
            out.append(k0 - d)
    return out


class LabelSpace:
    """Free space on the plot field (boxes and polylines, in axes fractions), so a label can be placed clear of what is there."""

    def __init__(self, ax):
        self.ax = ax
        self.boxes = []
        self.polys = []
        self.w_pt = FIELD[2] * FIG_W * 72.0         # field size in points, to estimate text extents
        self.h_pt = FIELD[3] * FIG_H * 72.0

    def _frac(self, x, y):
        """Data point -> axes fractions."""
        x0, x1 = self.ax.get_xlim()
        y0, y1 = self.ax.get_ylim()
        return (x - x0)/(x1 - x0), (y - y0)/(y1 - y0)

    def text_size(self, txt, fontsize):
        """Estimated (width, height) of a label in axes fractions."""
        return (len(txt) + 1.2) * fontsize * 0.62 / self.w_pt, fontsize * 1.55 / self.h_pt

    def reserve_box(self, xf, yf, w, h):
        """Occupy a w x h box centred on (xf, yf)."""
        self.boxes.append((xf - w/2, yf - h/2, xf + w/2, yf + h/2))

    def reserve_rect(self, x0f, y0f, x1f, y1f):
        """Occupy a rectangle."""
        self.boxes.append((x0f, y0f, x1f, y1f))

    def reserve_poly(self, pts_data):
        """Mark a polyline (data points) as a line labels should avoid."""
        self.polys.append([self._frac(x, y) for x, y in pts_data])

    def _hits_box(self, b):
        for o in self.boxes:
            if not (b[2] < o[0] or b[0] > o[2] or b[3] < o[1] or b[1] > o[3]):
                return True
        return False

    def _hits_poly(self, b):
        # coarse: a segment hits if an end or its midpoint is inside, the lines being dense and the boxes small
        for poly in self.polys:
            for i in range(1, len(poly)):
                ax_, ay = poly[i-1]
                bx_, by = poly[i]
                if (b[0] <= ax_ <= b[2] and b[1] <= ay <= b[3]) or \
                   (b[0] <= bx_ <= b[2] and b[1] <= by <= b[3]):
                    return True
                if min(ax_, bx_) <= b[2] and max(ax_, bx_) >= b[0] and \
                   min(ay, by) <= b[3] and max(ay, by) >= b[1]:
                    mx, my = 0.5*(ax_+bx_), 0.5*(ay+by)
                    if b[0] <= mx <= b[2] and b[1] <= my <= b[3]:
                        return True
        return False

    def place(self, txt, cands, fontsize):
        """The first candidate (x, y, dx_pt, dy_pt) clear of everything, else the first touching only lines, else the first."""
        w, h = self.text_size(txt, fontsize)
        fallback = None
        for (x, y, dx, dy) in cands:
            xf, yf = self._frac(x, y)
            xf += dx / self.w_pt
            yf += dy / self.h_pt
            if not (0.0 <= xf <= 1.0 and 0.0 <= yf <= 1.0):
                continue
            box = (xf - w/2, yf - h/2, xf + w/2, yf + h/2)
            if self._hits_box(box):
                continue
            if self._hits_poly(box):
                if fallback is None:
                    fallback = (x, y, dx, dy, xf, yf, w, h)
                continue
            self.reserve_box(xf, yf, w, h)
            return x, y, dx, dy
        if fallback is not None:
            x, y, dx, dy, xf, yf, w, h = fallback
            self.reserve_box(xf, yf, w, h)
            return x, y, dx, dy
        return cands[0]


def _new_figure():
    """A blank panel figure (pyplot imported on first use: the watcher imports this file for the family reader only)."""
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    plt.rcParams['font.family'] = 'DejaVu Sans Mono'
    plt.rcParams['font.weight'] = TEXT_WEIGHT            # bold, the symbols in the same face
    plt.rcParams['mathtext.fontset'] = 'custom'
    plt.rcParams['mathtext.rm'] = 'DejaVu Sans Mono:bold'
    plt.rcParams['mathtext.it'] = 'DejaVu Sans Mono:italic:bold'
    plt.rcParams['mathtext.bf'] = 'DejaVu Sans Mono:bold'
    return plt, plt.figure(figsize=(FIG_W, FIG_H), facecolor=BG)


def _draw_frame(fig, panel):
    """Everything on a panel that does not depend on the family (the frame, header, strips, top-left readout labels),
    on a whole-figure axes drawn under the plot field; returns the alpha strip's ticks. The KAL/S addon's templates
    (gen_traj_tpl.py) are this and _draw_readouts: the addon draws the family's lines and labels over it, then copies
    the readout box back from the template."""
    from matplotlib.patches import FancyBboxPatch
    fr = fig.add_axes([0, 0, 1, 1])     # whole-figure axes: frame, header, strips, readout labels
    fr.set_axis_off()
    fr.set_xlim(0, 1)
    fr.set_ylim(0, 1)
    fr.add_patch(FancyBboxPatch((0.012, 0.02), 0.976, 0.955, boxstyle='round,pad=0.004,rounding_size=0.022',
                                fill=False, ec=FG, lw=LW, transform=fr.transAxes))
    fr.annotate('3041/', xy=(0.075, 0.935), fontsize=fsz(HEAD_FS), color=FG, ha='center')
    fr.annotate('/', xy=(0.175, 0.935), fontsize=fsz(HEAD_FS), color=FG, ha='center')
    fr.annotate('ENTRY TRAJ %d' % panel, xy=(0.44, 0.935), fontsize=fsz(TITLE_FS), color=FG, ha='center')
    # the MET clock ticks, so the header leaves its place blank for the game to draw

    a_ticks = list(A_TICKS_BY_PANEL.get(panel, A_TICKS))
    strip(fr, A_STRIP_X, SLO, SHI, a_ticks, r'$\alpha$', lab_off=A_LAB_OFF)
    strip(fr, D_STRIP_X, SLO, SHI, D_TICKS, 'D', ticks_left=True, lab_off=D_LAB_OFF, lab_fs=D_LAB_FS)
    for label, y in zip(TL_LABELS, TL_Y):       # only the labels are baked in; the game draws the values
        fr.annotate(label, xy=(0.205, y), fontsize=fsz(TXT_FS), color=FG, ha='left')
    return a_ticks


def _box_px(dpi):
    """BR_BOX in whole pixels at dpi: (x0, y0, x1, y1) display px from the bottom left (TrajBg.cs BoxPx the same)."""
    return tuple(int(round(f * s)) for f, s in zip(BR_BOX, (FIG_W*dpi, FIG_H*dpi, FIG_W*dpi, FIG_H*dpi)))


def _draw_readouts(fig, dpi):
    """The bottom-right readout labels on an opaque box in the background colour, on a whole-figure axes added last, so
    it lies over the plot field's lines. The box covers whole pixels (no antialiasing), so its pixels are the same on
    every panel and in the template."""
    from matplotlib.patches import Rectangle
    ov = fig.add_axes([0, 0, 1, 1])
    ov.set_axis_off()
    ov.set_xlim(0, 1)
    ov.set_ylim(0, 1)
    pw, ph = FIG_W*dpi, FIG_H*dpi
    x0, y0, x1, y1 = _box_px(dpi)
    ov.add_patch(Rectangle((x0/pw, y0/ph), (x1 - x0)/pw, (y1 - y0)/ph, transform=ov.transAxes, fc=BG, ec='none',
                           lw=0, antialiased=False, snap=False))
    for label, y in zip(BR_LABELS, BR_Y):       # the game draws the values over the box
        ov.annotate(label, xy=(0.800, y), fontsize=fsz(TXT_FS), color=FG, ha='left')


def _round_panel(path):
    """T706: the committed pages' corner pass (tools/screen_corners.py), so the watcher's panels match the run-time ones (TjCorners)."""
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tools'))
    import screen_corners
    screen_corners.round_file(path)


def draw_template(panel, path, dpi):
    """The panel's family-independent under-layer alone (see _draw_frame), saved to path."""
    plt, fig = _new_figure()
    _draw_frame(fig, panel)
    _draw_readouts(fig, dpi)
    fig.savefig(path, dpi=dpi, facecolor=BG)
    plt.close(fig)


def draw_panel(fam, lines, vhi, vlo, panel, path, dpi, arrest_v, vpad=0.0):
    """Draw one background panel to path; returns the range window (x0, x1 km), alpha scale and drag scale it drew.
    The field shows the band vhi..vlo widened by vpad m/s each side (v_pad)."""
    plt, fig = _new_figure()
    a_ticks = _draw_frame(fig, panel)

    ax = fig.add_axes(FIELD)
    ax.set_axis_off()

    # range window: from just short of the shortest member at the band's bottom to just past the longest at its top
    vs_all = [v for _, pts in lines for v, _r in pts]
    v_min, v_max = min(vs_all), max(vs_all)

    def span(v):
        """(shortest, longest) member range in m at velocity v, clamped to where the lines have data."""
        v = min(max(v, v_min), v_max)
        rs = []
        for _, pts in lines:
            near = [r for vv, r in pts if abs(vv - v) < 45]
            if near:
                rs.append(sum(near)/len(near))
        if not rs:
            rs = [min(pts, key=lambda t: abs(t[0] - v))[1] for _, pts in lines]
        return min(rs), max(rs)

    # the last panel ends at the handover, where the bug and the lines end; its left edge is taken at the field's
    # bottom (vlo - vpad) and not moved in, so neither runs out through it (else the bug drifts across the lines
    # toward the handover)
    last = panel == 5
    x0 = max(0.0, span(vlo - vpad if last else vlo)[0]/1000.0 * 0.88)
    x1 = span(vhi)[1]/1000.0 * 1.04
    w = x1 - x0
    x1 = x0 + w*ZOOM_X1[panel]
    x0 = max(0.0, x0 - w*ZOOM_X0[panel])
    for keep in (0.70, 0.95, 0.95):     # crop the long-range edge to what the lines occupy
        x1 = x0 + (x1 - x0) * keep
    if not last:
        x0 = x0 + (x1 - x0) * 0.05
    ax.set_xlim(x0, x1)
    ylo, yhi = vlo - vpad, vhi + vpad      # the band inset by the pad
    ax.set_ylim(ylo, yhi)
    xl0, xl1 = ax.get_xlim()
    yl0, yl1 = ax.get_ylim()

    ls = LabelSpace(ax)
    ls.reserve_rect(-0.05, 0.80, 0.30, 1.05)        # top-left readout block
    ls.reserve_rect(0.70, -0.05, 1.05, 0.46)        # bottom-right readout block
    for _, pts in lines:
        seg = [(r/1000.0, v) for v, r in pts if ylo <= v <= yhi]
        if len(seg) >= 2:
            ls.reserve_poly(seg)

    # dashed constant-drag lines, each labelled at the first clear spot along it from its high-velocity end (none
    # with $TRAJ_NO_DRAG 1)
    for dv, pts in (drag_loci(fam, drag_ladder(fam, vhi, vlo), ylo, yhi) if DRAG_LINES_ON else {}).items():
        seg = [(v, r) for v, r in pts if ylo <= v <= yhi]
        if len(seg) < 3:
            continue
        ax.plot([r/1000 for _, r in seg], [v for v, _ in seg], color=FG, lw=CURVE_LW,
                ls=(0, (4.8/LW, 3.2/LW)), zorder=3)
        ordered = sorted(seg, key=lambda p: -p[0])
        cands = []
        for frac in (0.0, 0.06, 0.13, 0.22, 0.32, 0.45, 0.60, 0.78):
            k = min(len(ordered)-1, int(frac*len(ordered)))
            lx, ly = ordered[k][1]/1000.0, ordered[k][0]
            for dx, dy in ((14, 9), (14, 20), (-14, 9), (14, -10), (-14, -10)):
                cands.append((lx, ly, dx, dy))
        lx, ly, dx, dy = ls.place('%.0fD' % dv, cands, fsz(LINE_FS))
        ax.annotate('%.0fD' % dv, xy=(lx, ly), xytext=(dx, dy), textcoords='offset points',
                    fontsize=fsz(LINE_FS), color=FG, ha='center', va='center', zorder=4,
                    bbox=dict(fc=BG, ec='none', pad=0.6))

    # solid bank lines, the two limits heavier, each labelled on its own line
    for i, (bank, pts) in enumerate(lines):
        seg = [(v, r) for v, r in pts if ylo <= v <= yhi]
        if len(seg) < 3:
            continue
        lim = (i == 0 or i == len(lines)-1)
        ax.plot([r/1000 for _, r in seg], [v for v, _ in seg], color=FG, lw=CURVE_LW, zorder=5)   # the standard stroke
        if i == len(lines) - 1 and arrest_v is not None:
            # the max-bank line is bank-limited above arrest_v and Nz-limited (G-LIM) below it; both names, a notch between
            bank_seg = [(v, r) for v, r in seg if v >= arrest_v]
            glim_seg = [(v, r) for v, r in seg if v < arrest_v]
            for sg, txt in ((bank_seg, '%d' % bank), (glim_seg, 'G-LIM')):
                if len(sg) >= 3:
                    # from the middle point outward, the first spot clear of the blocks and labels
                    cands = [(sg[k][1]/1000, sg[k][0], -19, -7) for k in outward(len(sg)//2, len(sg))]
                    lx, ly, dx, dy = ls.place(txt, cands, fsz(LINE_FS))
                    ax.annotate(txt, xy=(lx, ly), xytext=(dx, dy), textcoords='offset points',
                                fontsize=fsz(LINE_FS), color=FG, ha='center', va='center', zorder=6,
                                bbox=dict(fc=BG, ec='none', pad=1.0))
            if bank_seg and glim_seg:
                pa = min(bank_seg, key=lambda t: t[0])          # lowest velocity still bank-limited
                pb = max(glim_seg, key=lambda t: t[0])          # highest velocity already arrested
                dxn = ((pa[1] - pb[1])/1000.0) / (xl1 - xl0)    # line direction in figure-normalised units
                dyn = (pa[0] - pb[0]) / (yl1 - yl0)
                mag = math.hypot(dxn, dyn)
                if mag > 1e-9:
                    half = 0.016                                # half-length of the notch (figure fraction)
                    nx, ny = -dyn/mag, dxn/mag                  # perpendicular
                    cx = 0.5*(pa[1] + pb[1])/1000.0
                    cy = 0.5*(pa[0] + pb[0])
                    ax.plot([cx - nx*half*(xl1-xl0), cx + nx*half*(xl1-xl0)],
                            [cy - ny*half*(yl1-yl0), cy + ny*half*(yl1-yl0)],
                            color=FG, lw=LW, zorder=6, solid_capstyle='butt')
            continue
        vis = [(v, r) for v, r in seg if xl0 <= r/1000 <= xl1]
        if not vis:
            continue
        # labels run along a diagonal across the fan: high bank high on its line, low bank low
        frac = i / max(1, len(lines)-1)
        vtarget = vhi - (vhi - vlo)*(0.78 - 0.56*frac)
        pick = min(range(len(vis)), key=lambda k: abs(vis[k][0] - vtarget))
        # that spot first, then the line's points outward from it: the first clear of the readout blocks and
        # the labels already placed (an unchecked spot can land the "0" on BANK)
        lx, ly, _, _ = ls.place('%d' % bank, [(vis[k][1]/1000, vis[k][0], 0, 0) for k in outward(pick, len(vis))],
                                fsz(LINE_FS))
        ax.annotate('%d' % bank, xy=(lx, ly), fontsize=fsz(LINE_FS), color=FG,
                    ha='center', va='center', zorder=6, bbox=dict(fc=BG, ec='none', pad=1.0))

    _draw_readouts(fig, dpi)
    fig.savefig(path, dpi=dpi, facecolor=BG)
    _round_panel(path)
    plt.close(fig)
    return (x0, x1), (a_ticks[0], a_ticks[-1]), (D_TICKS[0], D_TICKS[-1])


def _verify(outdir, fam, panels, px, py, pw, ph, tol=6.0, pad=0.0):
    """Read each PNG back: the description of the first member line not within tol px of where the sidecar puts it, or ''."""
    import numpy as np
    from PIL import Image

    for (n, vhi, vlo, x0, x1, name, _asc, _dsc) in panels:
        a = np.array(Image.open(os.path.join(outdir, name)).convert('RGB'))
        # three rows, a fifth of the way down the field and 6 % of its height either side; a member line is
        # refused only when it is missing on more than one of the rows it crosses (a label's box, ~14 px tall, blanks
        # a line on at most one, so a one-row check refuses correct panels)
        seen = {}
        for frac in (0.15, 0.21, 0.27):
            row = int(round(py + frac*ph))
            vp = v_pad(vhi, vlo, ph, pad)       # the field's rows span the padded band
            v = (vhi + vp) - frac*((vhi + vp) - (vlo - vp))
            g = a[row, :, 1]
            xs = [x for x in range(int(px)+15, a.shape[1]) if g[x] > 40]
            grp = []
            for x in xs:
                if grp and x - grp[-1][-1] <= 2:
                    grp[-1].append(x)
                else:
                    grp.append([x])
            drawn = [(gp[0] + gp[-1]) / 2.0 for gp in grp]      # each run's centre: its first pixel sits half a line
                                                                # width left, and more where a line runs flat
            runs = [(gp[0], gp[-1]) for gp in grp]              # lines that cross or crowd join into one run
            if not drawn:
                return 'panel %d: nothing drawn at row %d' % (n, row)
            for bank, rows in fam:
                if int(bank) == 12:
                    continue
                r = row_at(rows, v, 3)/1000.0
                if not (x0 <= r <= x1):
                    continue
                want = px + ((r - x0)/(x1 - x0))*pw
                s = seen.setdefault(int(bank), [0, 0, ''])
                s[0] += 1
                inside = any(a0 <= want <= a1 for a0, a1 in runs)
                if not inside and min(abs(want - d) for d in drawn) > tol:
                    s[1] += 1
                    if not s[2]:
                        s[2] = ('panel %d: bank %d should be at x %.0f (row %d) but no line is within %.0f px'
                                % (n, int(bank), want, row, tol))
        for bank in sorted(seen):
            s = seen[bank]
            if s[1] > 1 or (s[1] == 1 and s[0] == 1):
                return s[2]
    return ''


def _verify_strip_labels(outdir, panels):
    """The first pair of panels whose alpha labels look the same under different scales or differ under the same, or ''."""
    # tick marks sit on the same pixel rows on every panel, so the printed numbers (the column left of the strip) are read
    import numpy as np
    from PIL import Image

    crops = {}
    for (n, vhi, vlo, x0, x1, name, asc, _dsc) in panels:
        a = np.array(Image.open(os.path.join(outdir, name)).convert('L'))
        H, W = a.shape
        x_hi = int((A_STRIP_X - A_LAB_OFF + 0.002) * W)
        x_lo = max(0, x_hi - int(0.046 * W))
        y_lo, y_hi = int(0.10 * H), int(0.95 * H)
        crops[n] = (a[y_lo:y_hi, x_lo:x_hi], tuple(asc))

    for n in sorted(crops):
        for m in sorted(crops):
            if m <= n:
                continue
            same_pix = bool((crops[n][0] == crops[m][0]).all())
            same_scale = crops[n][1] == crops[m][1]
            if same_scale and not same_pix:
                return ('panels %d and %d claim the same alpha scale %s but their labels differ'
                        % (n, m, crops[n][1]))
            if not same_scale and same_pix:
                return ('panels %d and %d claim different alpha scales %s and %s but their '
                        'labels are PIXEL-IDENTICAL -- the tick set never reached the drawing'
                        % (n, m, crops[n][1], crops[m][1]))
    return ''


def main():
    """Draw the panels and the sidecar for the files named on the command line; returns the exit code."""
    fpath = sys.argv[1] if len(sys.argv) > 1 else 'family.txt'
    outdir = sys.argv[2] if len(sys.argv) > 2 else '.'
    scale = float(sys.argv[3]) if len(sys.argv) > 3 else float(os.environ.get('TRAJ_SCALE', DEFAULT_SCALE))
    hdr, fam = read_family(fpath)
    why = validate_family(hdr, fam)
    if why:
        print('REFUSING: %s' % why)
        return 1
    vinit = max(r[0] for _, rows in fam for r in rows)
    vtaem = hdr.get('taem_vel', 762.0)
    print('%s: %d members, v_init %.0f, TAEM %.0f, aero %.1f, written %.1f'
          % (os.path.basename(fpath), len(fam), vinit, vtaem, hdr['aero_ver'], hdr['written']))
    print('scale %.3f -> panels %.0fx%.0f' % (scale, FIG_W*BASE_DPI*scale, FIG_H*BASE_DPI*scale))

    # the highest velocity at which the max-bank member flies below its commanded bank: where the Nz arrest engages
    bank_top, rows_top = fam[-1]
    arrested = [r[0] for r in rows_top if PREENTRY_GUARD < r[4] < bank_top - 0.1]
    arrest_v = max(arrested) if arrested else None

    dpi = BASE_DPI * scale
    PW, PH = FIG_W*dpi, FIG_H*dpi
    px = FIELD[0]*PW                    # the plot field's pixel rect inside the PNG
    pw = FIELD[2]*PW
    ph = FIELD[3]*PH
    py = (1.0 - FIELD[1] - FIELD[3])*PH     # measured from the top, as the game's MARGIN:V is
    pad = float('%.1f' % (V_PAD_PX*scale))  # as the sidecar prints it, so the game maps what was drawn

    # no vessel line for a family without one (a generic background, tal/: trajReadSide then checks none; '?'
    # would refuse every ship); TRAJ_PNG_DIR (e.g. tal) prefixes the png names, which kOS reads from the archive's root
    pdir = os.environ.get('TRAJ_PNG_DIR', '').strip('/\\')
    out = ['version 2'] + (['vessel %s' % hdr['vessel']] if 'vessel' in hdr else []) + [
           'written %.3f' % hdr['written'],
           'aero_ver %.1f' % hdr['aero_ver'],
           'v_init %.2f' % vinit,
           'v_taem %.2f' % vtaem,
           'png_w %d' % int(PW),
           'png_h %d' % int(PH),
           '# the plot field inside the PNG, pixels, MARGIN:V measured from the top',
           'field_px %.1f %.1f %.1f %.1f' % (px, py, pw, ph),
           '# the band is drawn this many px inside the field\'s top and bottom',
           'v_pad_px %.1f' % pad,
           '# per panel: n  vhi  vlo  x0_km  x1_km  arrest_v  png  aLo aHi  dLo dHi']
    panels = []                         # (n, vhi, vlo, x0, x1, drawn name, alpha scale, drag scale)
    renames = []                        # (drawn name, final name), applied only once every check has passed
    for n, (vhi, vlo) in enumerate(panel_bands(vinit, vtaem), 1):
        # the 12 deg member converges onto 0 and 24 here and only crowds the labels
        vpad = v_pad(vhi, vlo, ph, pad)
        lines = [L for L in family_lines(fam, (vlo - vpad)*0.96) if int(L[0]) != 12]
        if not lines:
            print('  panel %d: no members in band -- skipped' % n)
            continue
        drawn = 'traj%d.png' % n
        (x0, x1), ascale, dscale = draw_panel(fam, lines, vhi, vlo, n, os.path.join(outdir, drawn), dpi, arrest_v,
                                             vpad)
        name = drawn
        if tuple(ascale) != DEFAULT_ASCALE:
            name = 'traj%d_a%g-%g.png' % (n, ascale[0], ascale[1])
            renames.append((drawn, name))
        out.append('P %d %.2f %.2f %.3f %.3f %.2f %s %g %g %g %g'
                   % (n, vhi, vlo, x0, x1, arrest_v if arrest_v else -1, (pdir + '/' + name) if pdir else name,
                      ascale[0], ascale[1], dscale[0], dscale[1]))
        panels.append((n, vhi, vlo, x0, x1, drawn, ascale, dscale))
        print('  panel %d  %.0f-%.0f m/s  %.0f-%.0f km  -> %s' % (n, vhi, vlo, x0, x1, name))

    # the strip positions are measured off the finished PNG's own pixel size
    from PIL import Image
    with Image.open(os.path.join(outdir, 'traj1.png')) as im:
        W, H = im.size
    out.append('# readout value rows, pixels from the top, and the right edge to align to')
    out.append('tl_rows ' + ' '.join('%.1f' % ((1.0 - y) * FIG_H * dpi) for y in TL_Y))
    out.append('tl_right %.1f' % (TL_RIGHT*PW))
    out.append('br_rows ' + ' '.join('%.1f' % ((1.0 - y) * FIG_H * dpi) for y in BR_Y))
    out.append('br_right %.1f' % (BR_RIGHT*PW))
    out.append('# the MET clock: right edge and baseline row, drawn live by kOS')
    out.append('clock_px %.1f %.1f' % (CLOCK_RIGHT*PW, CLOCK_TOP*PH))
    out.append('# the two strip scales: x centre, and the pixel row of the scale ends')
    out.append('strip_a %.1f %.1f %.1f' % (A_STRIP_X*W, H*(1.0-SHI), H*(1.0-SLO)))
    out.append('strip_d %.1f %.1f %.1f' % (D_STRIP_X*W, H*(1.0-SHI), H*(1.0-SLO)))

    # the checks read the finished PNGs; the sidecar is written only if all pass
    bad = _verify(outdir, fam, panels, px, py, pw, ph, pad=pad)
    if bad:
        print('*** SIDECAR DOES NOT MATCH THE PANELS: %s' % bad)
        print('*** Refusing to write it -- the display would place every symbol wrongly.')
        return 1

    for (n, vhi, vlo, x0, x1, name, asc, dsc) in panels:       # each strip must cover the AoA its panel shows
        for v in (vhi, vlo):
            a = aoa_schedule(v)
            if not (asc[0] + 1.0 <= a <= asc[1] - 1.0):
                print('*** PANEL %d SHOWS AoA %.2f AT %.0f m/s, OUTSIDE ITS %g-%g STRIP'
                      % (n, a, v, asc[0], asc[1]))
                print('*** Refusing to write it -- the marker would clamp and blink there.')
                return 1

    bad = _verify_strip_labels(outdir, panels)
    if bad:
        print('*** STRIP LABELS DO NOT MATCH THE SCALES: %s' % bad)
        print('*** Refusing to write it -- the alpha marker would be mapped through a range')
        print('*** the picture does not show.')
        return 1

    for src, dst in renames:
        os.replace(os.path.join(outdir, src), os.path.join(outdir, dst))
        print('  %s -> %s (non-default alpha scale; busts the kOS image cache)' % (src, dst))

    side = os.path.join(outdir, 'traj_bg.txt')
    with open(side, 'w') as f:
        f.write('\n'.join(out) + '\n')
    print('wrote %s' % side)
    return 0


if __name__ == '__main__':
    sys.exit(main())
