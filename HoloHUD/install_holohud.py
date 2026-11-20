r"""Holo HUD 1.0.0 install: installs this release into a KSP folder. Double-click INSTALL.bat (beside this
file), with KSP closed.

  1. Finds your KSP folders (the ones with KSP_x64.exe and GameData): this folder or one above it, Steam's libraries,
     GOG's games, and every fixed drive to 4 folders deep (at most 10 s). It lists them and asks which: a number, a
     folder, or Enter for the one this folder is in. None found, it asks for the folder.
  2. Checks it: KSP not running; GameData there; kOS there (it says its version; Holo HUD was built against 1.6.0.1).
  3. Compares the release's files (Install\ beside this file) with the KSP folder, says what it will add, replace and
     keep, and asks. A file you have that is NEWER than the release's, and different, is kept unless you say replace.
     Every file it replaces is kept first in HoloHUD_backup\<date-time>\ (in the KSP folder).
     Copies GameData\HoloHUD (the addon), GameData\kOS-Addons\StockCamera (the kOS StockCamera addon 0.3.1, for HUD CAM;
     GPL-3, see its LICENSE.md and SOURCE.txt) and Ships\Script (hud.ks, lib\, the reference HUD set hud\, hud_build.py).
  4. Asks the HUD CAM's field of view: 40, 60 (the default) or 70 deg (wider sees more of the world, the HUD smaller),
     and keeps it in Ships\Script\hud_fov.txt.
  5. Writes Ships\Script\display.txt from your screen size (settings.cfg) if there is none, and BUILDS the HUD sprite
     sets for that screen with hud_build.py (Python alone, a few seconds each): the 60 deg set (the base the HUD needs
     for any screen other than 3840x2160) and the one for your field of view. Run it again with another field of view
     to build that one too. A progress bar shows the copying and the drawing.
  6. Writes HoloHUD_install.txt (in the KSP folder): what it installed and built, for --uninstall.
  7. Cross-aware with KAL/S (which bundles this release): it reads GameData\HoloHUD\HoloHUD.version, and a NEWER Holo
     HUD already there is kept as it is (an older or equal release never overwrites a newer one); --dry says which
     decision it takes. KAL/S's own files are never touched. KAL/S's INSTALL.bat runs this installer first (--bundled).

    INSTALL.bat                     install (asks which KSP folder, and before copying)
    INSTALL.bat --ksp "D:\KSP"      install into that folder
    INSTALL.bat --yes               no questions (with --ksp, or this folder or one above it)
    INSTALL.bat --fov 70            the HUD CAM field of view without asking (40, 60 or 70)
    INSTALL.bat --dry               say what it would do, change nothing
    INSTALL.bat --list              list the KSP folders it finds, change nothing
    INSTALL.bat --uninstall         delete what it installed (unless changed since) and put back what it replaced
    UNINSTALL.bat                   the same (it runs this file with --uninstall); --dry and --yes work with it. It removes
                                    ONLY Holo HUD and StockCamera; when KAL/S is installed it warns that KAL/S needs
                                    Holo HUD and asks before going on (--yes skips the question)
"""
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import time
from collections import deque

sys.dont_write_bytecode = True     # importing the installed hud_build.py must leave no __pycache__ in Ships\Script

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'Install')
KALS_VERSION = 'Ships/Script/KALS_VERSION.txt'       # T1011: KAL/S's marker files (KAL/S bundles this release)
KALS_LOG = 'KALS_install.txt'
HOLO_VERSION = 'GameData/HoloHUD/HoloHUD.version'    # the KSP version file this release installs: its VERSION is the identity


def parse_version(v):
    """A .version file's VERSION (MAJOR / MINOR / PATCH, or a 'a.b.c' text) as a tuple of 3 numbers."""
    if isinstance(v, dict):
        return tuple(int(v.get(k, 0)) for k in ('MAJOR', 'MINOR', 'PATCH'))
    return tuple((int(x) for x in str(v).split('.')[:3]))


def vstr(v):
    return '.'.join(str(x) for x in v)


def version_in(path):
    """The version a HoloHUD.version file holds, or None (no file, or not readable)."""
    try:
        with open(path, encoding='utf-8-sig') as f:
            return parse_version(json.load(f)['VERSION'])
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return None


