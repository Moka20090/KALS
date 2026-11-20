r"""KAL/S v1.0 install: installs this release into a KSP folder, fresh or over an earlier KAL/S or SOCK release (KAL/S
was called SOCK until v0.22). Double-click INSTALL.bat (beside this file), with KSP closed.

  1. Finds your KSP folders (the ones with KSP_x64.exe and GameData): this folder or one above it, Steam's libraries,
     GOG's games, and every fixed drive to 4 folders deep (at most 10 s). It lists them, with the release in each and FAR
     if there, and asks which: a number, a folder, or Enter for the one this folder is in. None found, it asks for the
     folder. With --yes (and no --ksp) only this folder or one above it.
  2. Checks it: KSP not running; GameData there; the mods the release needs (a missing one is a warning: folder names
     can differ between versions). FAR is allowed (since v0.21; newer, flown less than stock): when it is there it says so and goes on.
  3. Says what is installed there now: Ships\Script\KALS_VERSION.txt (SOCK_VERSION.txt until v0.22), else an
     earlier release recognised by its files (known_files.txt, beside this file, lists every file every earlier
     release shipped).
  4. Asks which craft to install (Ships\VAB, Ships\SPH): all (Enter), none, or the ones you pick by number; a craft
     left out is not installed, and one already there is left as it is.
     Compares the release's files with the KSP folder (a counter shows how far; nothing is changed yet), shows a short
     list of what it keeps and leaves (the full list in KALS_install_plan.txt, beside this file), and asks.
     Then copies Install\GameData and Install\Ships into it. Every file it replaces or removes is kept first in
     KALS_backup\<date-time>\ (in the KSP folder); a file already the same is left alone.
     Upgrading, it also removes the files an earlier release installed that this one no longer has -- only those, and
     only while they are as that release shipped them -- and makes GameData\KALS_Coproc, SOCK_RealAero, KALS_RealAscent,
     KALS_kOS and KALS_Sites exactly this release's. It empties their SOCK names of v0.1 - v0.22 (GameData\SockCoproc,
     SOCK_RealAscent, SOCK_ops3q, SOCK_Sites) and removes Ships\Script\SOCK_VERSION.txt.
     Never touched: your logs, plans and families (Ships\Script\logs, deorbit_plan.txt, oms1_plan.txt, oms2_plan.txt,
     family.txt, the traj pictures, display.txt, your saved HUD eye hud_eye_cal.json, ...), your
     Ships\Script\logging.txt switch, a craft you changed, and any file no earlier release installed.
  5. Writes KALS_install.txt (in the KSP folder): what it installed and what it kept, for --uninstall; and the
     list of what it did into the backup folder (report.txt). An earlier release's SOCK_ops3q_install.txt is read
     (its rows carried over), kept in the backup folder and removed.
  6. Raises kOS's instruction limit to 10000 and writes display.txt for the screen size, once, with the installed
     Ships\Script\sock_setup.py's ipu() and display() (no setup to run before each play session any more).
  7. v1.0: the HUD is Holo HUD 1.0.0's, which this package BUNDLES (the HoloHUD folder beside this file: Holo HUD's own,
     unchanged release with its own installer). This installer runs that one first (HoloHUD\install_holohud.py
     --bundled), so INSTALL.bat alone gives a working KAL/S with its HUD: Ships\Script\hud, hud.ks, hud_build.py,
     lib\lib_hud.ks, lib_kmsg.ks, lib_logsw.ks, lib_screen.ks, the HUD sets hud_<w>x<h>..., GameData\HoloHUD,
     GameData\kOS-Addons\StockCamera, and its field of view question. Those files are Holo HUD's (HANDED): this installer
     never copies, replaces or removes them, an earlier KAL/S's rows for them are dropped from KALS_install.txt, and Holo
     HUD logs them in HoloHUD_install.txt. CROSS-AWARE: a NEWER Holo HUD already installed is kept (the bundled one never
     overwrites it), an equal or older one is brought up to date; --dry shows the decision; the folder list names the
     Holo HUD version in each KSP folder. The HUD eye is set in the game (hud_cal.ks).
  8. Installs the HUD fonts (the Fonts folder beside this file) for your Windows user, with no administrator: each one
     is copied to your own Fonts folder and listed in your registry. --no-fonts skips this; then it says how to do it.

    INSTALL.bat                     install or upgrade (asks which KSP folder, and before copying)
    INSTALL.bat --ksp "D:\KSP"      install into that folder
    INSTALL.bat --yes               no questions (with --ksp, or this folder or one above it)
    INSTALL.bat --dry               say what it would do, change nothing
    INSTALL.bat --no-setup          skip step 6
    INSTALL.bat --craft none        the craft without asking (step 4): all, none, or names: --craft "Columbia STS-1,
                                    Atlantis Late" (--yes alone installs them all)
    INSTALL.bat --list              list the KSP folders it finds (step 1), change nothing
    INSTALL.bat --fov 40            the HUD CAM field of view (40, 60 or 70) without asking: passed on to Holo HUD's installer
    INSTALL.bat --uninstall         delete what it installed (unless changed since), put back what it replaced and
                                    kOS's instruction limit (asks which KSP folder: the installed ones first)
    UNINSTALL.bat                   the same (it runs this file with --uninstall); --dry and --yes work with it. It
                                    removes ONLY KAL/S: Holo HUD, StockCamera and the shared HUD scripts stay
"""
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import time
from collections import deque
from contextlib import redirect_stdout

RELEASE = 'KAL/S v1.0'
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'Install')
KNOWN = os.path.join(HERE, 'known_files.txt')
LOG = 'KALS_install.txt'
OLD_LOG = 'SOCK_ops3q_install.txt'                  # SOCK v0.1 - v0.22's: read when there is no LOG, removed by an install
BACKUP = 'KALS_backup'                              # (SOCK v0.1 - v0.22's backups stay in SOCK_ops3q_backup)
VERSION = 'Ships/Script/KALS_VERSION.txt'
OLD_VERSION = 'Ships/Script/SOCK_VERSION.txt'       # SOCK v0.2 - v0.22's: read when there is no VERSION, removed by an install
# KAL/S's own GameData folders (and SOCK RealAero, which it ships): after an install they hold exactly this release's
# files. KALS_Sites too since v0.23 (SOCK_Sites was not): a site file left beside the release's would be a second copy.
OWNED_NOW = ('GameData/KALS_Coproc/', 'GameData/SOCK_RealAero/', 'GameData/KALS_RealAscent/', 'GameData/KALS_kOS/',
             'GameData/KALS_Sites/', 'GameData/KALS_CW/', 'GameData/KALS_BayModels/')   # v1.0: + CW, BayModels
# their SOCK v0.1 - v0.22 names: an install empties them (KSP would load the coprocessor and the sites twice)
RENAMED = {'GameData/SockCoproc/': 'GameData/KALS_Coproc/', 'GameData/SOCK_RealAscent/': 'GameData/KALS_RealAscent/',
           'GameData/SOCK_ops3q/': 'GameData/KALS_kOS/', 'GameData/SOCK_Sites/': 'GameData/KALS_Sites/'}
OWNED = OWNED_NOW + tuple(RENAMED)
# T702 (v1.0): Holo HUD 1.0.0's files (KAL/S v0.2x shipped them; Holo HUD is its own release now): never copied,
# replaced or removed by this installer, and dropped from KALS_install.txt (Holo HUD's installer and log own them)
HANDED = re.compile(r'^(Ships/Script/(hud/|hud\.ks$|hud_build\.py$|hud_\d+x\d+(_fov\d+)?/|'
                    r'lib/lib_(hud|kmsg|logsw|screen)\.ks$)|GameData/(HoloHUD|kOS-Addons)/)', re.I)
# the player's: kept when there (the logs' on / off switch)
KEEP = {'Ships/Script/logging.txt'}
# T1011: Holo HUD 1.0.0 is bundled (its own release, unchanged, in HoloHUD\ beside this file) and installed by its own installer
HOLO_DIR = os.path.join(HERE, 'HoloHUD')
HOLO_INSTALLER = os.path.join(HOLO_DIR, 'install_holohud.py')
HOLO_VERSION = 'GameData/HoloHUD/HoloHUD.version'
CRAFT = ('Ships/SPH/', 'Ships/VAB/')            # a craft you changed is kept (the release's is not put over it)
# what the programs and the setup write: never touched (the same list the release is built against)
RUNTIME = re.compile(r'^Ships/Script/(deorbit_plan\.txt|family\.txt|traj_bg\.txt|traj\d[^/]*\.png|sock_cg_ref\.json|'
                     r'hud_eye_cal\.json|'                  # v0.24.1: hud_cal.ks's saved HUD eye
                     r'hud_fov\.txt|'                       # T193: hud_cal.ks's saved HUD field of view
                     r'mono_usage\.csv|oms1_plan\.txt|oms2_plan\.txt|display\.txt|traj_bg_watch\.bat|logs/|kos_backup/|'
                     r'traj_cs/)', re.I)
