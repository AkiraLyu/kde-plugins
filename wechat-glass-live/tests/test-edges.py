#!/usr/bin/env python3
"""Measure the visible bar edge after moves in an isolated KWin session."""
import json, os, pathlib, subprocess, sys, time
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent
BUILD = pathlib.Path(os.environ.get('WECHAT_GLASS_BUILD_DIR', ROOT.parent/'build')).resolve()
EFFECT = 'wechat-glass-live-v5'
SCALE = float(os.environ.get('WECHAT_GLASS_TEST_SCALE', '1.25'))
RUN = BUILD / 'test-results' / f'edge-run-{EFFECT}-{SCALE}'
RUN.mkdir(parents=True, exist_ok=True)

def call(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=20).stdout.strip()

def dbus(*args):
    return call('qdbus6', 'org.kde.KWin', *args)

def state():
    return json.loads((RUN/'client.json').read_text())

if len(sys.argv) == 1:
    # Portal services can retain inherited output descriptors after the bus
    # exits. Give them a file, so CTest can finish when our runner exits.
    with (RUN/'session.log').open('w') as log:
        code = subprocess.call(['dbus-run-session', '--', sys.executable, __file__, 'inner'],
                               stdout=log, stderr=subprocess.STDOUT)
    if code:
        print((RUN/'session.log').read_text()[-6000:])
    else:
        print('Checks passed:', RUN/'results.json')
    sys.exit(code)

os.environ.update(XDG_CONFIG_HOME=str(RUN/'config'), XDG_CACHE_HOME=str(RUN/'cache'),
                  QT_PLUGIN_PATH=str(BUILD/'plugins'), WECHAT_GLASS_TEST_DIR=str(RUN),
                  XDG_SESSION_TYPE='wayland', WECHAT_GLASS_TEST_FLAT='1',
                  WECHAT_GLASS_TEST_QT_SCALE=str(SCALE))
(RUN/'config').mkdir(exist_ok=True)
(RUN/'config'/'kwinrc').write_text(
    '[Plugins]\n'+EFFECT+'Enabled=true\nkwin4_effect_shapecornersEnabled=false\n'
    'better_blur_dxEnabled=true\nblurEnabled=false\n'
    '[Effect-better-blur-dx]\nBlurStrength=2\nWindowClasses=\n'
    '[Effect-wechat-glass-live]\nEnabled=true\n'
    f'[Xwayland]\nScale={SCALE}\n')
(RUN/'command').write_text('')
for name in ['client.json', 'x11-env.json']:
    (RUN/name).unlink(missing_ok=True)
sock = 'wechat-edge-test-'+str(os.getpid())
log = (RUN/'kwin.log').open('w')
kwin = subprocess.Popen(['kwin_wayland', '--virtual', '--xwayland', '--socket', sock,
                        '--width', '1600', '--height', '1100', '--scale', str(SCALE),
                        '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities',
                        '--exit-with-session', str(ROOT/'launch-corner-client.py')],
                       stdout=log, stderr=subprocess.STDOUT)
try:
    for _ in range(70):
        if kwin.poll() is not None:
            raise RuntimeError('Nested compositor exited')
        if (RUN/'client.json').exists() and EFFECT in dbus('/Effects', 'loadedEffects').splitlines():
            break
        time.sleep(.15)
    else:
        raise RuntimeError('Test client/effect not ready')
    os.environ.update(json.loads((RUN/'x11-env.json').read_text()))
    os.environ.update(WAYLAND_DISPLAY=sock, QT_QPA_PLATFORM='wayland')
    time.sleep(2)
    profiles = []
    for offset in range(5):
        (RUN/'command').write_text(f'move {160+offset} {130+offset}')
        time.sleep(.7)
        s = state()
        path = RUN/f'move-{offset}.png'
        call('spectacle', '-b', '-f', '-n', '-o', str(path))
        im = Image.open(path).convert('RGB')
        ratio = s['dpr']
        x, y = round(s['x']*ratio), round(s['y']*ratio)
        top = [im.getpixel((x+round(350*ratio), y+i)) for i in range(8)]
        left = [im.getpixel((x+i, y+round(350*ratio))) for i in range(8)]
        # On a uniform backdrop the outer edge must not be brighter than the
        # same gray background a few pixels inside the translucent bar.
        excess = max(max(edge[channel]-profile[7][channel]
                         for edge in profile[:3] for channel in range(3))
                     for profile in (top, left))
        profiles.append({'window': s, 'top': top, 'left': left, 'edge_excess': excess})
    results = {'effect': EFFECT, 'output_scale': SCALE, 'profiles': profiles,
               'maximum_edge_excess': max(p['edge_excess'] for p in profiles),
               'no_bright_rim_after_moves': all(p['edge_excess'] <= 3 for p in profiles),
               'renderer': json.loads(dbus('/Effects', 'debug', EFFECT, ''))}
    (RUN/'results.json').write_text(json.dumps(results, indent=2)+'\n')
    print(json.dumps(results, indent=2), flush=True)
    assert results['no_bright_rim_after_moves'], results
finally:
    kwin.terminate()
    try:
        kwin.wait(timeout=10)
    except subprocess.TimeoutExpired:
        kwin.kill()
    log.close()