RELEASE = 'Holo HUD ' + vstr(version_in(os.path.join(SRC, *HOLO_VERSION.split('/'))) or (1, 0, 0))
LOG = 'HoloHUD_install.txt'
BACKUP = 'HoloHUD_backup'
SCRIPT = 'Ships/Script/'
CAMERA = 'GameData/kOS-Addons/StockCamera/'
DEPTH = 4
CAP = 10.0
SKIP_TOP = {'windows', 'windows.old', 'programdata', 'system volume information', 'recovery', 'perflogs',
            'config.msi', 'msocache'}
SKIP_ANY = {'app' + 'data', 'node_modules', '.git'}
STEAM_KSP = os.path.join('steamapps', 'common', 'Kerbal Space Program')
ARGS = sys.argv[1:]
YES = '--yes' in ARGS
DRY = '--dry' in ARGS
BUNDLED = '--bundled' in ARGS      # T1011: called by KAL/S's installer (it asked already, and installs without kOS too)
ASKED = '--asked' in ARGS          # ... and its 'Install now?' was answered yes: no second question
FOVS = (40, 60, 70)
FOV_FILE = 'hud_fov.txt'


class Bar:
    """A text progress bar: redrawn in place on a console, one line per 10 % when the output is a file or a pipe."""
    W = 30

    def __init__(self, total, what):
        self.n, self.t, self.what = 0, max(1, total), what
        try:
            self.tty = sys.stdout.isatty()
        except (AttributeError, ValueError):
            self.tty = False
        self.tenth = -1
        self.draw()

    def draw(self):
        f = min(1.0, self.n / float(self.t))
        line = '[%s%s] %3d %%  %s %d of %d' % ('#' * int(f * self.W), '.' * (self.W - int(f * self.W)), int(f * 100),
                                              self.what, min(self.n, self.t), self.t)
        if self.tty:
            sys.stdout.write('\r' + line)
            sys.stdout.flush()
        elif int(f * 10) > self.tenth:
            self.tenth = int(f * 10)
            print(line, flush=True)

    def step(self, k=1):
        self.n += k
        self.draw()

    def done(self):
        self.n = self.t
        self.draw()
        if self.tty:
            sys.stdout.write('\n')
            sys.stdout.flush()


