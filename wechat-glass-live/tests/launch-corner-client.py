#!/usr/bin/env python3
import os,json,pathlib
root=pathlib.Path(__file__).resolve().parent
build=pathlib.Path(os.environ.get('WECHAT_GLASS_BUILD_DIR',root.parent/'build')).resolve()
run=pathlib.Path(os.environ['WECHAT_GLASS_TEST_DIR'])
(run/'x11-env.json').write_text(json.dumps({k:os.environ[k] for k in ['DISPLAY','XAUTHORITY'] if k in os.environ}))
os.environ['QT_QPA_PLATFORM']='xcb'
os.environ['QT_QPA_PLATFORMTHEME']='generic'
if 'WECHAT_GLASS_TEST_QT_SCALE' in os.environ:
    os.environ['QT_SCALE_FACTOR']=os.environ['WECHAT_GLASS_TEST_QT_SCALE']
os.execv(str(build/'tests/wechat-glass-test-client'),[str(build/'tests/wechat-glass-test-client'),'-name','wechat'])
