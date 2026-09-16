#!/usr/bin/env python3
import os,json,pathlib,subprocess,time,sys
from PIL import Image
ROOT=pathlib.Path(__file__).resolve().parent
BUILD=pathlib.Path(os.environ.get('WECHAT_GLASS_BUILD_DIR',ROOT.parent/'build')).resolve()
EFFECT='wechat-glass-live-v5'
RUN=BUILD/'test-results'/('corner-run-'+EFFECT); RUN.mkdir(parents=True,exist_ok=True)
def call(*args,check=True):return subprocess.run(args,check=check,capture_output=True,text=True,timeout=20).stdout.strip()
def dbus(*args):return call('qdbus6','org.kde.KWin',*args)
def capture(name):
    call('spectacle','-b','-f','-n','-o',str(RUN/(name+'.png')))
    return Image.open(RUN/(name+'.png')).convert('RGB')
def state():return json.loads((RUN/'client.json').read_text())
def prop(w):return call('xprop','-id',hex(w),'_KDE_NET_WM_BLUR_BEHIND_REGION')
if len(sys.argv)==1:
    # Portal services may outlive the private bus. Keep their inherited output
    # off CTest's pipes so completed checks do not wait for those services.
    with (RUN/'session.log').open('w') as log:
        code=subprocess.call(['dbus-run-session','--',sys.executable,__file__,'inner'],
                             stdout=log,stderr=subprocess.STDOUT)
    if code: print((RUN/'session.log').read_text()[-6000:])
    else: print('Checks passed:',RUN/'results.json')
    sys.exit(code)
os.environ.update({'XDG_CONFIG_HOME':str(RUN/'config'),'XDG_CACHE_HOME':str(RUN/'cache'),
 'QT_PLUGIN_PATH':str(BUILD/'plugins'),'WECHAT_GLASS_TEST_DIR':str(RUN),'XDG_SESSION_TYPE':'wayland'})
(RUN/'config').mkdir(exist_ok=True)
(RUN/'config'/'kwinrc').write_text('[Plugins]\n'+EFFECT+'Enabled=true\nkwin4_effect_shapecornersEnabled=false\nbetter_blur_dxEnabled=true\nblurEnabled=false\n[Effect-better-blur-dx]\nBlurStrength=2\nWindowClasses=\n[Effect-wechat-glass-live]\nEnabled=true\n')
(RUN/'command').write_text('')
for name in ['client.json','x11-env.json']:(RUN/name).unlink(missing_ok=True)
sock='wechat-corner-test-'+str(os.getpid())
log=(RUN/'kwin.log').open('w')
kwin=subprocess.Popen(['kwin_wayland','--virtual','--xwayland','--socket',sock,'--width','1200','--height','900','--scale','1',
 '--no-lockscreen','--no-global-shortcuts','--no-kactivities','--exit-with-session',str(ROOT/'launch-corner-client.py')],stdout=log,stderr=subprocess.STDOUT)
try:
    for _ in range(60):
        if kwin.poll() is not None:raise RuntimeError('Nested KWin exited')
        if (RUN/'client.json').exists() and EFFECT in dbus('/Effects','loadedEffects').splitlines():break
        time.sleep(.15)
    else:raise RuntimeError('Test client/effect not ready')
    os.environ.update(json.loads((RUN/'x11-env.json').read_text()))
    os.environ.update({'WAYLAND_DISPLAY':sock,'QT_QPA_PLATFORM':'wayland'})
    time.sleep(2)
    s=state();a=capture('main')
    time.sleep(.6);b=capture('updated')
    main_region=prop(s['main'])
    checks={'main_has_explicit_blur': 'CARDINAL' in main_region,
            'live_content_updates': a.crop((510,230,710,430)).tobytes()!=b.crop((510,230,710,430)).tobytes()}
    for name,point in [('top_left',(s['x']+3,s['y']+3)),('bottom_left',(s['x']+3,s['y']+s['height']-4))]:
        x,y=point;expected=(40,60,180) if (x//8+y//8)%2 else (230,210,80)
        checks[name+'_outside_corner_unmodified']=a.getpixel(point)==expected
    (RUN/'command').write_text('popup');time.sleep(.7)
    s=state();popup=capture('popup')
    checks['popup_has_no_blur_property']='not found' in prop(s['popup'])
    point=(s['popup_x']+2,s['popup_y']+50)
    checks['popup_transparent_margin_unchanged']=popup.getpixel(point)==b.getpixel(point)
    (RUN/'command').write_text('resize');time.sleep(.7)
    resized=prop(state()['main'])
    checks['blur_region_updates_on_resize']=resized!=main_region
    (RUN/'command').write_text('');time.sleep(.7)
    dbus('/Effects','unloadEffect',EFFECT)
    checks['disable_removes_owned_blur_property']='not found' in prop(state()['main'])
    dbus('/Effects','loadEffect',EFFECT);time.sleep(.6)
    checks['reload_reinstates_blur_property']='CARDINAL' in prop(state()['main'])
    results={'checks':checks,'renderer':json.loads(dbus('/Effects','debug',EFFECT,'')),'window':state()}
    (RUN/'results.json').write_text(json.dumps(results,indent=2)+'\n')
    print(json.dumps(results,indent=2),flush=True)
    assert all(checks.values()),checks
finally:
    kwin.terminate()
    try:kwin.wait(timeout=10)
    except subprocess.TimeoutExpired:kwin.kill()
    log.close()
