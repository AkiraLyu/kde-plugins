#!/usr/bin/env python3
"""Measure bar transparency throughout KDE's real close animation."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from PIL import Image

ROOT = Path(__file__).resolve().parent
BUILD = Path(os.environ.get('WECHAT_GLASS_BUILD_DIR', ROOT.parent / 'build')).resolve()
EFFECT = 'wechat-glass-live-v5'
RUN = BUILD / 'test-results' / ('closing-run-' + EFFECT)
RUN.mkdir(parents=True, exist_ok=True)


def call(*args):
    return subprocess.check_output(args, text=True, stderr=subprocess.PIPE, timeout=20).strip()


def dbus(*args):
    return call('qdbus6', 'org.kde.KWin', *args)


def renderer():
    return json.loads(dbus('/Effects', 'debug', EFFECT, ''))


def state():
    return json.loads((RUN / 'client.json').read_text())


def wait_until(condition, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if kwin.poll() is not None:
            raise RuntimeError('Test compositor exited')
        try:
            if condition():
                return
        except (FileNotFoundError, subprocess.CalledProcessError):
            pass
        time.sleep(.05)
    raise RuntimeError('Timed out waiting for the test window/effect')


def command(action):
    (RUN / 'command').write_text(action)
    wait_until(lambda: state()['action'] == action)


def capture(name):
    path = RUN / (name + '.png')
    call('spectacle', '-b', '-f', '-n', '-o', str(path))
    return Image.open(path).convert('RGB')


def blur_property(window):
    return call('xprop', '-id', hex(window), '_KDE_NET_WM_BLUR_BEHIND_REGION')


if len(sys.argv) == 1:
    with (RUN / 'session.log').open('w') as log:
        code = subprocess.call(['dbus-run-session', '--', sys.executable, __file__, 'inner'],
                               stdout=log, stderr=subprocess.STDOUT)
    print((RUN / 'session.log').read_text()[-7000:] if code else f'Checks passed: {RUN / "results.json"}')
    sys.exit(code)

os.environ.update(XDG_CONFIG_HOME=str(RUN / 'config'), XDG_CACHE_HOME=str(RUN / 'cache'),
                  QT_PLUGIN_PATH=str(BUILD / 'plugins'), WECHAT_GLASS_TEST_DIR=str(RUN),
                  XDG_SESSION_TYPE='wayland', WECHAT_GLASS_TEST_FLAT='1',
                  WECHAT_GLASS_TEST_FAST_COMMANDS='1', WECHAT_GLASS_TEST_QT_SCALE='1')
(RUN / 'config').mkdir(exist_ok=True)
# Use KDE's actual scale effect, slowing it down for frame measurements.
# Closing keeps its default 0.8 scale; opening uses 1 to simplify readiness.
(RUN / 'config' / 'kwinrc').write_text(
    f'[Plugins]\n{EFFECT}Enabled=true\nkwin4_effect_shapecornersEnabled=false\n'
    'better_blur_dxEnabled=true\nblurEnabled=false\nscaleEnabled=true\n'
    '[Effect-scale]\nDuration=2000\nInScale=1\nOutScale=0.8\n'
    '[Effect-better-blur-dx]\nBlurStrength=2\nWindowClasses=\n'
    '[Effect-wechat-glass-live]\nEnabled=true\n')
(RUN / 'command').write_text('')
for name in ['client.json', 'x11-env.json']:
    (RUN / name).unlink(missing_ok=True)
sock = 'wechat-close-test-' + str(os.getpid())
log = (RUN / 'kwin.log').open('w')
kwin = subprocess.Popen([
    'kwin_wayland', '--virtual', '--xwayland', '--socket', sock,
    '--width', '1200', '--height', '900', '--scale', '1',
    '--no-lockscreen', '--no-global-shortcuts', '--no-kactivities',
    '--exit-with-session', str(ROOT / 'launch-corner-client.py'),
], stdout=log, stderr=subprocess.STDOUT)
checks = {}
samples = {}
try:
    wait_until(lambda: (RUN / 'client.json').exists()
               and EFFECT in dbus('/Effects', 'loadedEffects').splitlines())
    os.environ.update(json.loads((RUN / 'x11-env.json').read_text()))
    os.environ.update(WAYLAND_DISPLAY=sock, QT_QPA_PLATFORM='wayland')
    time.sleep(2.5)
    backdrop = (24, 40, 56)
    points = {'title': (700, 145), 'navigation': (190, 580)}
    reference = capture('visible')
    reference_bars = {name: reference.getpixel(point) for name, point in points.items()}
    checks['visible_bars_are_transparent'] = all(max(pixel) < 170 for pixel in reference_bars.values())

    for action in ('close', 'hide', 'destroy'):
        if action != 'close':
            command('show')
            time.sleep(2.3)
        started = time.monotonic()
        command(action)
        frames = []
        for index in range(4):
            screenshot = capture(f'{action}-{index}')
            body = screenshot.getpixel((850, 650))
            opacity = sum((body[c] - backdrop[c]) / (250 - backdrop[c]) for c in range(3)) / 3
            # Undo only the common close-animation opacity. Removing Glass
            # makes the normalized bar jump from ~130 to 224, even while fading.
            if opacity > .15:
                # KDE animates scale and opacity with the same curve. Track
                # each bar's pixel as the window shrinks around its center.
                scale = .8 + .2 * opacity
                transformed = {name: (round(600 + (x - 600) * scale), round(450 + (y - 450) * scale))
                               for name, (x, y) in points.items()}
                excess = max(
                    backdrop[c] + (screenshot.getpixel(point)[c] - backdrop[c]) / opacity
                    - reference_bars[name][c]
                    for name, point in transformed.items() for c in range(3))
                frames.append({'opacity': opacity, 'bar_brightness_excess': round(excess, 2)})
            time.sleep(.15)
        samples[action] = frames
        checks[action + '_animation_was_sampled'] = len(frames) >= 3 and frames[0]['opacity'] - frames[-1]['opacity'] > .02
        checks[action + '_keeps_bar_transparency'] = len(frames) >= 3 and all(f['bar_brightness_excess'] <= 7 for f in frames)
        time.sleep(max(0, 2.2 - (time.monotonic() - started)))
        wait_until(lambda: renderer()['redirected_windows'] == 0)
        checks[action + '_releases_effect_resources'] = renderer()['windows_with_blur_region'] == 0
        # QWidget.close() may destroy the native X window. hide() keeps it.
        if action == 'hide':
            checks[action + '_restores_hidden_window_property'] = 'not found' in blur_property(state()['main'])

    # Reopen the same X window before its predecessor's animation finishes.
    command('show')
    time.sleep(2.3)
    window = state()['main']
    command('hide')
    command('show')
    checks['rapid_reopen_reuses_x_window'] = state()['main'] == window
    time.sleep(2.4)
    checks['rapid_reopen_keeps_new_blur_region'] = 'CARDINAL' in blur_property(window)
    checks['rapid_reopen_has_one_redirected_window'] = renderer()['redirected_windows'] == 1
    dbus('/Effects', 'unloadEffect', EFFECT)
    checks['disable_after_reopen_restores_original_property'] = 'not found' in blur_property(window)
    dbus('/Effects', 'loadEffect', EFFECT)
    dbus('/Effects', 'unloadEffect', 'scale')
    command('close')
    wait_until(lambda: renderer()['redirected_windows'] == 0)
    checks['close_without_animation_releases_resources'] = renderer()['windows_with_blur_region'] == 0
    results = {'checks': checks, 'samples': samples}
    (RUN / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(json.dumps(results, indent=2), flush=True)
    assert all(checks.values()), checks
finally:
    kwin.terminate()
    try:
        kwin.wait(timeout=10)
    except subprocess.TimeoutExpired:
        kwin.kill()
        kwin.wait()
    log.close()