# the mods the release needs, by their GameData folder (or a file pattern): a missing one is a warning
NEEDS = [('kOS', 'kOS'), ('Principia', 'Principia'), ('Kopernicus', 'Kopernicus'), ('Sol (the planet pack)', 'Sol-Configs'),
         ('ModuleManager', 'ModuleManager.*.dll'), ('B9PartSwitch', 'B9PartSwitch'),
         ('SOCK (Benjee10 Shuttle Orbiter Construction Kit)', 'Benjee10_shuttleOrbiter'),
         ('Benjee10 shared assets', 'Benjee10_sharedAssets'), ('Rocket Motor Menagerie (the SSMEs)', 'RocketMotorMenagerie'),
         ('Conformal Decals', 'ConformalDecals'),
         ('Kerbal Konstructs (the landing sites)', 'KerbalKonstructs'),
         ('Kerbin Side Remastered (the landing runways)', 'KerbinSideRemastered'),   # KALS_Sites places its runways
         ('Tundra Space Center (pad 39B)', 'TundraSpaceCenter'),                     # and its pad 39B
         ('SPOCK (the drag chute)', 'ShuttleStuff_SharedAssets'),
         ("kOS for All! (the orbiter's kOS core)", os.path.join('XyphosAerospace', 'Tweaks', 'kOS-CommandPod')),
         ('Katniss Cape Canaveral', 'KatnisssCapeCanaveral'),
         ('Photon Corp (the SRBs, for the launch craft)', 'PhotonCorp'),
         ('ORANGES (the external tank, for the launch craft)', 'ORANGES'),
         ('Modular Launch Pads (the pad, for the launch craft)', 'ModularLaunchPads'),
         ('htRobotics (the Canadarm)', 'htRobotics'),
         ('Breaking Ground (the Canadarm\'s servos)', os.path.join('SquadExpansion', 'Serenity'))]   # Holo HUD: bundled (holo_step)
# mods KAL/S cannot work with: the install refuses while one is there (none since v0.21, which allows FAR)
CONFLICTS = []
# mods that change how KAL/S flies: a note, and the install goes on
NOTICES = [('FerramAerospaceResearch',
            "FAR found: KAL/S will use its FAR patches. FAR support is newer and less tested than stock; see Requirements in README.md.")]
# the HUD's fonts (Fonts\ beside this file): kOS draws only a font installed in Windows; without them the HUD is in Arial
FONTS = ['HUD Stroke', 'HUD Stroke Wide 092', 'HUD Stroke Wide 116', 'HUD Stroke Wide 127', 'HUD Stroke Wide 140',
         'HUD Stroke Wide 148']
# T191: the HUD eye presets (lib_hud.ks HD_EYE_PRESETS: m forward, up, right of the forward fuselage; CENTERED is its
# built-in HD_EYE_DEF, so it needs no file); the file is the one hud_cal.ks's SAVE writes and HUD CAM reads
HUD_EYE = 'Ships/Script/hud_eye_cal.json'
HUD_PRESETS = [('CENTERED', 'on the centreline, the default', (-0.27, 0.963, 0.0)),
               ('CDR WINDOW', "at the commander's seat, 0.4 m to the left", (-0.37, 0.963, -0.4))]
HUD_BUILTIN = 'CENTERED'                              # no file needed
HUD_PART = 'benjee10.shuttle.forwardFuselage'
# T193: the HUD CAM fields of view (lib_screen.ks SCR_FOVS) and the file that picks one (60 without it); the HUD sets
# hud_build.py builds for the player's screen
HUD_FOV = 'Ships/Script/hud_fov.txt'
HUD_FOVS = [(40, 'a bigger HUD, less of the view'), (60, "KSP's normal camera, the default"),
            (70, 'more of the view, a smaller HUD')]
# the release ships no HUD set, only the reference hud_build.py builds each one from (hud_layout.txt's lines that do
# not depend on the screen, hud_runways.txt); the 3840x2160 60 deg set is built into Ships/Script/hud
HUD_REF = 'Ships/Script/hud_ref'
HUD_4K = 'Ships/Script/hud'
PLAN = os.path.join(HERE, 'KALS_install_plan.txt')   # the full list of what an install does (or would do, --dry)
SHOW = 15                                             # at most this many lines of a list on the screen
# the search for KSP folders (find_installs): how deep it looks on each drive, for how long, and where it does not look
DEPTH = 4
CAP = 10.0                                            # seconds
WIDTH = 100                                           # the list's lines fit in this many columns
SKIP_TOP = {'windows', 'windows.old', 'programdata', 'system volume information', 'recovery', 'perflogs',
            'config.msi', 'msocache'}                 # at a drive's top (and any name there that starts with $)
SKIP_ANY = {'app' + 'data', 'node_modules', '.git'}   # anywhere ('app' + 'data': a profile's hidden program-data folder)
STEAM_KSP = os.path.join('steamapps', 'common', 'Kerbal Space Program')
ARGS = sys.argv[1:]
YES = '--yes' in ARGS
DRY = '--dry' in ARGS


