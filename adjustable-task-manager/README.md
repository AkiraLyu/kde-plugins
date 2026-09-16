# 可调节图标和文本任务管理器

基于 KDE Plasma **6.7.5** 官方 Icons-and-Text Task Manager 的小幅 fork。
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

需要 Plasma 6.7、Qt 6.10+、KDE Frameworks 6.26+、CMake、Ninja、C++20 编译器。
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

**Meta+数字键**由 Plasma 在主屏各面板中查找任务管理器。
为了避免多个管理器竞争，请让主屏只保留这一个任务管理器；其他面板／底部 Dock 中的
图标任务管理器也会参与选择。此 fork 保留官方快捷键入口，不额外抢占全局快捷键。

## 验证和独立预览

```bash
cmake -S . -B build -G Ninja -DBUILD_TESTING=ON
cmake --build build --parallel 4
ctest --test-dir build --output-on-failure

QT_PLUGIN_PATH="$PWD/build/bin${QT_PLUGIN_PATH:+:$QT_PLUGIN_PATH}" \
    plasmawindowed org.kde.plasma.adjustabletaskmanager
```

冒烟测试需要 X11／XWayland 的 `DISPLAY`，使用临时配置加载真实插件，检查配置页、
与官方任务管理器同时加载时的右键菜单、启动器间距、自适应宽度开关、数字快捷键跳过启动器，
以及中间的固定图标在测试窗口打开／关闭时保持原位。
测试会短暂显示自己的窗口，不修改面板，不启动或关闭用户的应用。

当前基于 Plasma 6.7.5；升级 Plasma／Qt 后建议重新构建。此插件包含原生代码，
不能作为纯 QML `.plasmoid` 包用 `kpackagetool6` 安装。

## 卸载

先从面板移除此小部件，再运行 `run0 pacman -R adjustable-task-manager`。
