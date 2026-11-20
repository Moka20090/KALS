"""Draws this flight's ENTRY TRAJ backgrounds by itself: watches family.txt and runs gen_traj_bg.py when a new family lands.

    python traj_bg_watch.py           watch: start once before the flight (or double-click traj_bg_watch.bat); Ctrl-C stops
    python traj_bg_watch.py --once    draw from the family.txt that is there, then exit
    python traj_bg_watch.py --dir D   use folder D instead of this one for family.txt, the pictures and the log

Reads family.txt (written by fam_build.ks on the coast); writes traj1..5.png and traj_bg.txt next to it, where the game
reads them before the warp, and appends every action to traj_bg_watch.log there.
  * It polls family.txt twice a second at below-normal priority (no measurable CPU while it waits).
  * It acts once the file's size and time have been steady for 1.5 s, the family reads and validates (the checks
    gen_traj_bg.py makes), and its "written" stamp differs from the one traj_bg.txt was drawn from: each family is drawn
    once, and one still being written is left alone.
  * gen_traj_bg.py draws into a temporary folder; the PNGs are moved into place first and traj_bg.txt last, so the game
    never reads a sidecar that points at pictures not yet in place.
"""
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from gen_traj_bg import read_family, validate_family       # the family reader only; the drawing runs in a subprocess

POLL_S = 0.5        # seconds between looks at family.txt
STEADY_S = 1.5      # seconds its size and time must hold before it is read


def below_normal():
    """Lower this process's priority so the polling never competes with the game (Windows; ignored elsewhere)."""
    try:
        import ctypes
        ctypes.windll.kernel32.SetPriorityClass(ctypes.windll.kernel32.GetCurrentProcess(), 0x4000)
    except Exception:
        pass


def stamp(path):
    """The "written" value in a family.txt or traj_bg.txt header (the game time it was made), or None."""
    try:
        with open(path) as f:
            for i, line in enumerate(f):
                p = line.split()
                if len(p) == 2 and p[0] == "written":
                    return p[1]
                if i > 20:
                    break
    except OSError:
        pass
    return None


def replace(src, dst):
    """os.replace, retried briefly: the game may be reading the old file at that instant."""
    for k in range(10):
        try:
            os.replace(src, dst)
            return
        except PermissionError:
            if k == 9:
                raise
            time.sleep(0.2)


def draw(fam, outdir, log):
    """gen_traj_bg.py into a temporary folder, then the PNGs into place, the sidecar last. True when drawn."""
    tmp = os.path.join(outdir, "_traj_bg_tmp")
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp)
    t0 = time.time()
    r = subprocess.run([sys.executable, os.path.join(HERE, "gen_traj_bg.py"), fam, tmp], cwd=HERE,
                       capture_output=True, text=True)
    side = os.path.join(tmp, "traj_bg.txt")
    if r.returncode != 0 or not os.path.exists(side):
        last = ((r.stdout or "") + (r.stderr or "")).strip().splitlines()[-1:] or ["no output"]
        log("gen_traj_bg.py did not draw (exit %d): %s" % (r.returncode, last[0]))
        shutil.rmtree(tmp, ignore_errors=True)
        return False
    pngs = sorted(n for n in os.listdir(tmp) if n.lower().endswith(".png"))
    for n in pngs:
        replace(os.path.join(tmp, n), os.path.join(outdir, n))
    replace(side, os.path.join(outdir, "traj_bg.txt"))
    shutil.rmtree(tmp, ignore_errors=True)
    log("drew %s + traj_bg.txt from family.txt written %s (%.1f s)" % (", ".join(pngs), stamp(fam), time.time() - t0))
    return True


def main():
    """Watch family.txt (or, with --once, draw it once); returns the exit code."""
    args = sys.argv[1:]
    below_normal()
    d = os.path.abspath(args[args.index("--dir") + 1]) if "--dir" in args else HERE
    fam = os.path.join(d, "family.txt")
    logf = os.path.join(d, "traj_bg_watch.log")

    def log(msg):
        line = time.strftime("%H:%M:%S ") + msg
        print(line, flush=True)
        try:
            with open(logf, "a") as f:
                f.write(line + "\n")
        except OSError:
            pass

    if "--once" in args:
        return 0 if draw(fam, d, log) else 1
    log("watching %s (Ctrl-C stops)" % fam)
    seen, since = None, None
    while True:
        try:
            st = os.stat(fam)
            key = (st.st_mtime, st.st_size)
        except OSError:
            key = None
        now = time.time()
        if key != seen:
            seen, since = key, now
        elif key is not None and since is not None and now - since >= STEADY_S:
            since = None                                    # this version is handled; wait for the next change
            ws = stamp(fam)
            if ws is not None and ws == stamp(os.path.join(d, "traj_bg.txt")):
                log("family.txt written %s: its panels are already drawn" % ws)
            else:
                try:
                    hdr, mem = read_family(fam)
                    why = validate_family(hdr, mem)
                except Exception as e:                      # a half-written line is a reason too
                    why = "unreadable (%s)" % e
                if why:
                    log("family.txt written %s not drawn yet: %s (waiting for it to change)" % (ws, why))
                else:
                    draw(fam, d, log)
        time.sleep(POLL_S)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("traj_bg_watch stopped")