def sha(p):
    with open(p, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()


def ask(q):
    if YES:
        return True
    try:
        return input(q + ' [y/n] ').strip().lower().startswith('y')
    except EOFError:
        return False


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
    try:
        return os.path.normcase(os.path.realpath(d))
    except (OSError, ValueError):
        return os.path.normcase(os.path.abspath(d))


def reg(hive, path, name):
    try:
        import winreg
        with winreg.OpenKey(getattr(winreg, hive), path) as k:
            return str(winreg.QueryValueEx(k, name)[0])
    except Exception:
        return None


def reg_keys(hive, path):
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


def steam_libraries():
    libs = []
    for s in (reg('HKEY_LOCAL_MACHINE', r'SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
              reg('HKEY_LOCAL_MACHINE', r'SOFTWARE\Valve\Steam', 'InstallPath'),
              reg('HKEY_CURRENT_USER', r'Software\Valve\Steam', 'SteamPath')):
        if not s:
            continue
        s = os.path.normpath(s)
        libs.append(s)
        for vdf in (os.path.join(s, 'steamapps', 'libraryfolders.vdf'), os.path.join(s, 'config', 'libraryfolders.vdf')):
            try:
                text = open(vdf, encoding='utf-8', errors='replace').read()
            except OSError:
                continue
            libs += [p.replace('\\\\', '\\') for p in re.findall(r'^\s*"(?:path|\d+)"\s+"([^"]+)"', text, re.M)
                     if os.path.isabs(p.replace('\\\\', '\\'))]
    return libs


def gog_dirs():
    out = []
    for base in (r'SOFTWARE\WOW6432Node\GOG.com\Games', r'SOFTWARE\GOG.com\Games'):
        for sub in reg_keys('HKEY_LOCAL_MACHINE', base):
            p = reg('HKEY_LOCAL_MACHINE', base + '\\' + sub, 'path')
            if p:
                out.append(p)
    return out


def drives():
    if os.name != 'nt':
        return []
    try:
        import ctypes
        k = ctypes.windll.kernel32
        mask = k.GetLogicalDrives()
        return ['%s:\\' % c for i, c in enumerate('ABCDEFGHIJKLMNOPQRSTUVWXYZ')
                if mask >> i & 1 and k.GetDriveTypeW('%s:\\' % c) == 3]
    except Exception:
        return []


def linked(e):
    if e.is_symlink():
        return True
    st = e.stat(follow_symlinks=False)
    return bool(getattr(st, 'st_file_attributes', 0) & 0x400) and getattr(st, 'st_reparse_tag', 0) == 0xA0000003


def scan(roots, add, seen, cap):
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


def find_installs():
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
    d = near()
    if d:
        add(d)
    for lib in steam_libraries():
        add(os.path.join(lib, STEAM_KSP))
    for g in gog_dirs():
        add(g)
    if not scan(drives(), add, seen, CAP):
        print('Stopped searching after %g seconds, so some folders were not checked.' % CAP)
    return found


def note(d):
    bits = []
    hv = version_in(os.path.join(d, *HOLO_VERSION.split('/')))
    if hv or os.path.isfile(os.path.join(d, LOG)):
        bits.append('Holo HUD ' + vstr(hv) if hv else 'Holo HUD installed')
    if os.path.isfile(os.path.join(d, 'Ships', 'Script', 'KALS_VERSION.txt')) or os.path.isfile(os.path.join(d, KALS_LOG)):
        bits.append('KAL/S')
    if os.path.isdir(os.path.join(d, 'GameData', 'FerramAerospaceResearch')):
        bits.append('FAR')
    return ', '.join(bits)


def find_ksp():
    if '--ksp' in ARGS:
        return os.path.abspath(ARGS[ARGS.index('--ksp') + 1])
    d = near()
    if YES:
        if d is None:
            sys.exit('No KSP folder was found next to this one. Name it with --ksp "<folder>".')
        return d
    print('Finding your KSP folders...', flush=True)
    found = find_installs()
    if not found:
        print('No KSP folder was found.')
        try:
            return os.path.abspath(input('Type the path of your KSP folder, the one with KSP_x64.exe: ').strip().strip('"'))
        except EOFError:
            sys.exit('Nothing changed.')
    keys = [key(f) for f in found]
    default = keys.index(key(d)) if d is not None and key(d) in keys else (0 if len(found) == 1 else None)
    print('These KSP folders were found:')
    for i, f in enumerate(found):
        print('  %d  %s  %s' % (i + 1, f, note(f)))
    q = '%s which folder? Type %s or a KSP folder path%s: ' % (
        'Uninstall from' if '--uninstall' in ARGS else 'Install into', '1' if len(found) == 1 else '1-%d' % len(found),
        '' if default is None else ', or press Enter for %d' % (default + 1))
    while True:
        try:
            a = input(q).strip().strip('"')
        except EOFError:
            sys.exit('Nothing changed.')
        if not a and default is not None:
            return found[default]
        if a.isdigit() and 1 <= int(a) <= len(found):
            return found[int(a) - 1]
        if a and not a.isdigit():
            p = os.path.abspath(a)
            if os.path.isdir(os.path.join(p, 'GameData')):
                return p
            print('There is no GameData folder in %s, so it is not a KSP folder.' % p)
            continue
        print('Please type a number from the list or the path of a KSP folder.')


def native(ksp, rel):
    return os.path.join(ksp, *rel.split('/'))


def kos_version(ksp):
    try:
        return json.load(open(native(ksp, 'GameData/kOS/kOS.version'), encoding='utf-8-sig'))['VERSION']
    except (OSError, ValueError, KeyError):
        return None


def check(ksp):
    gd = os.path.join(ksp, 'GameData')
    if not os.path.isdir(gd):
        sys.exit('There is no GameData folder in %s, so it is not a KSP folder.' % ksp)
    if not os.path.isfile(os.path.join(ksp, 'KSP_x64.exe')):
        print('There is no KSP_x64.exe in %s.' % ksp)
        if not BUNDLED and not ask('Install there anyway?'):
            sys.exit('Nothing installed.')
    if ksp_running() and not DRY:
        sys.exit('KSP is running. Close it and try again. Nothing installed.')
    if not os.path.isfile(native(ksp, 'GameData/kOS/Plugins/kOS.dll')):
        print('kOS is NOT installed in %s (no GameData\\kOS\\Plugins\\kOS.dll). Holo HUD runs from kOS: install kOS first '
              '(https://github.com/KSP-KOS/KOS/releases, or CKAN).' % ksp)
        if BUNDLED:                                                          # KAL/S installs without kOS too (it warned)
            print('Installing anyway (KAL/S asked): add kOS before you fly.')
        elif YES or not ask('Install Holo HUD there anyway?'):               # --yes never installs without kOS
            sys.exit('Nothing installed.')
    else:
        v = kos_version(ksp)
        print('kOS %s found.' % (v or '(version unknown)') + ('' if v and v.startswith('1.6.0') else
              ' Holo HUD was built against kOS 1.6.0.1; another version may not load its C# half (the HUD then runs in kOS alone).'))
    if os.path.isdir(native(ksp, 'GameData/FerramAerospaceResearch')):
        print('FAR is installed: Holo HUD does not depend on it.')
    if kals_here(ksp):
        print('KAL/S is installed here: it uses Holo HUD (hud.ks, lib_hud.ks, lib_kmsg.ks, lib_logsw.ks, lib_screen.ks); '
              'a file newer than this release\'s is kept (you are asked). KAL/S\'s own files are never touched.')


def installed_version(ksp):
    """The Holo HUD installed in this KSP folder (GameData\\HoloHUD\\HoloHUD.version), or None."""
    return version_in(native(ksp, HOLO_VERSION))


def kals_here(ksp):
    """KAL/S in this KSP folder: its KALS_VERSION.txt (first line) or, without it, 'KAL/S' when its install log is
    there; None when neither is."""
    try:
        for ln in open(native(ksp, KALS_VERSION), encoding='utf-8', errors='replace').read().splitlines():
            if ln.strip():
                return ln.strip()
    except OSError:
        pass
    return 'KAL/S' if os.path.isfile(native(ksp, KALS_LOG)) else None


def decide(ksp):
    """What this release does about the Holo HUD already in the KSP folder -> (code, a line saying it):
    new (none there), same (this version: the files that differ are replaced), upgrade (an older one: replaced, the old
    kept in HoloHUD_backup), newer (a NEWER one: nothing is changed)."""
    rel = version_in(os.path.join(SRC, *HOLO_VERSION.split('/'))) or (1, 0, 0)
    have = installed_version(ksp)
    if have is None:
        return 'new', 'Holo HUD: none installed here; %s will be installed.' % RELEASE
    if have > rel:
        return 'newer', ('Holo HUD %s is installed here and is NEWER than this release (%s): it is kept as it is and '
                         'nothing of this release is installed.' % (vstr(have), vstr(rel)))
    if have == rel:
        return 'same', ('Holo HUD %s is installed here, the same version as this release: files that differ are '
                        'replaced (the old kept in %s).' % (vstr(have), BACKUP))
    return 'upgrade', ('Holo HUD %s is installed here; this release (%s) is newer and replaces it (the old files are kept '
                       'in %s).' % (vstr(have), vstr(rel), BACKUP))


def release_files():
    out = []
    for root, _, fs in os.walk(SRC):
        for f in fs:
            p = os.path.join(root, f)
            out.append(os.path.relpath(p, SRC).replace('\\', '/'))
    return sorted(out)


def camera_version(ksp):
    """The installed StockCamera's version text, or None."""
    try:
        v = json.load(open(native(ksp, CAMERA + 'KOS-StockCamera.version'), encoding='utf-8-sig'))['VERSION']
    except (OSError, ValueError, KeyError):
        return None
    return v if isinstance(v, str) else '%s.%s.%s' % (v.get('MAJOR', 0), v.get('MINOR', 0), v.get('PATCH', 0))


def old_camera(ksp):
    """True when the installed StockCamera is older than 0.3 (CKAN's 0.2 has no FREECAMERA): the release's replaces it
    whatever the file dates."""
    v = camera_version(ksp)
    try:
        return v is not None and tuple(int(x) for x in v.split('.')[:2]) < (0, 3)
    except ValueError:
        return False


def plan(ksp, files):
    """-> (add, same, replace, newer): rel paths. newer = differs and the KSP folder's is newer than the release's."""
    add, same, replace, newer = [], [], [], []
    try:
        logged = json.load(open(native(ksp, LOG), encoding='utf-8')).get('files', {})    # T1011: what an earlier install logged
    except (OSError, ValueError):
        logged = {}
    for rel in files:
        dst = native(ksp, rel)
        src = os.path.join(SRC, *rel.split('/'))
        if not os.path.isfile(dst):
            add.append(rel)
        elif os.path.getsize(dst) == os.path.getsize(src) and sha(dst) == sha(src):
            same.append(rel)
        elif logged.get(rel) == sha(dst):
            replace.append(rel)                              # Holo HUD's own file, unchanged since it was installed: upgraded
        elif os.path.getmtime(dst) > os.path.getmtime(src) + 2 and not (rel.startswith(CAMERA) and old_camera(ksp)):
            newer.append(rel)
        else:
            replace.append(rel)
    return add, same, replace, newer


def show(title, rel, n=8):
    if not rel:
        return
    print('%s (%d):' % (title, len(rel)))
    dirs = {}
    for r in rel:
        dirs.setdefault(r.rsplit('/', 1)[0] if '/' in r else '.', []).append(r)
    k = 0
    for d, fs in sorted(dirs.items()):
        if k >= n:
            print('  ... and %d more folders' % (len(dirs) - k))
            break
        print('  %s/  %d file%s' % (d, len(fs), '' if len(fs) == 1 else 's'))
        k += 1


def screen_size(ksp):
    try:
        cfg = open(native(ksp, 'settings.cfg'), encoding='utf-8', errors='replace').read()
    except OSError:
        return None
    w = re.search(r'^\s*SCREEN_RESOLUTION_WIDTH\s*=\s*(\d+)', cfg, re.M)
    h = re.search(r'^\s*SCREEN_RESOLUTION_HEIGHT\s*=\s*(\d+)', cfg, re.M)
    return '%sx%s' % (w.group(1), h.group(1)) if w and h else None


def built_list(log):
    """The sets an install built (pre2's log has one name or none)."""
    b = log.get('built')
    return [b] if isinstance(b, str) else list(b or [])


def display(ksp, did, fov, prior):
    """display.txt for the screen (written only when there is none), and the sprite sets for it: the 60 deg set and the
    one for fov."""
    size = screen_size(ksp)
    dpath = native(ksp, SCRIPT + 'display.txt')
    have = open(dpath, encoding='utf-8', errors='replace').read().split()[0].lower() if os.path.isfile(dpath) and \
        open(dpath, encoding='utf-8', errors='replace').read().split() else None
    if size is None:
        print('Screen: no settings.cfg (or no screen size in it) in %s; display.txt left as it is. Without it the HUD is '
              'drawn for 3840x2160.' % ksp)
        return
    target = size
    if have is not None and have != size:
        print('Screen: your KSP is %s but Ships\\Script\\display.txt says %s; it is kept (edit it if the HUD does not '
              'line up with the view).' % (size, have))
        target = have
    sdir = native(ksp, SCRIPT)
    try:
        w, h = (int(x) for x in target.lower().split('x'))
    except ValueError:
        print('Screen: display.txt\'s "%s" is not a size like 1920x1080; no HUD set built.' % target)
        return
    # the sets the HUD reads (lib_screen.ks): hud/ = 3840x2160 at 60 deg, hud_<W>x<H>/ = another screen at 60 deg (needed
    # before any other field of view on that screen), hud_<W>x<H>_fov<N>/ = another field of view
    need = [] if target == '3840x2160' else ['hud_' + target]
    if fov != 60:
        need.append('hud_%s_fov%d' % (target, fov))
    stamp = ref_stamp(sdir)
    ours = set(n.split('/')[-1] for n in built_list(prior))
    stale = prior.get('ref') != stamp
    did['built'] = []
    for name in need:
        have_set = os.path.isfile(os.path.join(sdir, name, 'hud_layout.txt'))
        if have_set and not (name in ours and stale):
            print('Screen: %s, %d deg; the HUD set %s is there.' % (target, 60 if name == 'hud_' + target else fov, name))
            continue
        if DRY:
            print('Screen: would build Ships\\Script\\%s with hud_build.py.' % name)
            continue
        if not os.path.isfile(os.path.join(sdir, 'hud_build.py')) or stamp is None:
            print('Screen: %s has no HUD set and hud_build.py or the reference set hud\\ is missing; the HUD will not '
                  'line up.' % name)
            return
        print('Screen: building the HUD set %s (%s, %d deg; a few seconds)...'
              % (name, target, 60 if name == 'hud_' + target else fov), flush=True)
        try:
            build_set(sdir, name, w, h, 60 if name == 'hud_' + target else fov)
        except Exception as e:                                   # noqa: the build's own failure, said, then go on
            print('   hud_build.py failed (%s). The HUD will be drawn for 3840x2160 / 60 deg and will not line up.' % e)
            return
        did['built'].append(SCRIPT + name)
        print('   built Ships\\Script\\%s.' % name)
    did['ref'] = stamp
    if have is None and size != '3840x2160' and not DRY:
        with open(dpath, 'w', encoding='utf-8') as f:
            f.write(size + '\n')
        did['display'] = sha(dpath)
        print('Wrote Ships\\Script\\display.txt (%s).' % size)
    elif have is None and size != '3840x2160':
        print('Would write Ships\\Script\\display.txt (%s).' % size)


def fov_now(ksp):
    """The player's hud_fov.txt number, or None."""
    p = native(ksp, SCRIPT + FOV_FILE)
    try:
        return int(round(float(open(p, encoding='utf-8', errors='replace').read().split()[0])))
    except (OSError, ValueError, IndexError):
        return None


def choose_fov(ksp):
    """--fov N, else ask (Enter = the player's hud_fov.txt, or 60); --yes takes that default."""
    have = fov_now(ksp)
    dflt = have if have in FOVS else 60
    if '--fov' in ARGS:
        try:
            f = int(ARGS[ARGS.index('--fov') + 1])
        except (IndexError, ValueError):
            f = None
        if f not in FOVS:
            sys.exit('--fov takes 40, 60 or 70.')
        return f
    if YES:
        return dflt
    print('\nThe HUD CAM\'s field of view (the camera the HUD is drawn for; wider sees more, the HUD smaller):')
    for i, f in enumerate(FOVS):
        print('  %d  %d deg%s' % (i + 1, f, '   (Enter)' if f == dflt else ''))
    while True:
        try:
            a = input('Field of view, 1-3 [Enter = %d deg]: ' % dflt).strip()
        except EOFError:
            a = ''
        if a == '':
            return dflt
        if a in ('1', '2', '3'):
            return FOVS[int(a) - 1]
        if a.isdigit() and int(a) in FOVS:
            return int(a)
        print('  1, 2 or 3, please.')


def set_fov(ksp, fov, did):
    """hud_fov.txt = fov (the player's choice); the old text kept in the log so --uninstall can put it back."""
    p = native(ksp, SCRIPT + FOV_FILE)
    old = open(p, encoding='utf-8', errors='replace').read() if os.path.isfile(p) else None
    if old is not None and fov_now(ksp) == fov:
        print('Field of view: %d deg (Ships\\Script\\%s, kept).' % (fov, FOV_FILE))
        return
    if DRY:
        print('Field of view: would write Ships\\Script\\%s (%d deg).' % (FOV_FILE, fov))
        return
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'w', encoding='utf-8', newline='\n') as f:
        f.write('%d\n' % fov)
    did['fov'] = sha(p)
    did['fov_prior'] = old
    print('Field of view: %d deg, written to Ships\\Script\\%s.' % (fov, FOV_FILE))


def ref_stamp(sdir):
    """The reference set's identity: a set built from another reference is rebuilt."""
    h = hashlib.sha256()
    for f in ('hud_layout.txt', 'sprites.txt'):
        try:
            h.update(open(os.path.join(sdir, 'hud', f), 'rb').read())
        except OSError:
            return None
    try:
        h.update(open(os.path.join(sdir, 'hud_build.py'), 'rb').read())
    except OSError:
        return None
    return h.hexdigest()[:16]


def build_set(sdir, name, w, h, fov):
    """Builds Ships/Script/<name> with the installed hud_build.py (in a .part folder, then moved: never half a set)."""
    spec = importlib.util.spec_from_file_location('hud_build', os.path.join(sdir, 'hud_build.py'))
    hb = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(hb)
    dest = os.path.join(sdir, name)
    part = dest + '.part'
    shutil.rmtree(part, ignore_errors=True)
    bar = Bar(hb.count(w, h, fov), 'drawing %s, sprite' % name)
    try:
        hb.build(os.path.join(sdir, 'hud'), part, w, h, fov, log=None, tick=bar.step)
    except SystemExit as e:
        shutil.rmtree(part, ignore_errors=True)
        raise RuntimeError(str(e))
    bar.done()
    shutil.rmtree(dest, ignore_errors=True)
    os.replace(part, dest)


def install(ksp):
    code, said = decide(ksp)
    print(said)
    if code == 'newer':
        print('--dry: nothing would be changed.' if DRY else 'Nothing of Holo HUD was changed.')
        return
    files = release_files()
    if not files:
        sys.exit('The Install folder beside this file is empty or missing. Unzip the whole release first.')
    add, same, replace, newer = plan(ksp, files)
    print('\n%s into %s' % (RELEASE, ksp))
    show('New files', add)
    show('Replaced (the old kept in %s\\<date-time>)' % BACKUP, replace)
    show('Already the same, left alone', same, 3)
    show('Yours, newer than the release\'s: kept unless you say replace', newer)
    cv = camera_version(ksp)
    cam_in = any(r.startswith(CAMERA) for r in add + replace + newer)
    if cv and cam_in:
        print('kOS StockCamera %s is installed already; the release has 0.3.1.0 (HUD CAM needs 0.3.x: FREECAMERA).' % cv)
    if DRY:
        print('\n--dry: nothing changed.')
    do_newer = bool(newer) and not DRY and not YES and ask('Replace the %d newer file(s) of yours too?' % len(newer))
    if not DRY and not (add or replace or do_newer) and not same:
        sys.exit('Nothing to do.')
    if not DRY and (add or replace or do_newer):
        if not (BUNDLED and ASKED) and not ask('Install?'):
            sys.exit('Nothing installed.')
    did = {'files': {}, 'backup': None, 'replaced': []}
    try:                                                      # T1011: what an earlier Holo HUD install logged (its own files)
        mine_before = json.load(open(native(ksp, LOG), encoding='utf-8')).get('files', {})
    except (OSError, ValueError):
        mine_before = {}
    todo = add + replace + (newer if do_newer else [])
    fov = choose_fov(ksp)
    if not DRY:
        stamp = time.strftime('%Y%m%d-%H%M%S')
        bdir = os.path.join(ksp, BACKUP, stamp)
        nb = sum(1 for rel in todo if os.path.isfile(native(ksp, rel)))
        bar = Bar(len(todo) + nb, 'copying, file') if todo else None
        for rel in todo:
            src, dst = os.path.join(SRC, *rel.split('/')), native(ksp, rel)
            if os.path.isfile(dst):
                bk = os.path.join(bdir, *rel.split('/'))
                os.makedirs(os.path.dirname(bk), exist_ok=True)
                shutil.copy2(dst, bk)
                did['backup'] = os.path.join(BACKUP, stamp)
                if mine_before.get(rel) != sha(dst):         # an earlier Holo HUD's own file (an upgrade) is not put back by --uninstall
                    did['replaced'].append(rel)
                bar.step()
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            did['files'][rel] = sha(dst)
            bar.step()
        if bar:
            bar.done()
        for rel in same:
            did['files'].setdefault(rel, None)               # ours or theirs? not known: --uninstall will not delete it
    prior = {}
    lp = native(ksp, LOG)
    if os.path.isfile(lp):
        try:
            prior = json.load(open(lp, encoding='utf-8'))
        except (OSError, ValueError):
            prior = {}
    set_fov(ksp, fov, did)
    display(ksp, did, fov, prior)
    if DRY:
        return
    files_log = dict(prior.get('files', {}))
    for rel, h in did['files'].items():
        if h is not None:
            files_log[rel] = h
    out = {'release': RELEASE, 'time': time.strftime('%Y-%m-%d %H:%M:%S'), 'files': files_log,
           'replaced': sorted(set(prior.get('replaced', []) + did['replaced'])),
           'backups': prior.get('backups', []) + ([did['backup']] if did['backup'] else []),
           'built': sorted(set(built_list(prior) + did.get('built', []))), 'ref': did.get('ref') or prior.get('ref'),
           'display': did.get('display') or prior.get('display'), 'fov': did.get('fov') or prior.get('fov'),
           'fov_prior': did['fov_prior'] if 'fov' in did and 'fov' not in prior else prior.get('fov_prior')}
    with open(lp, 'w', encoding='utf-8') as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print('\nDone: %d file(s) added, %d replaced, %d already the same, %d of yours kept.'
          % (len(add), len(replace) + (len(newer) if do_newer else 0), len(same), 0 if do_newer else len(newer)))
    print('What was installed is listed in %s (for UNINSTALL.bat).' % LOG)
    if not BUNDLED:
        print('Next: start KSP, load an aircraft with a kOS part, open the kOS terminal and type, each on its own line:')
        print('    SWITCH TO 0.')
        print('    RUN hud.ks.')
        print('See INSTALL.txt.')


def uninstall(ksp):
    lp = native(ksp, LOG)
    if not os.path.isfile(lp):
        sys.exit('There is no %s in %s: nothing to uninstall (it lists what an install put there).' % (LOG, ksp))
    if ksp_running() and not DRY:
        sys.exit('KSP is running. Close it and try again. Nothing changed.')
    log = json.load(open(lp, encoding='utf-8'))
    gone, kept, back = [], [], []
    for rel, h in sorted(log['files'].items()):
        p = native(ksp, rel)
        if not os.path.isfile(p):
            continue
        if sha(p) == h:
            gone.append(rel)
        else:
            kept.append(rel)
    print('%s in %s: %d file(s) to delete, %d changed since the install and kept.' % (log['release'], ksp, len(gone),
                                                                                       len(kept)))
    for rel in kept[:10]:
        print('  kept (changed): ' + rel)
    kv = kals_here(ksp)
    if kv:
        print('\nWARNING: %s is installed in this KSP folder and needs Holo HUD: its programs load Holo HUD\'s hud.ks '
              'libraries (lib_hud.ks, lib_kmsg.ks, lib_logsw.ks, lib_screen.ks) and will NOT run without them. KAL/S\'s '
              'own UNINSTALL.bat removes KAL/S and leaves Holo HUD; this one removes only Holo HUD and StockCamera.' % kv)
    if DRY:
        print('--dry: nothing changed.')
        return
    if not ask('Uninstall Holo HUD%s?' % (' anyway (KAL/S stays installed, without its HUD)' if kv else '')):
        sys.exit('Nothing changed.')
    sets = [b for b in built_list(log) if os.path.isdir(native(ksp, b))]
    bar = Bar(len(gone) + len(log.get('replaced', [])) + len(sets), 'removing, item')
    for rel in gone:
        os.remove(native(ksp, rel))
        bar.step()
    for rel in log.get('replaced', []):                       # what the install replaced: back from the oldest backup
        for b in log.get('backups', []):
            bk = os.path.join(ksp, b, *rel.split('/'))
            if os.path.isfile(bk):
                os.makedirs(os.path.dirname(native(ksp, rel)), exist_ok=True)
                if not os.path.isfile(native(ksp, rel)):
                    shutil.copy2(bk, native(ksp, rel))
                    back.append(rel)
                break
        bar.step()
    for b in sets:
        shutil.rmtree(native(ksp, b), ignore_errors=True)
        bar.step()
    bar.done()
    fp = native(ksp, SCRIPT + FOV_FILE)
    if log.get('fov') and os.path.isfile(fp) and sha(fp) == log['fov']:
        if log.get('fov_prior') is not None:
            with open(fp, 'w', encoding='utf-8', newline='') as f:
                f.write(log['fov_prior'])
        else:
            os.remove(fp)
    dp = native(ksp, SCRIPT + 'display.txt')
    if log.get('display') and os.path.isfile(dp) and sha(dp) == log['display']:
        os.remove(dp)
    for root, dirs, fs in os.walk(os.path.join(ksp, 'GameData'), topdown=False):       # empty folders it leaves
        if root.endswith(('HoloHUD', 'StockCamera', 'kOS-Addons', 'Plugins')) and not os.listdir(root):
            os.rmdir(root)
    for root, dirs, fs in os.walk(native(ksp, SCRIPT.rstrip('/')), topdown=False):
        if os.path.basename(root) in ('lib', 'hud') and not os.listdir(root):
            os.rmdir(root)
    os.remove(lp)
    print('Removed %d file(s), put back %d from %s. The backups stay in %s.' % (len(gone), len(back), BACKUP, BACKUP))


def main():
    if '--list' in ARGS:
        print('Finding your KSP folders...', flush=True)
        found = find_installs()
        for i, f in enumerate(found):
            print('  %d  %s  %s' % (i + 1, f, note(f)))
        print('Found %d.' % len(found) if found else 'No KSP folder was found.')
        return
    ksp = find_ksp()
    if '--uninstall' in ARGS:
        uninstall(ksp)
        return
    check(ksp)
    install(ksp)


main()
