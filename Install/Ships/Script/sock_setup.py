r"""SOCK ops3q setup: double-click sock_setup.bat (in KSP's Ships\Script) before each play session, with KSP closed.

  1. Checks the Python packages the ENTRY TRAJ pictures need (numpy, Pillow, matplotlib); offers to install them.
  2. Raises kOS's instruction limit from 2000 to 10000 per update, as the scripts ask (kOS 1.6.0.1 only: two numbers in
     GameData\kOS\Plugins\kOS.dll). The original is kept in kos_backup\; --revert puts it back. Again after a kOS update.
  3. Writes display.txt with KSP's screen size (from settings.cfg) when the HUD has a set for it.
  4. Says whether the logs are on (logging.txt: one word, on or off).
  5. Starts the ENTRY TRAJ watcher (traj_bg_watch.py): leave its window open while you fly.

    python sock_setup.py              all five steps
    python sock_setup.py --check      report only, change nothing
    python sock_setup.py --no-watch   steps 1-4 only
    python sock_setup.py --revert     put the original kOS.dll back
"""
import hashlib
import importlib
import importlib.util
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))            # KSP's Ships\Script, the kOS Archive
KSP = os.path.dirname(os.path.dirname(HERE))
DLL = os.path.join(KSP, 'GameData', 'kOS', 'Plugins', 'kOS.dll')
BACKUP = os.path.join(HERE, 'kos_backup', 'kOS.dll.original')
SETTINGS = os.path.join(KSP, 'settings.cfg')
IPU = 10000                                                   # what deorbit_plan and ops3q set (SET CONFIG:IPU)
STOCK_IPU = 2000
ORIG_SHA = 'fa778010db230cd9ada5ff1fc8e21880da4771579278efa8af70f19d8202260e'    # kOS 1.6.0.1's kOS.dll
# the two int32s that hold the limit: the operand of the IPU setter's ldc.i4, and the difficulty slider's maxValue
SETTER = re.compile(re.escape(bytes.fromhex('02 1F 32 20')) + b'(.{4})'
                    + re.escape(bytes.fromhex('03 28 F3 04 00 0A 28 03 02 00 0A 7D EB 02 00 04 2A')), re.S)
SLIDER = re.compile(re.escape(b'S\x08\x08maxValue') + b'(.{4})', re.S)
PACKAGES = (('numpy', 'numpy'), ('PIL', 'pillow'), ('matplotlib', 'matplotlib'))      # (import name, pip name)


def missing_packages():
    """The pip names of the packages that are not installed."""
    importlib.invalidate_caches()
    return [pip for mod, pip in PACKAGES if importlib.util.find_spec(mod) is None]


def ask(question):
    """True on Enter or y / yes; False on anything else or when there is no console to answer."""
    try:
        return input(question + ' [Y/n] ').strip().lower() in ('', 'y', 'yes')
    except EOFError:
        return False


def packages(check):
    """Step 1; True if all three packages are installed at the end."""
    miss = missing_packages()
    if not miss:
        print('1. Python packages: numpy, Pillow and matplotlib are installed.')
        return True
    print('1. Python packages: missing %s (the ENTRY TRAJ pictures need numpy, Pillow and matplotlib).' % ', '.join(miss))
    if check:
        return False
    if not ask('   Install with pip now?'):
        print('   Not installed: ops3q flies without the ENTRY TRAJ display.')
        return False
    subprocess.call([sys.executable, '-m', 'pip', 'install'] + miss)
    miss = missing_packages()
    if miss:
        print('   Still missing: %s. In a command window: %s -m pip install %s'
              % (', '.join(miss), os.path.basename(sys.executable), ' '.join(miss)))
        return False
    print('   Installed.')
    return True


def ksp_running():
    """True if a KSP process shows in the process list."""
    try:
        out = subprocess.run(['tasklist'] if os.name == 'nt' else ['ps', '-A'], capture_output=True, text=True).stdout
    except OSError:
        return False
    return re.search(r'\bKSP(_x64)?(\.exe|\.x86_64|\.app)?\b', out) is not None


def dll_layout(b):
    """(the original 1.6.0.1 file, its two limits now, their offsets) from kOS.dll's bytes, or None for another kOS."""
    s, l = list(SETTER.finditer(b)), list(SLIDER.finditer(b))
    if len(s) != 1 or len(l) != 1:
        return None
    offs = (s[0].start(1), l[0].start(1))
    limits = [struct.unpack('<i', b[o:o + 4])[0] for o in offs]
    orig = with_limit(b, offs, STOCK_IPU)
    return (orig, limits, offs) if hashlib.sha256(orig).hexdigest() == ORIG_SHA else None


def with_limit(b, offs, n):
    """b with both limits set to n."""
    p = bytearray(b)
    for o in offs:
        p[o:o + 4] = struct.pack('<i', n)
    return bytes(p)