def sha(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


class Count:
    """A slow step: its line, then (on a console only) a progress bar on one line, redrawn every 1 % or 50 files.
    Elsewhere (a file, --dry's output read by a program) only the line."""
    WIDTH = 20                                        # the bar's # / - (the whole line fits in 60 columns)

    def __init__(self, line, total, unit, label):
        if total:
            print(line, flush=True)
        self.total, self.unit, self.label, self.n, self.t0 = total, unit, label, 0, time.time()
        self.every = max(1, min(50, total // 100))
        self.tty = sys.stdout.isatty()
        if self.tty and total:
            self.draw()

    def draw(self):
        f = self.n / self.total if self.total else 1.0
        k = int(round(f * self.WIDTH))
        print('\r  [%s%s] %3d %%' % ('#' * k, '-' * (self.WIDTH - k), int(f * 100)), end='', flush=True)

    def tick(self):
        self.n += 1
        if self.tty and (self.n % self.every == 0 or self.n == self.total):
            self.draw()

    def done(self):
        if self.tty and self.total:
            self.draw()
            print(flush=True)


def show(lines, rest):
    """Print at most SHOW of the lines, then how many more and where they all are."""
    for ln in lines[:SHOW]:
        print(ln)
    if len(lines) > SHOW:
        print('  ... and %d more (%s)' % (len(lines) - SHOW, rest))


def ask(q):
    if YES:
        return True
    try:
        return input(q + ' [y/n] ').strip().lower().startswith('y')
    except EOFError:
        return False


def hud_saved(ksp):
    """The saved HUD eye (fwd, up, star) in Ships/Script/hud_eye_cal.json, or None (none, or not one)."""
    p = native(ksp, HUD_EYE)
    if not os.path.isfile(p):
        return None
    try:
        import json
        d = json.load(open(p, encoding='utf-8'))
        e = d['entries']
        kv = {e[i]['value']: e[i + 1]['value'] for i in range(0, len(e) - 1, 2)}
        return tuple(float(kv[k]) for k in ('fwd', 'up', 'star'))
    except (OSError, ValueError, KeyError, TypeError, IndexError):
        return None


def hud_json(eye):
    """hud_eye_cal.json as kOS's WRITEJSON writes hud_cal.ks's LEXICON(fwd, up, star, part)."""
    import json
    ent = []
    for k, v in zip(('fwd', 'up', 'star', 'part'), list(eye) + [HUD_PART]):
        ent.append({'value': k, '$type': 'kOS.Safe.Encapsulation.StringValue'})
        ent.append({'value': v, '$type': 'kOS.Safe.Encapsulation.StringValue' if isinstance(v, str)
                    else 'kOS.Safe.Encapsulation.ScalarDoubleValue'})
    return json.dumps({'entries': ent, '$type': 'kOS.Safe.Encapsulation.Lexicon'}, indent=4)


def hud_choice(ksp):
    """T191: which HUD eye, asked before the copy: ('keep', None) leaves the file as it is, (name, eye) a preset."""
    have = hud_saved(ksp)
    cur = None
    for name, _, eye in HUD_PRESETS:
        if (have is None and name == HUD_BUILTIN) or (have is not None and all(abs(a - b) < 1e-6 for a, b in zip(eye, have))):
            cur = name
    opts = [(n, w, e) for n, w, e in HUD_PRESETS]
    if have is not None and cur is None:
        opts.append(('YOURS', 'your saved eye, %g m forward, %g m up and %g m right' % have, have))
    if '--hud' in ARGS:
        want = ARGS[ARGS.index('--hud') + 1].strip().lower()
        for n, w, e in HUD_PRESETS:
            if n.lower().startswith(want[:3]):
                return ('keep', None) if n == cur else (n, None if n == HUD_BUILTIN else e)
        sys.exit('--hud must be centered or cdr. You gave: ' + want)
    if YES:
        return ('keep', None)
    print('Where should HUD CAM put your eye? You can change this later in the game with hud_cal.ks.')
    dflt = 1
    for i, (n, w, e) in enumerate(opts, 1):
        now = (n == cur) or (n == 'YOURS')
        if now:
            dflt = i
        print('  %d  %-11s %s%s' % (i, n, w, '  (current)' if now else ''))
    try:
        a = input('Type a number, or press Enter for %d: ' % dflt).strip()
    except EOFError:
        a = ''
    k = int(a) if a.isdigit() and 1 <= int(a) <= len(opts) else dflt
    n, _, e = opts[k - 1]
    return ('keep', None) if (n == 'YOURS' or n == cur) else (n, None if n == HUD_BUILTIN else e)


def hud_dir(w, h, fov):
    """The HUD set's folder for a screen and a field of view (lib_screen.ks scrHudDir)."""
    if fov != 60:
        return 'Ships/Script/hud_%dx%d_fov%d' % (w, h, fov)
    return HUD_4K if (w, h) == (3840, 2160) else 'Ships/Script/hud_%dx%d' % (w, h)


def fov_now(ksp):
    try:
        return int(round(float(open(native(ksp, HUD_FOV)).read().split()[0])))
    except (OSError, ValueError, IndexError):
        return 60


def fov_choice(ksp):
    """T193: which HUD field of view, asked with the HUD eye: None keeps the file as it is, else 40, 60 or 70."""
    cur = fov_now(ksp)
    fovs = [f for f, _ in HUD_FOVS]
    if '--fov' in ARGS:
        want = ARGS[ARGS.index('--fov') + 1].strip()
        if not want.isdigit() or int(want) not in fovs:
            sys.exit('--fov must be 40, 60 or 70. You gave: ' + want)
        return None if int(want) == cur else int(want)
    if YES:
        return None
    print('Which field of view should HUD CAM use? You can change this later in the game with hud_cal.ks.')
    dflt = fovs.index(cur) + 1 if cur in fovs else 2
    for i, (f, w) in enumerate(HUD_FOVS, 1):
        print('  %d  %2d deg  %s%s' % (i, f, w, '  (current)' if f == cur else ''))
    try:
        a = input('Type a number, or press Enter for %d: ' % dflt).strip()
    except EOFError:
        a = ''
    k = int(a) if a.isdigit() and 1 <= int(a) <= len(fovs) else dflt
    return None if fovs[k - 1] == cur else fovs[k - 1]


def screen_size(ksp):
    """The screen display.txt names (w, h), or 3840x2160."""
    try:
        w, h = open(native(ksp, 'Ships/Script/display.txt')).read().split()[0].lower().split('x')
        return int(w), int(h)
    except (OSError, ValueError, IndexError):
        return 3840, 2160


def hud_mine(ksp):
    """The folders of the HUD sets hud_sets builds (each with its /): an earlier install's files there are rebuilt
    in place, not removed."""
    w, h = screen_size(ksp)
    return tuple(hud_dir(w, h, f) + '/' for f, _ in HUD_FOVS)


def hud_sets(ksp, rows, report):
    """T193: the HUD sets for this screen at every field of view, built by the installed hud_build.py from the shipped
    reference (HUD_REF); each file logged as installed (rows), so --uninstall removes it."""
    p = native(ksp, 'Ships/Script/hud_build.py')
    ref = native(ksp, HUD_REF)
    if not os.path.isfile(p) or not os.path.isfile(os.path.join(ref, 'hud_layout.txt')):
        print('Ships\\Script\\hud_build.py or Ships\\Script\\hud_ref is missing, so no HUD pictures were built.')
        return
    sys.dont_write_bytecode = True
    spec = importlib.util.spec_from_file_location('hud_build', p)
    hb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hb)
    w, h = screen_size(ksp)
    todo = [f for f, _ in HUD_FOVS]
    c = Count('Building HUD pictures for your %dx%d screen at %s deg...' % (w, h, ', '.join('%d' % f for f in todo)),
              sum(hb.count(w, h, float(f)) for f in todo), 'sprites drawn', 'Drawing')
    built = []
    for f in todo:
        rel = hud_dir(w, h, f)
        dest = native(ksp, rel)
        hb.build(ref, dest, w, h, float(f), log=None, tick=c.tick)
        n = 0
        for root, _, fs in os.walk(dest):
            for x in fs:
                r = norm(os.path.relpath(os.path.join(root, x), ksp))
                rows[r] = ('new', sha(os.path.join(root, x)), '-')
                n += 1
        report.append('build   %s (%d files, %d deg)' % (rel, n, f))
        built.append('  Built %s for %d deg.' % (rel.split('/')[-1], f))
    c.done()
    for ln in built:
        print(ln)


# T511 (the owner 11-03 / 11-12): THE CAPE OPTION, one choice like the HUD eye and the HUD field of view: Katniss's Cape Canaveral as published, or the Cape moved
# onto Sol's coast with the water fix. ON = these 5 files of the release (our own: KALS_CapeWater = the terrain decal, its height map and the coprocessor's near-field
# switch; ZZ_KALS_CapeShift = ONE ModuleManager patch that sets Katniss's 14 Cape numbers by absolute value). Katniss's own files are never changed or copied.
# OFF = none of the 5 files (the default of a fresh install). Offered only when Katniss's files hold the published numbers (or the shifted ones: a hand edit).
CAPE_FILES = ('GameData/KALS_CapeWater/KALS_CapeNearField.cfg', 'GameData/KALS_CapeWater/KALS_CapeWater.cfg', 'GameData/KALS_CapeWater/KALS_CapeWater.png',
              'GameData/KALS_CapeWater/KK_MapDecal_KALS_CapeWater.cfg', 'GameData/ZZ_KALS_CapeShift/KALS_CapeShift.cfg')
KATNISS = 'GameData/KatnisssCapeCanaveral/'
# per Katniss file: (key, which `key = number` in the file, published, shifted); the 14 numbers KALS_CapeShift.cfg sets
CAPE_VALUES = {
    'Instances/Modern/CapeCanaveral_center.cfg': [('RefLatitude', 0, 28.5234, 28.487427192), ('RefLongitude', 0, -80.6222, -80.721263457)],
    'Patches/EarthPatch.cfg': [('lat', 0, 28.5857702, 28.549797392), ('lon', 0, -80.6507262, -80.749848315),
                               ('latitude', 0, 28.5233993, 28.487426492), ('longitude', 0, -80.6531998, -80.752263257)],
    'Patches/LaunchSitesPatch.cfg': [('latitude', 0, 28.5233993, 28.487426492), ('longitude', 0, -80.6531998, -80.752263257),
                                     ('latitude', 1, 28.5233993, 28.487426492), ('longitude', 1, -80.6531998, -80.752263257)],
    'Patches/KK_MapDecal_KK_MapDecal_0.cfg': [('Latitude', 0, 28.59737959790569, 28.561406790), ('Longitude', 0, -80.605396545099026, -80.704529599)],
    'Patches/KK_MapDecal_KK_MapDecal_1.cfg': [('Latitude', 0, 28.218599207419143, 28.182626400), ('Longitude', 0, -80.608861976055763, -80.707641453)],
}
CAPE_EPS = 1e-6
CAPE_OPTS = [('PUBLISHED', "Katniss's Cape where Katniss put it"),
             ('SHIFTED', "the Cape moved onto Sol's coast, with the water fix (KAL/S's own files; Katniss's stay as they are)")]


def cape_now(ksp):
    """True when all 5 option files are in this KSP folder."""
    return all(os.path.isfile(native(ksp, rel)) for rel in CAPE_FILES)


def cape_number(text, key, nth):
    """The nth `key = number` (or `@key = number`) of a Katniss file, or None."""
    m = re.findall(r'^[ \t]*@?' + re.escape(key) + r'[ \t]*=[ \t]*(-?[0-9][0-9.eE+-]*)', text, re.M)
    try:
        return float(m[nth])
    except (IndexError, ValueError):
        return None


def katniss_state(ksp):
    """T511: (state, why) of Katniss Cape Canaveral's 5 files: 'published' (all 14 numbers as published), 'shifted' (all as the option sets them: a hand edit),
    'missing' (no mod or a file gone) or 'differs' (any other value: another version, or half a shift). Only the first two are offered."""
    if not os.path.isdir(native(ksp, KATNISS.rstrip('/'))):
        return 'missing', "Katniss Cape Canaveral is not in GameData"
    pub = sh = n = 0
    for f, vals in CAPE_VALUES.items():
        p = native(ksp, KATNISS + f)
        if not os.path.isfile(p):
            return 'missing', "Katniss's %s is not there" % f
        try:
            text = open(p, encoding='utf-8', errors='replace').read()
        except OSError:
            return 'missing', "Katniss's %s cannot be read" % f
        for key, nth, a, b in vals:
            x = cape_number(text, key, nth)
            n += 1
            if x is not None and abs(x - a) < CAPE_EPS:
                pub += 1
            if x is not None and abs(x - b) < CAPE_EPS:
                sh += 1
    if pub == n:
        return 'published', ''
    if sh == n:
        return 'shifted', ''
    return 'differs', "Katniss's Cape files are not as published (another version, or changed by hand)"


def cape_choice(ksp):
    """T511: which Cape, asked like hud_choice / fov_choice, before the compare: 'on' (the 5 files), 'off' (none), or None (not offered: what is installed stays).
    --cape on|off chooses without asking; --yes keeps what is there (a fresh install: off)."""
    now = cape_now(ksp)
    state, why = katniss_state(ksp)
    offered = state in ('published', 'shifted')
    if '--cape' in ARGS:
        i = ARGS.index('--cape')
        want = ARGS[i + 1].strip().lower() if i + 1 < len(ARGS) else ''
        if want not in ('on', 'off'):
            sys.exit('--cape must be on or off. You gave: ' + want)
        if want == 'on' and not offered:
            sys.exit('--cape on is not possible: ' + why + '. Nothing installed.')
        return want
    if not offered:
        if not YES and (state != 'missing' or now):
            print('The Cape option is not offered: %s. The Cape stays as it is.' % why)
        return None
    if YES:
        return 'on' if now else 'off'
    if state == 'shifted':
        print("Your Katniss Cape files are already moved by hand: the SHIFTED answer sets the same numbers, and the PUBLISHED answer cannot move them back.")
    print('Which Cape Canaveral should KAL/S use? You can change this later by running INSTALL.bat again.')
    dflt = 2 if now else 1
    for i, (n, w) in enumerate(CAPE_OPTS, 1):
        print('  %d  %-9s %s%s' % (i, n, w, '  (current)' if i == dflt else ''))
    try:
        a = input('Type a number, or press Enter for %d: ' % dflt).strip()
    except EOFError:
        a = ''
    k = int(a) if a.isdigit() and 1 <= int(a) <= len(CAPE_OPTS) else dflt
    return 'on' if k == 2 else 'off'


def craft_choice(files):
    """T286: which of the release's craft to install: (the files without the others, the others). Asked before the
    compare; --craft all / none / "name, name" chooses without asking, --yes alone installs them all. A craft left out
    is not installed, and one an earlier release put there is left as it is (and stays in the log for --uninstall)."""
    craft = [rel for rel in files if rel.startswith(CRAFT) and rel.endswith('.craft')]
    if not craft:
        return files, set()
    names = [rel.split('/')[-1][:-len('.craft')] for rel in craft]
    bad = '--craft takes all, none, or craft names separated by commas. The craft this release has: ' + ', '.join(names)
    if '--craft' in ARGS:
        i = ARGS.index('--craft')
        a = ARGS[i + 1].strip() if i + 1 < len(ARGS) else ''
        if a.lower() == 'all':
            want = set(craft)
        elif a.lower() == 'none':
            want = set()
        else:
            want = set()
            for n in [x.strip() for x in a.split(',') if x.strip()]:
                hit = [rel for rel, nm in zip(craft, names) if nm.lower() == n.lower()]
                if not hit:
                    sys.exit(bad)
                want.update(hit)
            if not want:
                sys.exit(bad)
    elif YES:
        want = set(craft)
    else:
        print('Which craft do you want to install? This release has %d; README.md describes them under What it flies.' % len(craft))
        print('  1  all of them')
        print('  2  none')
        print('  3  let me choose')
        try:
            a = input('Type a number, or press Enter for 1: ').strip()
        except EOFError:
            a = ''
        if a == '2':
            want = set()
        elif a == '3':
            for k, (rel, nm) in enumerate(zip(craft, names), 1):
                print('  %2d  %-26s (%s)' % (k, nm, rel.split('/')[1]))
            try:
                a = input('Type the numbers to install, for example 1 4 12, or press Enter for all: ').strip()
            except EOFError:
                a = ''
            if a:
                want = {craft[int(x) - 1] for x in re.split(r'[\s,]+', a) if x.isdigit() and 1 <= int(x) <= len(craft)}
            else:
                want = set(craft)
        else:
            want = set(craft)
    skip = set(craft) - want
    if skip:
        print('Craft: %d of %d will be installed. Left out: %s.' % (len(want), len(craft),
                                                  ', '.join(nm for rel, nm in zip(craft, names) if rel in skip)))
    return [rel for rel in files if rel not in skip], skip


def has(gd, pat):
    if '*' in pat:
        a, b = pat.split('*', 1)
        return any(f.startswith(a) and f.endswith(b) for f in os.listdir(gd))
    return os.path.isdir(os.path.join(gd, pat))


def ksp_running():
    if os.name != 'nt':
        return False
    out = subprocess.run(['tasklist', '/FI', 'IMAGENAME eq KSP_x64.exe'], capture_output=True, text=True).stdout
    return 'KSP_x64.exe' in out


def near(d=HERE):
    """The first folder with KSP_x64.exe: this one or up to 3 above it; or None."""
    for _ in range(4):
        if os.path.isfile(os.path.join(d, 'KSP_x64.exe')):
            return d
        d = os.path.dirname(d)
    return None


def is_ksp(d):
    return os.path.isfile(os.path.join(d, 'KSP_x64.exe')) and os.path.isdir(os.path.join(d, 'GameData'))


def key(d):
    """A folder's name for telling two apart: its real path, case-folded."""
    try:
        return os.path.normcase(os.path.realpath(d))
    except (OSError, ValueError):
        return os.path.normcase(os.path.abspath(d))


def reg(hive, path, name):
    """A registry value as text, or None (off Windows, or on any error)."""
    try:
        import winreg
        with winreg.OpenKey(getattr(winreg, hive), path) as k:
            return str(winreg.QueryValueEx(k, name)[0])
    except Exception:
        return None


def reg_keys(hive, path):
    """A registry key's subkeys, or [] (off Windows, or on any error)."""
    out = []
    try:
        import winreg
        with winreg.OpenKey(getattr(winreg, hive), path) as k:
            while True:
                try:
                    out.append(winreg.EnumKey(k, len(out)))
                except OSError:
                    break
    except Exception:
        pass
    return out


def steam_dirs():
    """Steam's folder, from the registry (the machine's entries first: the user's is in lower case)."""
    return [p for p in (reg('HKEY_LOCAL_MACHINE', r'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
                        reg('HKEY_LOCAL_MACHINE', r'SOFTWARE\Valve\Steam', 'InstallPath'),
                        reg('HKEY_CURRENT_USER', r'Software\Valve\Steam', 'SteamPath')) if p]


def steam_libraries(steam):
    """Steam's folder and every library its libraryfolders.vdf names."""
    libs = [steam]
    for vdf in (os.path.join(steam, 'steamapps', 'libraryfolders.vdf'),
                os.path.join(steam, 'config', 'libraryfolders.vdf')):
        try:
            text = open(vdf, encoding='utf-8', errors='replace').read()
        except OSError:
            continue
        # "path" "D:\\SteamLibrary" (since 2021) or "1" "D:\\SteamLibrary" (before); a number with a number (an app's
        # size) is not a folder
        libs += [p.replace('\\\\', '\\') for p in re.findall(r'^\s*"(?:path|\d+)"\s+"([^"]+)"', text, re.M)
                 if os.path.isabs(p.replace('\\\\', '\\'))]
    return libs


def gog_dirs():
    """GOG's games' folders, from the registry."""
    out = []
    for base in (r'SOFTWARE\WOW6432Node\GOG.com\Games', r'SOFTWARE\GOG.com\Games'):
        for sub in reg_keys('HKEY_LOCAL_MACHINE', base):
            p = reg('HKEY_LOCAL_MACHINE', base + '\\' + sub, 'path')
            if p:
                out.append(p)
    return out


def drives():
    """The fixed drives' tops (C:\\, D:\\, ...), or [] (off Windows, or on any error)."""
    if os.name != 'nt':
        return []
    try:
        import ctypes
        k = ctypes.windll.kernel32
        mask = k.GetLogicalDrives()
        return ['%s:\\' % c for i, c in enumerate('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                if mask >> i & 1 and k.GetDriveTypeW('%s:\\' % c) == 3]          # 3: a fixed drive
    except Exception:
        return []


def linked(e):
    """A symbolic link or a junction: not followed (it leads where the scan looks anyway, or round in a loop)."""
    if e.is_symlink():
        return True
    st = e.stat(follow_symlinks=False)
    return bool(getattr(st, 'st_file_attributes', 0) & 0x400) and getattr(st, 'st_reparse_tag', 0) == 0xA0000003


def scan(roots, add, seen, cap):
    """Each root's folders, breadth first, to DEPTH down: add() for each KSP folder (not looked into, nor a folder in
    seen). False when cap seconds ran out first."""
    end = time.time() + cap
    q = deque((r, 0) for r in roots)
    while q:
        if time.time() > end:
            return False
        d, n = q.popleft()
        try:
            with os.scandir(d) as it:
                ents = list(it)
            if n and any(e.name.lower() == 'ksp_x64.exe' and e.is_file() for e in ents) and \
                    any(e.name.lower() == 'gamedata' and e.is_dir() for e in ents):
                add(d)
                continue
        except OSError:
            continue
        if n >= DEPTH:
            continue
        for e in sorted(ents, key=lambda e: e.name.lower()):
            low = e.name.lower()
            if low in SKIP_ANY or (n == 0 and (low in SKIP_TOP or low.startswith('$'))):
                continue
            try:
                if not e.is_dir() or linked(e) or os.path.normcase(e.path) in seen:
                    continue
            except OSError:
                continue
            q.append((e.path, n + 1))
    return True


def find_installs(roots=None, steam=None, gog=None, here=HERE, cap=CAP):
    """The KSP folders (KSP_x64.exe and GameData) on this computer, each once: this folder's (this one or one above
    it), Steam's, GOG's, then the drive scan's. roots / steam / gog: the folders to scan / Steam's folders / GOG's game
    folders, by default the fixed drives / the registry's (a test gives its own). Reads only; what it cannot read it
    passes by."""
    found, keys, seen = [], set(), set()

    def add(d):
        try:
            d = os.path.normpath(os.path.abspath(d))
            k = key(d)
            if k not in keys and is_ksp(d):
                keys.add(k)
                seen.update((k, os.path.normcase(d)))
                found.append(d)
        except (OSError, ValueError):
            pass
    d = near(here) if here else None
    if d:
        add(d)
    for s in (steam_dirs() if steam is None else steam):
        for lib in steam_libraries(os.path.normpath(s)):
            add(os.path.join(lib, STEAM_KSP))
    for g in (gog_dirs() if gog is None else gog):
        add(g)
    if not scan(drives() if roots is None else roots, add, seen, cap):
        print('Stopped searching after %g seconds, so some folders were not checked.' % cap)
    return found


def shorten(p, n, others=()):
    """p in at most n characters, as (start, end): the screen shows start + '...' + end (or p, end None); None when
    every such cut could also be one of the others. Kept: the drive, its first folder if it fits, then as many of the
    last folders as fit (they tell two copies apart), then more of the first ones; else cut in the middle."""
    if len(p) <= n:
        return p, None
    parts, best, score = p.split(os.sep), None, None
    for a in range(1, len(parts)):
        for b in range(1, len(parts) - a):
            cut = (os.sep.join(parts[:a]) + os.sep, os.sep + os.sep.join(parts[-b:]))
            if len(cut[0]) + 3 + len(cut[1]) <= n and (score is None or (a > 1, b, a) > score) and \
                    not any(could_be(cut, f) for f in others):
                best, score = cut, (a > 1, b, a)
    cut = (p[:n // 2 - 1], p[-(n - n // 2 - 2):])
    return best or (None if any(could_be(cut, f) for f in others) else cut)


def shown(cut):
    return cut[0] if cut[1] is None else cut[0] + '...' + cut[1]


def could_be(cut, d):
    """Could the screen's cut also be the folder d?"""
    s, e, d = os.path.normcase(cut[0]), cut[1] and os.path.normcase(cut[1]), os.path.normcase(d)
    return s == d if e is None else len(d) > len(s) + len(e) and d.startswith(s) and d.endswith(e)


def brief(now):
    """what_is_installed()'s line, as the list shows it (shorter than short()'s)."""
    s = short(now)
    if s.startswith('an earlier KAL/S'):
        return 'KAL/S or SOCK (some files changed)'
    return re.sub(r' \(\d{4}-\d\d-\d\d\) \(build ([^,)]+)(, \d+ files)?\)$', r' (build \1)', s)


def describe(found, versions, uninstall=False):
    """The list's lines: the number, the folder, what release is there (and FAR), each in at most WIDTH columns (but
    for a folder that only its whole name tells apart from another)."""
    notes = []
    for d in found:
        try:
            s = brief(what_is_installed(d, versions))
        except OSError:
            s = 'could not read its KAL/S files'
        if os.path.isdir(os.path.join(d, 'GameData', 'FerramAerospaceResearch')):
            s += ', FAR'
        if holo_version(d):
            s += ', Holo HUD ' + holo_version(d)
        if uninstall and log_path(d) is None:
            s += ', no install log'
        notes.append(s)
    num = len(str(len(found)))
    pw = max(36, WIDTH - (num + 6) - max(len(s) for s in notes))
    paths = []
    for i, d in enumerate(found):                       # a cut that could be another folder: longer till it cannot
        w, others = pw, found[:i] + found[i + 1:]
        cut = shorten(d, w, others)
        while cut is None:
            w += 1
            cut = shorten(d, w, others)
        paths.append(shown(cut))
    col = min(pw, max(len(p) for p in paths))
    out = []
    for i, (p, s) in enumerate(zip(paths, notes)):
        ln = '  %*d  %-*s  %s' % (num, i + 1, col, p, s)
        if len(ln) > WIDTH and len(p) <= col:
            ln = ln[:WIDTH - 3] + '...'
        out.append(ln)
    return out


def pick(found, default, uninstall=False):
    """The KSP folder the user picks: a number from the list, a folder, or Enter for found[default] (None: no
    Enter). End of input: exits."""
    q = '%s which folder? Type %s or a KSP folder path%s: ' % ('Uninstall from' if uninstall else 'Install into',
                                        '1' if len(found) == 1 else '1-%d' % len(found),
                                        '' if default is None else ', or press Enter for %d' % (default + 1))
    while True:
        try:
            a = input(q).strip().strip('"')
        except EOFError:
            print()
            sys.exit('Nothing changed.' if uninstall else 'Nothing installed.')
        if not a:
            if default is not None:
                return found[default]
        elif a.isdigit():
            if 1 <= int(a) <= len(found):
                return found[int(a) - 1]
        else:
            p = os.path.abspath(a)
            if os.path.isdir(os.path.join(p, 'GameData')):
                return p
            print('There is no GameData folder in %s, so it is not a KSP folder.' % p)
            continue
        print('Please type a number from the list or the path of a KSP folder.')


def find_ksp():
    if '--ksp' in ARGS:
        return os.path.abspath(ARGS[ARGS.index('--ksp') + 1])
    d = near()
    if YES:
        if d is None:
            sys.exit('No KSP folder was found next to this one. Name it with --ksp "<folder>".')
        return d
    uninstall = '--uninstall' in ARGS
    print('Finding your KSP folders...', flush=True)
    found = find_installs()
    if not found:
        print('No KSP folder was found.')
        try:
            return os.path.abspath(input('Type the path of your KSP folder, the one with KSP_x64.exe: ').strip().strip('"'))
        except EOFError:
            print()
            sys.exit('Nothing changed.' if uninstall else 'Nothing installed.')
    logged = [f for f in found if log_path(f)]
    if uninstall:                                       # the ones with an install log first
        found = logged + [f for f in found if f not in logged]
    keys = [key(f) for f in found]
    if d is not None and key(d) in keys:                # Enter: the one this folder is in,
        default = keys.index(key(d))
    elif uninstall and len(logged) == 1:                # else (uninstalling) the one with an install log,
        default = 0
    else:                                               # else the only one
        default = 0 if len(found) == 1 else None
    print('These KSP folders were found:')
    for ln in describe(found, read_known()[0], uninstall):
        print(ln)
    return pick(found, default, uninstall)


def list_installs():
    """--list: the KSP folders it finds, as the install lists them; changes nothing."""
    t0 = time.time()
    print('Finding your KSP folders...', flush=True)
    found = find_installs()
    for ln in describe(found, read_known()[0]) if found else ['No KSP folder was found.']:
        print(ln)
    print('Found %d in %.1f seconds.' % (len(found), time.time() - t0))


def check(ksp):
    gd = os.path.join(ksp, 'GameData')
    if not os.path.isdir(gd):
        sys.exit('There is no GameData folder in %s, so it is not a KSP folder.' % ksp)
    if not os.path.isfile(os.path.join(ksp, 'KSP_x64.exe')):
        print('There is no KSP_x64.exe in %s.' % ksp)
        if not ask('Install there anyway?'):
            sys.exit('Nothing installed.')
    if ksp_running():
        sys.exit('KSP is running. Close it and try again. Nothing installed.')
    for name, pat in CONFLICTS:
        if has(gd, pat):
            sys.exit('KAL/S does not work with %s (GameData\\%s). Remove it and try again. Nothing installed.'
                     % (name, pat))
    for pat, note in NOTICES:
        if has(gd, pat):
            print(note)
    return [name for name, pat in NEEDS if not has(gd, pat)]


def registered_fonts(root):
    """The font names listed under one root's Fonts key ('HUD Stroke (TrueType)' -> 'HUD Stroke'); raises OSError when
    the key cannot be read."""
    import winreg
    k = winreg.OpenKey(root, r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts')
    names, i = set(), 0
    while True:
        try:
            names.add(winreg.EnumValue(k, i)[0].replace(' (TrueType)', ''))
        except OSError:
            break
        i += 1
    return names


def fonts_missing():
    """The HUD fonts not installed for all users (HKLM's Fonts list) nor for this user (HKCU's), or None when the
    all-users list cannot be read."""
    if os.name != 'nt':
        return None
    import winreg
    try:
        names = registered_fonts(winreg.HKEY_LOCAL_MACHINE)
    except OSError:
        return None
    try:
        names |= registered_fonts(winreg.HKEY_CURRENT_USER)
    except OSError:
        pass
    return [f for f in FONTS if f not in names]


def font_file(name):
    """The file in Fonts\\ for a HUD font: 'HUD Stroke Wide 092' -> 'HUDStrokeWide092-Regular.ttf'."""
    return name.replace(' ', '') + '-Regular.ttf'


def font_user_dir():
    """This Windows user's own font folder (per-user fonts need no administrator)."""
    return os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Microsoft', 'Windows', 'Fonts')


def font_plan():
    """--dry: what the install would do with the HUD fonts (writes nothing)."""
    if '--no-fonts' in ARGS or os.name != 'nt':
        return
    miss = fonts_missing()
    if not miss:
        return
    print('--dry: %d HUD font(s) not installed for your user would be copied to %s and listed for it (%s).'
          % (len(miss), font_user_dir(), ', '.join(miss)))


def install_user_fonts(miss):
    """T947: the missing HUD fonts for this Windows user, with no administrator: each .ttf is copied to the user's
    Fonts folder and listed under HKCU's Fonts key, as Windows lists a per-user font. Returns the names installed."""
    import winreg
    folder = font_user_dir()
    os.makedirs(folder, exist_ok=True)
    key = winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts', 0,
                             winreg.KEY_SET_VALUE)
    done = []
    try:
        for name in miss:
            src = os.path.join(HERE, 'Fonts', font_file(name))
            if not os.path.isfile(src):
                print('The package has no font file for %s (%s), so it stays in Arial.' % (name, src))
                continue
            dst = os.path.join(folder, font_file(name))
            try:
                shutil.copyfile(src, dst)
            except OSError as e:
                print('Could not copy %s to %s (%s), so it stays in Arial.' % (font_file(name), folder, e))
                continue
            winreg.SetValueEx(key, name + ' (TrueType)', 0, winreg.REG_SZ, dst)
            done.append(name)
    finally:
        winreg.CloseKey(key)
    return done


def tell_fonts(miss):
    """The HUD fonts that could not be installed here: how to install them by hand."""
    folder = os.path.join(HERE, 'Fonts')
    print('%d of the %d HUD fonts are not installed, so the HUD text will show in Arial. To install them, open the Fonts'
          % (len(miss), len(FONTS)))
    print('folder, select all the .ttf files, right-click and choose "Install for all users". On Windows 11, click')
    print('"Show more options" first to see it. Then restart KSP.')
    if not YES and os.name == 'nt' and os.path.isdir(folder) and ask('Open the Fonts folder now?'):
        os.startfile(folder)


def check_fonts():
    """T947: installs the HUD fonts missing for this user (no administrator; --no-fonts skips it), then says so."""
    miss = fonts_missing()
    if miss is None:
        print('Could not check whether the HUD fonts are installed. See Install in README.md.')
        return
    if not miss:
        return
    if '--no-fonts' in ARGS:
        tell_fonts(miss)
        return
    try:
        install_user_fonts(miss)
    except OSError as e:
        print('Could not install the HUD fonts for your user (%s).' % e)
    still = fonts_missing()
    if still is None:
        print('Could not check whether the HUD fonts are installed. See Install in README.md.')
    elif still:
        tell_fonts(still)
    else:
        print('The HUD fonts are installed for your Windows user. Restart KSP so it can use them.')


def norm(rel):
    return rel.replace('\\', '/')


def native(ksp, rel):
    return os.path.join(ksp, *norm(rel).split('/'))


def log_path(ksp):
    """The install log in this KSP folder: KALS_install.txt, else an earlier release's SOCK_ops3q_install.txt; or
    None."""
    for name in (LOG, OLD_LOG):
        p = os.path.join(ksp, name)
        if os.path.isfile(p):
            return p
    return None


def read_log(ksp):
    """{rel: (kind, sha, backup)} from log_path() (kind new / repl / same), {} without one."""
    p = log_path(ksp)
    if p is None:
        return {}
    rows = {}
    for ln in open(p, encoding='utf-8').read().splitlines()[1:]:
        if ln.strip():
            kind, s, bk, rel = ln.split(None, 3)
            rows[norm(rel)] = (kind, s, norm(bk))
    return rows


def read_known():
    """(versions, files): versions = [(label, {rel: sha16})], the signature files of each earlier release;
    files = {rel: {sha16, ...}}, every file any earlier release shipped, as it shipped it."""
    versions, files = [], {}
    if not os.path.isfile(KNOWN):
        return versions, files
    for ln in open(KNOWN, encoding='utf-8').read().splitlines():
        if ln.startswith('V\t'):
            f = ln.split('\t')
            versions.append((f[1], dict(x.split(' ', 1)[::-1] for x in f[2:] if x)))
        elif ln.startswith('F '):
            _, s, rel = ln.split(' ', 2)
            files.setdefault(rel, set()).add(s)
    return versions, files


def what_is_installed(ksp, versions):
    """A line saying what release is in this KSP folder now."""
    for v in (VERSION, OLD_VERSION):
        p = native(ksp, v)
        if os.path.isfile(p):
            lines = open(p, encoding='utf-8', errors='replace').read().splitlines()
            return '%s (read from %s)' % (', '.join(l.strip() for l in lines if l.strip()), v.replace('/', '\\'))
    best, score, seen = None, 0, {}

    def h16(rel):                                       # each signature file read once
        if rel not in seen:
            p = native(ksp, rel)
            seen[rel] = sha(p)[:16] if os.path.isfile(p) else None
        return seen[rel]
    for label, sig in versions:
        n = sum(1 for rel, s in sig.items() if h16(rel) == s)
        if n == len(sig) and n > score:
            best, score = label, n
    if best:
        return 'an earlier release: ' + best
    if os.path.isfile(native(ksp, 'Ships/Script/ops3q.ks')) or log_path(ksp):
        return 'an earlier KAL/S or SOCK release or a changed copy (its files do not match one release exactly)'
    return 'none found'


def short(now):
    """what_is_installed()'s line, as the screen shows it."""
    if now.startswith('an earlier release: '):
        return now[len('an earlier release: '):]
    if now.startswith('an earlier KAL/S'):
        return 'an earlier KAL/S or SOCK (some files changed)'
    if now == 'none found':
        return 'no KAL/S or SOCK'
    return now.split(',')[0]


def plan(ksp, files, old, known, skip=frozenset()):
    """What the install will do: a list of (action, rel, why), action new / replace / same / keep / remove / restore /
    leave; and rsha(rel), the sha of a release file (read once, when first needed)."""
    steps, memo = [], {}

    def rsha(rel):
        if rel not in memo:
            memo[rel] = sha(os.path.join(SRC, *rel.split('/')))
        return memo[rel]
    c = Count('Comparing your files with the release; nothing is changed yet...', len(files), 'files compared', 'Comparing')
    for rel in files:
        c.tick()
        dst = native(ksp, rel)
        if not os.path.exists(dst):
            steps.append(('new', rel, ''))
            continue
        # a different size cannot be the same file: no need to read it (only a craft's check needs its sha)
        if os.path.getsize(dst) == os.path.getsize(os.path.join(SRC, *rel.split('/'))) and sha(dst) == rsha(rel):
            steps.append(('same', rel, ''))
        elif rel in KEEP:
            steps.append(('keep', rel, 'your setting'))
        elif rel.startswith(CRAFT) and sha(dst)[:16] not in known.get(rel, ()) and \
                not (rel in old and old[rel][0] != 'same' and old[rel][1] == sha(dst)):
            steps.append(('keep', rel, 'a craft you changed (the release\'s is not put over it)'))
        else:
            steps.append(('replace', rel, ''))
    c.done()
    # the files an earlier release installed that this one does not have
    cand = set(old) | {rel for rel in known if os.path.isfile(native(ksp, rel))}
    if os.path.isfile(native(ksp, OLD_VERSION)):
        cand.add(OLD_VERSION)                           # SOCK_VERSION.txt, whatever is in it
    for top in OWNED:
        for root, _, fs in os.walk(native(ksp, top.rstrip('/'))):
            for f in fs:
                cand.add(norm(os.path.relpath(os.path.join(root, f), ksp)))
    todo = [rel for rel in sorted(cand - set(files))
            if os.path.isfile(native(ksp, rel)) and not RUNTIME.match(rel) and rel not in KEEP and rel not in skip]
    for rel in todo:
        dst = native(ksp, rel)
        if HANDED.match(rel):                           # T702: Holo HUD's now: left, and no row in the new log
            steps.append(('leave', rel, 'Holo HUD\'s now'))
            continue
        if rel.startswith(tuple(RENAMED)):
            top = 'GameData/' + rel.split('/')[1] + '/'
            steps.append(('remove', rel, 'GameData\\%s is %s since v0.23' % (top.split('/')[1], RENAMED[top].split('/')[1])))
            continue
        if rel.startswith(OWNED):
            steps.append(('remove', rel, 'not in this release\'s ' + rel.split('/')[1]))
            continue
        if rel == OLD_VERSION:
            steps.append(('remove', rel, 'SOCK_VERSION.txt is KALS_VERSION.txt since v0.23'))
            continue
        d = sha(dst)
        if rel in old:
            kind, s, bk = old[rel]
            if kind == 'same':
                steps.append(('leave', rel, 'yours (it was there before the first install)'))
            elif d != s:
                steps.append(('leave', rel, 'changed since an earlier release installed it'))
            elif kind == 'repl' and os.path.isfile(native(ksp, bk + '/' + rel)):
                steps.append(('restore', rel, 'an earlier release replaced it; yours is put back'))
            else:
                steps.append(('remove', rel, 'an earlier release\'s, no longer shipped'))
        elif d[:16] in known.get(rel, ()):
            steps.append(('remove', rel, 'an earlier release\'s, no longer shipped'))
        else:
            steps.append(('leave', rel, 'not as an earlier release shipped it: yours'))
    return steps, rsha


def prune(ksp, d):
    stop = {os.path.join(ksp, *k) for k in [(), ('GameData',), ('Ships',), ('Ships', 'Script'), ('Ships', 'VAB'),
                                           ('Ships', 'SPH')]}
    while d not in stop and os.path.isdir(d) and not os.listdir(d):
        os.rmdir(d)
        d = os.path.dirname(d)


def setup_mod(ksp):
    """The installed Ships/Script/sock_setup.py as a module (its ipu() and display()), or None."""
    p = native(ksp, 'Ships/Script/sock_setup.py')
    if not os.path.isfile(p):
        return None
    sys.dont_write_bytecode = True                       # no __pycache__ left in Ships/Script
    spec = importlib.util.spec_from_file_location('sock_setup', p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def kos_limit(m):
    """kOS.dll's instruction limit now, or None (no kOS.dll, or not kOS 1.6.0.1)."""
    if not os.path.isfile(m.DLL):
        return None
    lay = m.dll_layout(open(m.DLL, 'rb').read())
    return lay[1][0] if lay else None


def one_time(ksp):
    """What sock_setup did before each play session, done once: kOS's limit to 10000, display.txt for the screen."""
    m = setup_mod(ksp)
    if m is None:
        return
    buf = io.StringIO()
    with redirect_stdout(buf):
        m.ipu(False, revert=False)
        m.display(False)
    said = buf.getvalue()
    if os.path.isfile(m.DLL):
        n = kos_limit(m)
        if n is None:
            print('Your kOS is not version 1.6.0.1, so its instruction limit stays at %d and the guidance may run slowly.'
                  % m.STOCK_IPU)
        elif n != m.IPU:
            print('Could not raise kOS\'s instruction limit, which is still %d. Close KSP and run INSTALL.bat again.' % n)
    if 'has no HUD set' in said:                         # none yet: hud_sets builds this screen's next
        size = said.split('3. Screen: ', 1)[1].split(' ', 1)[0]
        with open(os.path.join(m.HERE, 'display.txt'), 'w', encoding='utf-8') as f:
            f.write(size + '\n')


def holo_version(ksp):
    """The Holo HUD installed in this KSP folder (its HoloHUD.version) as 'a.b.c', or None."""
    try:
        with open(native(ksp, HOLO_VERSION), encoding='utf-8-sig') as f:
            v = json.load(f)['VERSION']
        return '%s.%s.%s' % (v['MAJOR'], v['MINOR'], v['PATCH']) if isinstance(v, dict) else str(v)
    except (OSError, ValueError, KeyError, TypeError):
        return None


def holo_step(ksp, dry, asked):
    """T1011: the bundled Holo HUD, installed by its own installer (--bundled: it asks no 'install anyway' question, and it
    keeps a NEWER Holo HUD that is already there). asked = the 'Install now?' was answered yes. True when KAL/S may go on."""
    if not os.path.isfile(HOLO_INSTALLER) or not os.path.isdir(os.path.join(HOLO_DIR, 'Install')):
        print('This package has no HoloHUD folder. KAL/S needs Holo HUD (its own release): install it too.')
        return True
    cmd = [sys.executable, HOLO_INSTALLER, '--bundled', '--ksp', ksp]
    if YES:
        cmd.append('--yes')
    if dry:
        cmd.append('--dry')
    if asked:
        cmd.append('--asked')
    if '--fov' in ARGS and ARGS.index('--fov') + 1 < len(ARGS):
        cmd += ['--fov', ARGS[ARGS.index('--fov') + 1]]
    print('\nHolo HUD, bundled with this release (HoloHUD\\install_holohud.py):', flush=True)
    r = subprocess.run(cmd)
    print(flush=True)
    return r.returncode == 0


def install(ksp):
    print('KSP folder: ' + ksp)
    missing = check(ksp)
    versions, known = read_known()
    now = what_is_installed(ksp, versions)
    print('Currently installed: ' + short(now))
    if missing:
        print('These mods were not found. KAL/S installs anyway, but add them before you fly:')
        for name in missing:
            print('  ' + name)
    files = sorted(norm(os.path.relpath(os.path.join(root, f), SRC)) for root, _, fs in os.walk(SRC) for f in fs)
    files, skip = craft_choice(files)                   # T286
    cape = cape_choice(ksp)                              # T511
    cape_was = cape_now(ksp)
    cape_on = cape == 'on' or (cape is None and cape_was)
    if not cape_on:
        files = [rel for rel in files if rel not in CAPE_FILES]   # off: none of the 5 (an earlier install's are removed below)
    old = read_log(ksp)
    fset = set(files)
    mine = ()                                            # T702: the HUD sets are Holo HUD's (HANDED)
    if '--hud' in ARGS:
        sys.exit('--hud: the HUD eye is set in the game (hud_cal.ks) since KAL/S v1.0; --fov 40|60|70 sets the HUD CAM '
                 'field of view. Nothing installed.')
    steps, rsha = plan(ksp, files, old, known, skip)
    steps = [(a, rel, 'the Cape option is off' if a in ('remove', 'restore') and rel in CAPE_FILES else why) for a, rel, why in steps]   # T511
    count = {}
    for a, _, _ in steps:
        count[a] = count.get(a, 0) + 1
    summary = ('%s -> %s. Of the %d release files: %d new, %d replaced, %d already the same, %d of yours kept. Also %d '
               'earlier-release files removed, %d of your files put back, %d other files left alone.'
               % (RELEASE, ksp, len(files), count.get('new', 0), count.get('replace', 0), count.get('same', 0),
                  count.get('keep', 0), count.get('remove', 0), count.get('restore', 0), count.get('leave', 0)))
    try:                                                 # the full list, beside this file
        with open(PLAN, 'w', encoding='utf-8') as f:
            f.write('%s\nIn %s now: %s.\n%s\n' % (summary, ksp, now, '(This was a --dry run, so nothing was changed.)' if DRY else
                                                 '(The installer asks before it changes anything.)'))
            f.write(''.join('%-7s %s%s\n' % (a, rel.replace('/', os.sep), (' (' + why + ')') if why else '')
                            for a, rel, why in steps if a != 'same'))
    except OSError:
        pass
    show(['Keeping your changed craft: ' + rel.split('/')[-1] for a, rel, why in steps
          if a == 'keep' and rel.startswith(CRAFT)], 'not shown')
    work = len(steps) - count.get('same', 0)
    parts = [(count.get('new', 0), 'new'), (count.get('replace', 0) + count.get('restore', 0), 'updated'),
             (count.get('remove', 0), 'removed')]
    todo = ', '.join('%d %s' % (n, w) for n, w in parts if n)
    print(('Files to change: %s.' % todo) if todo else 'Everything is already up to date.')
    hud = ('keep', None)                                 # T702: the HUD eye and field of view are Holo HUD's
    fov = None
    if DRY:
        print('--dry: nothing changed. The full list of what would be done is in ' + PLAN)
        if hud[0] != 'keep':
            print('The HUD eye would be set to ' + hud[0] + '.')
        if fov is not None:
            print('The HUD field of view would be set to %d deg.' % fov)
        if cape is not None:
            print('The Cape would be %s.' % ('the SHIFTED one (the 5 option files)' if cape_on else 'the PUBLISHED one (none of the option files)'))
        holo_step(ksp, True, False)
        font_plan()
        return
    asked = bool(todo) or YES
    if todo and not ask('Install now?'):
        sys.exit('Nothing installed.')
    if ksp_running():
        sys.exit('KSP is running. Close it and try again. Nothing installed.')
    if not holo_step(ksp, False, asked):
        sys.exit('Holo HUD did not install, so KAL/S was not installed either (it needs its HUD). Fix what is said above, '
                 'then run INSTALL.bat again. Nothing of KAL/S installed.')
    stamp = time.strftime('%Y%m%d_%H%M%S')
    bkrel = BACKUP + '/' + stamp
    report, rows = [], {}

    def keep_copy(rel):
        b = native(ksp, bkrel + '/' + rel)
        os.makedirs(os.path.dirname(b), exist_ok=True)
        shutil.copy2(native(ksp, rel), b)

    c = Count('Copying files...', work, 'files done', 'Copying')
    for a, rel, why in steps:
        dst, prev = native(ksp, rel), old.get(rel)
        ours = prev is not None and prev[0] != 'same'           # put there by an earlier install
        if a != 'same':
            c.tick()
        if a in ('new', 'replace'):
            s = rsha(rel)
            if a == 'replace':
                keep_copy(rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(os.path.join(SRC, *rel.split('/')), dst)
            assert sha(dst) == s, rel
            if ours:
                rows[rel] = (prev[0], s, prev[2])
            elif a == 'replace' and sha(native(ksp, bkrel + '/' + rel))[:16] not in known.get(rel, ()):
                rows[rel] = ('repl', s, bkrel)                    # yours before SOCK: --uninstall puts it back
            else:
                rows[rel] = ('new', s, '-')
        elif a == 'same':
            rows[rel] = (prev[0], rsha(rel), prev[2]) if ours else ('same', rsha(rel), '-')
        elif a == 'keep':
            rows[rel] = ('same', sha(dst), '-')
        elif a == 'remove':
            keep_copy(rel)
            os.remove(dst)
            prune(ksp, os.path.dirname(dst))
        elif a == 'restore':
            keep_copy(rel)
            shutil.copy2(native(ksp, prev[2] + '/' + rel), dst)
        report.append('%-7s %s%s' % (a, rel, (' (' + why + ')') if why else ''))
    c.done()
    for rel in skip:                                     # T286: a craft left out stays as an earlier install logged it
        if rel.startswith(mine) and not os.path.isfile(native(ksp, rel)):
            continue                                     # a built HUD file gone: no row
        if rel in old:
            rows[rel] = old[rel]
    if hud[0] != 'keep':                                 # T191: the HUD eye asked for
        dst = native(ksp, HUD_EYE)
        if os.path.isfile(dst):
            keep_copy(HUD_EYE)
        if hud[1] is None:
            if os.path.isfile(dst):
                os.remove(dst)
                report.append('remove  %s (HUD eye %s: the built-in)' % (HUD_EYE, hud[0]))
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            with open(dst, 'w', encoding='utf-8') as f:
                f.write(hud_json(hud[1]))
            report.append('write   %s (HUD eye %s)' % (HUD_EYE, hud[0]))
        print('HUD eye set to ' + hud[0] + '.')
    if fov is not None:                                  # T193: the field of view asked for
        dst = native(ksp, HUD_FOV)
        if os.path.isfile(dst):
            keep_copy(HUD_FOV)
            os.remove(dst)
        if fov != 60:
            with open(dst, 'w', encoding='utf-8', newline='\n') as f:
                f.write('%d\n' % fov)
        report.append('write   %s (HUD field of view %d deg)' % (HUD_FOV, fov))
        print('HUD field of view set to %d deg.' % fov)
    if cape is not None:                                 # T511: said once, the warning only when it changes
        print('Cape set to %s.' % ('SHIFTED' if cape_on else 'PUBLISHED'))
        if cape_on != cape_was:
            print('A vessel landed near the Cape in an existing save moves with the Cape: use a new save, or one with no vessel there.')
    if '--no-setup' not in ARGS:                         # display.txt first: the HUD sets are built for its screen
        one_time(ksp)
    with open(os.path.join(ksp, LOG), 'w', encoding='utf-8') as f:
        f.write('KAL/S install log (for INSTALL.bat --uninstall); %s, last install %s\n' % (RELEASE, stamp))
        f.write(''.join('%-4s %s %s %s\n' % (r[0], r[1], r[2].replace('/', os.sep), rel.replace('/', os.sep))
                        for rel, r in sorted(rows.items())))
    op = os.path.join(ksp, OLD_LOG)
    if os.path.isfile(op):                               # an earlier release's log: its rows are in LOG now
        keep_copy(OLD_LOG)
        os.remove(op)
        report.append('remove  %s (its rows are in %s now)' % (OLD_LOG, LOG))
    bk = native(ksp, bkrel)
    if os.path.isdir(bk):
        with open(os.path.join(bk, 'report.txt'), 'w', encoding='utf-8') as f:
            f.write('%s install into %s, %s\n' % (RELEASE, ksp, stamp))
            f.write('\n'.join(r for r in report if not r.startswith('same')) + '\n')
    print('Installed %s.%s' % (RELEASE, (' The old files were backed up in %s.' % bk) if os.path.isdir(bk) else ''))
    check_fonts()
    print('To learn how to fly, read README.md.')


def uninstall(ksp):
    p = log_path(ksp)
    if p is None:
        sys.exit('There is no %s or %s in %s, so there is nothing to uninstall.' % (LOG, OLD_LOG, ksp))
    if ksp_running() and not DRY:
        sys.exit('KSP is running. Close it and try again.')
    rows = read_log(ksp)
    mine = {rel: r for rel, r in rows.items() if r[0] != 'same' and not HANDED.match(rel)}   # T702: Holo HUD's files are its uninstaller's
    gone, back, kept = [], [], []
    for rel, (kind, s, bk) in sorted(mine.items()):
        dst = native(ksp, rel)
        if os.path.exists(dst) and sha(dst) != s:
            kept.append(rel)
        elif kind == 'repl':
            back.append(rel)
        elif os.path.exists(dst):
            gone.append(rel)
    hv = holo_version(ksp)
    print('KAL/S in %s: %d file(s) to delete, %d of yours put back, %d changed since the install and kept.'
          % (ksp, len(gone), len(back), len(kept)))
    for rel in kept[:10]:
        print('  kept (changed): ' + rel.replace('/', os.sep))
    if hv:
        print('Holo HUD %s stays installed: this removes only KAL/S (HoloHUD\\UNINSTALL.bat removes Holo HUD).' % hv)
    if DRY:
        print('--dry: nothing changed.')
        return
    if not ask('Uninstall KAL/S from %s?' % ksp):
        sys.exit('Nothing changed.')
    m = setup_mod(ksp)                                      # kOS's limit back to 2000 while sock_setup.py is there
    if m is not None and '--no-setup' not in ARGS:
        with redirect_stdout(io.StringIO()):
            m.ipu(False, revert=True)
    c = Count('Removing KAL/S files...', len(mine), 'files done', 'Removing')
    for rel, (kind, s, bk) in sorted(mine.items()):
        c.tick()
        dst = native(ksp, rel)
        if os.path.exists(dst) and sha(dst) != s:
            continue
        if kind == 'repl':
            shutil.copy2(native(ksp, bk + '/' + rel), dst)
        elif os.path.exists(dst):
            os.remove(dst)
            prune(ksp, os.path.dirname(dst))
    c.done()
    os.remove(p)
    bk = os.path.join(ksp, BACKUP)
    print('Uninstalled KAL/S.%s%s%s' % (' %d files you changed were left in place.' % len(kept) if kept else '',
                                        (' Your backups are still in %s.' % bk) if os.path.isdir(bk) else '',
                                        (' Holo HUD %s is still installed.' % hv) if hv else ''))


def main():
    if '--list' in ARGS:
        list_installs()
        return
    if not os.path.isdir(SRC):
        sys.exit('The Install folder is missing next to this file. Unpack the whole zip, then run INSTALL.bat again.')
    ksp = find_ksp()
    if '--uninstall' in ARGS:
        uninstall(ksp)
    else:
        install(ksp)


if __name__ == '__main__':
    main()
