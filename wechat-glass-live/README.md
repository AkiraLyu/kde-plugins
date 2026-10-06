# 微信局部透明

KWin 原生特效，为微信主窗口的顶栏和最左侧图标栏添加透明模糊，保留聊天正文、图标以及弹窗。当前原生代码为 0.6.1，插件标识 `wechat-glass-live-v5`，配置组为 `Effect-wechat-glass-live`。

## 后端

插件同时支持 XWayland 和 Wayland 原生窗口，两条栏的透明都由插件着色器生成，模糊来源随后端不同：

| 后端 | 模糊来源 | 模糊范围 |
| --- | --- | --- |
| XWayland | 插件写入窗口属性 `_KDE_NET_WM_BLUR_BEHIND_REGION` | 只有两条栏 |
| Wayland 原生 | Better Blur DX 的强制模糊 | 整个窗口；着色器只让两条栏透明，因此可见的模糊仍限于两条栏 |

Wayland 下应用无法由合成器代为请求模糊区域，只能由窗口自己通过 `ext-background-effect-v1` 请求，所以插件改用 Better Blur DX 按窗口类强制模糊。该强制模糊对自带模糊区域的窗口不生效，因此在 XWayland 下不会与插件的属性冲突。

## 构建与安装

在仓库根目录执行：

```bash
paru --sudo run0 -S kde-config
kde-config
```

配方位于 AkiraLyu/pkgbuilds 的 `wechat-glass-live/PKGBUILD`，从 GitHub 拉取源码构建；`wechat-glass-control` 管理当前用户的启停和参数。

`kde-config` 会把 Better Blur DX 的 `WindowClasses` 写入 `wechat`，Wayland 原生微信据此获得背景模糊。窗口类在 Wayland 下取自应用的 desktop file name，在 XWayland 下取自 WM_CLASS；Flatpak 微信的对应值是 `com.tencent.WeChat`。

## 后端选择

AUR 的 `wechat` 包由 portable 沙箱启动微信。微信自带 Qt 6.6 的平台插件顺序是 `wayland;xcb`，只要沙箱里能看到 Wayland socket 就以 Wayland 原生运行。要改回 XWayland，给沙箱补一个环境变量：

```bash
# ~/.local/share/WeChat_Data/portable.env
QT_QPA_PLATFORM=xcb
```

`portable.env` 是 portable 20 唯一生效的环境变量入口；包内 `/usr/lib/portable/info/com.tencent.wechat/config` 的旧式环境变量段会被忽略。改动后从托盘完全退出微信再重新打开，仅关闭主窗口通常只是隐藏窗口。

Flatpak 微信（`com.tencent.WeChat`）由 `kde-config` 写入用户级 override，固定在 XWayland 后端：

```bash
flatpak override --user --nosocket=wayland --socket=x11 --env=QT_QPA_PLATFORM=xcb com.tencent.WeChat
```

## 参数和维护

```bash
wechat-glass-control status
wechat-glass-control enable
wechat-glass-control disable
wechat-glass-control opacity 0.52
```

需要启用 Better Blur DX。Wayland 窗口的模糊由它的强制模糊列表提供，`CornerRadius` 需要与窗口圆角一致（本机 Shape Corners 为 16），否则窗口圆角外会露出方形模糊。运行中改 kwinrc 后，Better Blur DX 不一定会重读该列表，逐特效 `reconfigureEffect` 也不一定让已经打开的窗口拿到模糊，重新加载效果才可靠：

```bash
qdbus6 org.kde.KWin /Effects unloadEffect better_blur_dx
qdbus6 org.kde.KWin /Effects loadEffect better_blur_dx
```

`wechat-glass-control enable` 已包含这一步。

| 配置项 | 默认值 | 含义 |
| --- | --- | --- |
| BackgroundOpacity | 0.52 | 栏背景不透明度，范围 0.1–1.0 |
| NavigationWidth | 60.8 | 最左侧图标栏宽度，逻辑像素 |
| TitleHeight | 32.8 | 顶栏高度，逻辑像素 |
| MatchTolerance | 0.025 | 识别背景色的容差 |
| CornerRadius | 16 | KWin 未提供圆角尺寸时使用的半径 |

需要保存日常调整时同步修改 `kde-config/kwinrc`，下一次复现会以该文件为准。KWin 不会为 Wayland 窗口提供 X11 属性，因此 `wechat-glass-control status` 中的 `windows_with_blur_region` 在 Wayland 下始终为 0，`wayland_windows` 表示插件接管的 Wayland 主窗口数。

KWin 插件接口与 KWin 版本绑定，更新后执行 `paru --sudo run0 --rebuild -S wechat-glass-live` 重编译并重新登录。Qt 会缓存已经加载的库，同一会话中覆盖文件不等于换用了新代码。安装包可通过 `run0 pacman -R wechat-glass-live` 卸载。

关闭动画期间，透明处理与模糊区域保留到 `windowDeleted`，由 KDE 的动画决定窗口何时释放。隐藏到托盘后快速重新打开时，新窗口接管同一 X 窗口的模糊属性，避免旧动画结束时清掉新窗口的效果。

## 原生代码检查

隔离回归工具保存在 `tests/`，启动独立 D-Bus / 虚拟 KWin，检查实时刷新、圆角、弹窗和缩放边缘。`test-closing.py` 使用 KDE 的 Scale 动画逐帧比较顶栏和图标栏的透明度，并检查关闭、隐藏、销毁、快速重开和停用后的属性清理。`test-wayland.py` 让测试客户端以 Wayland 原生方式运行，检查窗口被接管、两条栏变透明、正文和桌面不受影响、弹窗不被接管，以及停用后两条栏恢复不透明。

```bash
cd wechat-glass-live
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DWECHAT_GLASS_BUILD_TESTS=ON
cmake --build build --parallel 2
ctest --test-dir build --output-on-failure
```

测试额外需要 Spectacle、XWayland、xprop 和 Python Pillow，Wayland 用例不需要 XWayland；截图和逐项结果位于 `build/test-results/`。

许可证：GPL-2.0-or-later，见 `LICENSE`。
