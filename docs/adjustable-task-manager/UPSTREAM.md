# Upstream

The QML interface is derived from KDE Plasma Desktop's Icons-and-Text Task Manager:

- Repository: https://invent.kde.org/plasma/plasma-desktop
- Tag: `v6.7.5`
- Commit: `43f55fff3480c6eb5f60133f045bfc74b9c67d84`
- Source directory: `applets/taskmanager`, copied to `adjustable-task-manager/applet/`.
- Original copyright notices and applicable GPL/LGPL texts are retained.

Custom behavior is implemented in `qml/main.qml`, `qml/Task.qml`,
`qml/code/LayoutMetrics.js`, `qml/ConfigAppearance.qml`, and `main.xml`:

1. Enable the existing `TasksModel.launchInPlace` behavior for manual sorting.
2. Add extra launcher cell space along the panel, excluding popup delegates.
3. Add a custom maximum task width alongside the three original presets.
   In custom mode, each task's width also respects the natural width of its title,
   with room for its icon, margins, and audio control. This title fitting can be
   disabled in Appearance settings and defaults to enabled.
4. Number only existing window tasks for Meta+number shortcuts, skipping launchers
   and startup placeholders while keeping the upstream window/group activation behavior.

Plasma 6.8 is the minimum supported runtime. The applet loads the installed
`org.kde.plasma.taskmanager` plugin through `KPluginFactory` before loading its
QML. It uses that plugin's `Backend` and `SmartLauncherItem` types for context
menus, application badges, progress, audio process lookup, and global shortcuts.
These native implementations and their configuration schemas are not copied.
Sharing the backend keeps one shortcut dispatcher and one set of native QML
types when the stock and adjustable task managers run in the same process.

The Plasma 6.8 integration follows `applets/taskmanager` at tag `v6.8.0`:
`main.qml` handles the backend's shortcut signals, including task cycling and
reordering. Number shortcuts retain the custom window-only indexing rule.
`ToolTipInstance.qml` uses PipeWire previews and an application-icon fallback;
it does not reference the removed X11 `WindowThumbnail` type.

The fork has its own plugin ID and QML module URI. Unchanged QML
messages explicitly use the installed upstream translation domain; new messages
use this fork's catalog. No system KDE files are patched.

The component's CMake project builds the applet and an optional integration
smoke test. Plasma provides `org.kde.taskmanager`, the stock applet backend, and
the other runtime QML modules. Recheck these private APIs when upgrading Plasma.
