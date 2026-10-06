#!/usr/bin/env python3
import os,pathlib
root=pathlib.Path(__file__).resolve().parent
build=pathlib.Path(os.environ.get('WECHAT_GLASS_BUILD_DIR',root.parent/'build')).resolve()
# Wayland identifies the window through the desktop file name the client sets.
os.environ['QT_QPA_PLATFORM']='wayland'
os.environ['QT_QPA_PLATFORMTHEME']='generic'
os.execv(str(build/'tests/wechat-glass-test-client'),[str(build/'tests/wechat-glass-test-client'),'-name','wechat'])