def ipu(check, revert):
    """Step 2 (or --revert): kOS.dll's instruction limit."""
    want = STOCK_IPU if revert else IPU
    if not os.path.isfile(DLL):
        print('2. kOS: no kOS.dll at %s. Is this folder KSP\'s Ships\\Script, and kOS installed?' % DLL)
        return
    b = open(DLL, 'rb').read()
    lay = dll_layout(b)
    if lay is None:
        print('2. kOS: this kOS.dll is not kOS 1.6.0.1, so it is left alone. The guidance then runs at kOS\'s limit of '
              '%d instructions per update, up to five times slower than it was tuned for.' % STOCK_IPU)
        return
    orig, limits, offs = lay
    if limits == [want, want]:
        print('2. kOS: the instruction limit is %d%s.' % (want, ' (the original kOS.dll)' if revert else ''))
        return
    print('2. kOS: the instruction limit is %d; setting it to %d.' % (limits[0], want))
    if check:
        print('   (--check: not changed)')
        return
    if ksp_running():
        print('   KSP is running: close it, then run the setup again.')
        return
    if not os.path.isfile(BACKUP):
        os.makedirs(os.path.dirname(BACKUP), exist_ok=True)
        with open(BACKUP, 'wb') as f:
            f.write(orig)
    new = with_limit(orig, offs, want)
    tmp = DLL + '.new'
    with open(tmp, 'wb') as f:
        f.write(new)
    if open(tmp, 'rb').read() != new:
        print('   kOS.dll.new did not read back as written: kOS.dll is unchanged.')
        return
    try:
        os.replace(tmp, DLL)
    except OSError as e:
        print('   Could not replace kOS.dll (%s): close KSP, then run the setup again.' % e)
        return
    print('   Done: kOS.dll is the original again.' if revert else '   Done (the original is kept in %s).' % BACKUP)


def hud_sets():
    """The screen sizes the HUD has a set for: hud\\ is 3840x2160, hud_<W>x<H>\\ the others."""
    sizes = ['3840x2160']
    for d in os.listdir(HERE):
        if re.fullmatch(r'hud_\d+x\d+', d) and os.path.isfile(os.path.join(HERE, d, 'hud_layout.txt')):
            sizes.append(d[4:])
    return sorted(sizes, key=lambda s: -int(s.split('x')[0]))


def display(check):
    """Step 3: display.txt from settings.cfg's SCREEN_RESOLUTION_WIDTH / _HEIGHT."""
    try:
        cfg = open(SETTINGS, encoding='utf-8', errors='replace').read()
    except OSError:
        print('3. Screen: no settings.cfg at %s; display.txt left as it is.' % SETTINGS)
        return
    w = re.search(r'^\s*SCREEN_RESOLUTION_WIDTH\s*=\s*(\d+)', cfg, re.M)
    h = re.search(r'^\s*SCREEN_RESOLUTION_HEIGHT\s*=\s*(\d+)', cfg, re.M)
    if not (w and h):
        print('3. Screen: settings.cfg has no screen size; display.txt left as it is.')
        return
    size = '%sx%s' % (w.group(1), h.group(1))
    path = os.path.join(HERE, 'display.txt')
    have = open(path, encoding='utf-8', errors='replace').read().strip() if os.path.isfile(path) else None
    sets = hud_sets()
    if size in sets:
        if have == size or (have is None and size == '3840x2160'):
            print('3. Screen: %s; display.txt is right.' % size)
            return
        if size == '3840x2160':                               # no file = 3840x2160: a stale one goes
            print('3. Screen: %s; removing the old display.txt (%s).' % (size, have))
        else:
            print('3. Screen: %s; writing display.txt.' % size)
    else:
        print('3. Screen: %s has no HUD set (the sets: %s), so the HUD is drawn for 3840x2160 and will not line up '
              'with the view; the windows work at any size.' % (size, ', '.join(sets)))
        if have is None:
            return
    if check:
        print('   (--check: not changed)')
    elif size in sets and size != '3840x2160':
        with open(path, 'w', encoding='utf-8') as f:
            f.write(size + '\n')
    else:
        os.remove(path)


def logs():
    """Step 4: the logs' switch, logging.txt (one word: on or off; no file: off), read by each program when it starts.
    A report: the file is changed by hand."""
    path = os.path.join(HERE, 'logging.txt')
    on = os.path.isfile(path) and open(path, encoding='utf-8', errors='replace').read().strip().lower() == 'on'
    print('4. Logs: %s. To turn them %s, change the word in %s to %s.'
          % ('on (in the logs folder beside it)' if on else 'off', 'off' if on else 'on', path, 'off' if on else 'on'))


def main():
    args = sys.argv[1:]
    if any(a not in ('--check', '--no-watch', '--revert') for a in args):
        print(__doc__)
        return 2
    check = '--check' in args
    print('SOCK ops3q setup in %s' % HERE)
    if '--revert' in args:
        ipu(check, revert=True)
        return 0
    ok = packages(check)
    ipu(check, revert=False)
    display(check)
    logs()
    if check or '--no-watch' in args:
        return 0
    if not ok:
        print('5. The ENTRY TRAJ watcher needs the packages of step 1: not started.')
        return 1
    print('5. The ENTRY TRAJ watcher: leave this window open while you fly (close it to stop).')
    try:
        return subprocess.call([sys.executable, os.path.join(HERE, 'traj_bg_watch.py')])
    except KeyboardInterrupt:                                 # Ctrl-C reaches the watcher too; it stops by itself
        return 0


if __name__ == '__main__':
    sys.exit(main())
