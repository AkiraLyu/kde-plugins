# 可调节图标和文本任务管理器

基于 KDE Plasma 官方 Icons-and-Text Task Manager，适用于 **Plasma 6.8**。
界面源自 6.7.5，原生后端复用系统安装的官方任务管理器。
插件 ID：`org.kde.plasma.adjustabletaskmanager`。

## 改动

- **固定图标额外间距**：外观设置中输入 0–256 逻辑像素，默认 12。
  增加的是每个未启动图标的占位长度，图标保持居中；0 恢复官方间距。
  横向、纵向面板均支持，分组弹出列表不增加间距。
- **任务最大宽度**：保留窄／中／宽，新增“自定义”，支持输入 1–4096
  逻辑像素。数值是整个任务按钮的宽度上限；面板拥挤时仍按 KDE 原有规则缩小、分组。
  自定义模式下，短标题的任务会单独收缩到容纳标题、图标和边距所需的宽度，标题改变时自动更新；
  长标题仍受自定义上限约束。“按标题长度缩小任务宽度”默认开启，取消勾选后，空间充足时任务统一使用自定义最大宽度。
  原有三个档位的行为不变。
  与原版一样，此设置用于横向面板，纵向面板的宽度由面板本身决定。
- **固定应用原位打开**：默认的手动排序模式下，固定图标在原排序位置展开成文字任务；
  关闭后恢复图标，不再跳到任务列表末尾。固定列表不变。
  按名称、桌面等排序时仍遵守所选排序规则。
- **Meta+数字键只切换已打开任务**：按任务栏中的顺序为窗口任务编号，跳过尚未打开的固定图标
  和启动中的占位项。已最小化的窗口仍可切换，分组任务沿用原有分组操作；超出任务数量时不执行操作。

其他功能沿用官方实现，包括分组、预览、拖放、右键菜单、音量和媒体控制、活动／桌面过滤。
源码来源和修改范围见 [UPSTREAM.md](UPSTREAM.md)。

## 构建和安装

需要 Plasma Desktop 6.8+（包含官方任务管理器）、Qt 6.11+、KDE Frameworks 6.30+、
CMake、Ninja、C++20 编译器。运行环境为 Plasma Wayland 会话。
在配置了 AkiraLyu/pkgbuilds 的 Arch Linux 上执行：

```bash
paru --sudo run0 -S adjustable-task-manager
```

pacman 将插件和翻译安装到系统目录，不需要用户级 Qt 插件路径设置。

注销后重新登录，或执行下面的命令重新加载面板（桌面和面板会短暂消失，应用窗口继续运行）：

```bash
systemctl --user restart plasma-plasmashell.service
```

然后在面板的“添加小部件”中搜索 **可调节图标和文本任务管理器**。
可以先添加、调整配置和固定应用，确认后移除旧的两个任务管理器。

**Meta+数字键**与官方任务管理器共用快捷键后端。Plasma 6.8 优先选择包含活动任务、
且不按屏幕过滤的任务管理器；没有活动任务时，优先选择不按屏幕过滤的实例。
多个管理器同时满足条件时，选择结果还取决于后端初始化顺序。要始终使用本插件的编号规则，
建议只保留这一个任务管理器，其他面板和底部 Dock 中的任务管理器也会参与选择。
Plasma 6.8 的前后任务切换、任务位置移动快捷键同样使用这个后端。

## 验证和独立预览

```bash
cmake -S adjustable-task-manager -B adjustable-task-manager/build -G Ninja -DBUILD_TESTING=ON
cmake --build adjustable-task-manager/build --parallel 4
ctest --test-dir adjustable-task-manager/build --output-on-failure

QT_PLUGIN_PATH="$PWD/adjustable-task-manager/build/bin${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}" \
    plasmawindowed org.kde.plasma.adjustabletaskmanager
```

以上命令在仓库根目录执行。冒烟测试还需要 Python 3、`dbus-run-session`、`kwin_wayland`
和 KWayland 开发库。测试自动启动隔离的 D-Bus 和无界面的 KWin Wayland 会话，无需 `DISPLAY`。
测试加载真实插件，通过鼠标和键盘事件检查配置页、与官方任务管理器同时加载时的右键菜单、
启动器间距、自适应宽度开关、Meta+数字键跳过启动器、任务切换和重排快捷键，
以及固定图标在测试窗口打开／关闭时保持原位。
测试使用临时配置和自己的窗口，不修改当前桌面。

升级 Plasma／Qt 后建议重新构建，并运行冒烟测试验证官方后端接口。此插件包含原生代码，
不能作为纯 QML `.plasmoid` 包用 `kpackagetool6` 安装。

## 卸载

先从面板移除此小部件，再运行 `run0 pacman -R adjustable-task-manager`。
