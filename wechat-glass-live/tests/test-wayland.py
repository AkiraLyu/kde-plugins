#!/usr/bin/env python3
"""Wayland backend regression test.

Runs a nested KWin with a Wayland-native client that announces WeChat's app id
and checks the effect's behaviour on that backend: the two bars must become
translucent, the window body and the desktop behind it must stay untouched, the
client's own popup must not be taken over, and unloading the effect must restore
the opaque bars.
"""
import json, os, pathlib, subprocess, sys, time
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent
BUILD = pathlib.Path(os.environ.get('WECHAT_GLASS_BUILD_DIR', ROOT.parent / 'build')).resolve()
EFFECT = 'wechat-glass-live-v5'
BAR = (224, 224, 224)      # the client's own bar colour
BODY = (250, 250, 250)
RUN = BUILD / 'test-results' / ('wayland-run-' + EFFECT)
RUN.mkdir(parents=True, exist_ok=True)


def call(*args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True, timeout=20).stdout.strip()


def dbus(*args):
    return call('qdbus6', 'org.kde.KWin', *args)


def capture(name):
    call('spectacle', '-b', '-f', '-n', '-o', str(RUN / (name + '.png')))
    return Image.open(RUN / (name + '.png')).convert('RGB')


def near(pixel, colour, tolerance=6):
    return all(abs(a - b) <= tolerance for a, b in zip(pixel, colour))


def body_box(image):
    """Bounding box of the client's body colour, i.e. the window without bars."""
    xs, ys = [], []
    for y in range(0, image.height, 2):
        for x in range(0, image.width, 2):
            if near(image.getpixel((x, y)), BODY, 2):
                xs.append(x)
                ys.append(y)
    if not xs:
        raise RuntimeError('Test client window not found in screenshot')
    return min(xs), min(ys), max(xs), max(ys)


def sample_points(image):
    left, top, right, bottom = body_box(image)
    # The client draws the body inset by the navigation width and title height.
    x, y = left - 61, top - 33
    width = right - left
    return {
        'title': (x + width // 2, y + 16),
        'nav': (x + 30, y + 200),
        # Stay clear of the client's animated square and frame counter.
        'body': (x + width - 40, y + 200),
        'desktop': (x - 20, y + 200),
    }


def state():
    return json.loads((RUN / 'client.json').read_text())


if len(sys.argv) == 1:
    # Portal services may outlive the private bus. Keep their inherited output
    # off CTest's pipes so completed checks do not wait for those services.
    with (RUN / 'session.log').open('w') as log:
        code = subprocess.call(['dbus-run-session', '--', sys.executable, __file__, 'inner'],
                               stdout=log, stderr=subprocess.STDOUT)
    if code:
        print((RUN / 'session.log').read_text()[-6000:])
    else:
        print('Checks passed:', RUN / 'results.json')
    sys.exit(code)

os.environ.update({'XDG_CONFIG_HOME': str(RUN / 'config'), 'XDG_CACHE_HOME': str(RUN / 'cache'),
                   'QT_PLUGIN_PATH': str(BUILD / 'plugins'), 'WECHAT_GLASS_TEST_DIR': str(RUN),
                   'XDG_SESSION_TYPE': 'wayland'})
(RUN / 'config').mkdir(exist_ok=True)
(RUN / 'cache').mkdir(exist_ok=True)
(RUN / 'config' / 'kwinrc').write_text(
    '[Plugins]\n' + EFFECT + 'Enabled=true\nkwin4_effect_shapecornersEnabled=false\n'
    'better_blur_dxEnabled=true\nblurEnabled=false\n'
    '[Effect-better-blur-dx]\nBlurStrength=2\nWindowClasses=\n'
    '[Effect-wechat-glass-live]\nEnabled=true\n')
(RUN / 'command').write_text('')
for name in ('client.json', 'results.json'):
    (RUN / name).unlink(missing_ok=True)

sock = 'wechat-wayland-test-' + str(os.getpid())
log = (RUN / 'kwin.log').open('w')
kwin = subprocess.Popen(
    ['kwin_wayland', '--virtual', '--socket', sock, '--width', '1200', '--height', '900',
     '--scale', '1', '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities',
     '--exit-with-session', str(ROOT / 'launch-wayland-client.py')],
    stdout=log, stderr=subprocess.STDOUT)
try:
    for _ in range(60):
        if kwin.poll() is not None:
            raise RuntimeError('Nested KWin exited')
        if (RUN / 'client.json').exists() and EFFECT in dbus('/Effects', 'loadedEffects').splitlines():
            break
        time.sleep(0.15)
    else:
        raise RuntimeError('Test client/effect not ready')
    os.environ['WAYLAND_DISPLAY'] = sock
    time.sleep(2.5)

    engine = json.loads(dbus('/Effects', 'debug', EFFECT, ''))
    shot = capture('main')
    points = sample_points(shot)
    pixels = {name: shot.getpixel(point) for name, point in points.items()}
    checks = {
        'wayland_window_matched': engine['wayland_windows'] == 1 and engine['x11_windows'] == 0,
        'single_window_redirected': engine['redirected_windows'] == 1,
        'title_bar_translucent': not near(pixels['title'], BAR),
        'navigation_bar_translucent': not near(pixels['nav'], BAR),
        'body_unchanged': near(pixels['body'], BODY),
        'desktop_unchanged': not near(pixels['desktop'], BAR) and not near(pixels['desktop'], BODY),
    }

    (RUN / 'command').write_text('popup')
    time.sleep(0.7)
    engine = json.loads(dbus('/Effects', 'debug', EFFECT, ''))
    checks['popup_not_redirected'] = engine['redirected_windows'] == 1

    dbus('/Effects', 'unloadEffect', EFFECT)
    time.sleep(0.7)
    restored = capture('unloaded')
    restored_pixels = {name: restored.getpixel(point) for name, point in points.items()}
    checks['bars_opaque_without_effect'] = near(restored_pixels['title'], BAR) and near(restored_pixels['nav'], BAR)
    checks['body_still_unchanged'] = near(restored_pixels['body'], BODY)

    results = {'checks': checks, 'pixels': {k: list(v) for k, v in pixels.items()},
               'restored_pixels': {k: list(v) for k, v in restored_pixels.items()},
               'points': {k: list(v) for k, v in points.items()},
               'renderer': engine, 'window': state()}
    (RUN / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2), flush=True)
    assert all(checks.values()), checks
finally:
    kwin.terminate()
    try:
        kwin.wait(timeout=10)
    except subprocess.TimeoutExpired:
        kwin.kill()
    log.close()
