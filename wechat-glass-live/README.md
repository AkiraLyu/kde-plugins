# 微信局部透明

KWin 原生特效，为 XWayland 微信主窗口的顶栏和最左侧图标栏添加透明模糊，保留聊天正文、图标以及弹窗。当前原生代码为 0.5.0，插件标识 `wechat-glass-live-v5`，配置组为 `Effect-wechat-glass-live`。

## 构建与安装

在仓库根目录执行：

```bash
paru --sudo run0 -S kde-config
kde-config
```

配方位于 AkiraLyu/pkgbuilds 的 `wechat-glass-live/PKGBUILD`，从 GitHub 拉取源码构建；`wechat-glass-control` 管理当前用户的启停和参数。

本机的 Flatpak 微信为 `com.tencent.WeChat`。新机器需先安装微信；安装入口会执行以下用户级 override，保证窗口使用本插件支持的 XWayland 后端：

```bash
flatpak override --user --nosocket=wayland --socket=x11 --env=QT_QPA_PLATFORM=xcb com.tencent.WeChat
```

从托盘完全退出微信后重新打开才能切换后端。仅关闭主窗口通常只是隐藏窗口。

## 参数和维护

```bash
wechat-glass-control status
wechat-glass-control enable
wechat-glass-control disable
wechat-glass-control opacity 0.52
```

需要启用 Better Blur DX。不要把 `wechat` 加入 Better Blur DX 的全局强制模糊列表：本插件自己设置主窗口两条栏的模糊区域，强制整窗模糊会影响弹窗阴影和圆角。

| 配置项 | 默认值 | 含义 |
| --- | --- | --- |
| BackgroundOpacity | 0.52 | 栏背景不透明度，范围 0.1–1.0 |
| NavigationWidth | 60.8 | 最左侧图标栏宽度，逻辑像素 |
| TitleHeight | 32.8 | 顶栏高度，逻辑像素 |
| MatchTolerance | 0.025 | 识别背景色的容差 |
| CornerRadius | 16 | KWin 未提供圆角尺寸时使用的半径 |

需要保存日常调整时同步修改 `kde-config/kwinrc`，下一次复现会以该文件为准。

KWin 插件接口与 KWin 版本绑定，更新后执行 `paru --sudo run0 --rebuild -S wechat-glass-live` 重编译并重新登录。Qt 会缓存已经加载的库，同一会话中覆盖文件不等于换用了新代码。安装包可通过 `run0 pacman -R wechat-glass-live` 卸载。

关闭动画期间，透明处理与模糊区域保留到 `windowDeleted`，由 KDE 的动画决定窗口何时释放。隐藏到托盘后快速重新打开时，新窗口接管同一 X 窗口的模糊属性，避免旧动画结束时清掉新窗口的效果。

## 原生代码检查

隔离回归工具保存在 `tests/`，启动独立 D-Bus / 虚拟 KWin，检查实时刷新、圆角、弹窗和缩放边缘。`test-closing.py` 使用 KDE 的 Scale 动画逐帧比较顶栏和图标栏的透明度，并检查关闭、隐藏、销毁、快速重开和停用后的属性清理。

```bash
cd wechat-glass-live
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DWECHAT_GLASS_BUILD_TESTS=ON
cmake --build build --parallel 2
ctest --test-dir build --output-on-failure
```

测试额外需要 Spectacle、XWayland、xprop 和 Python Pillow；结果位于 `build/test-results/`。`docs/verification-*.json` 记录各自标注版本和环境下的验证结果。

许可证：GPL-2.0-or-later，见 `LICENSE`。
