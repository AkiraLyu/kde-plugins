# Upstream

This is a fork of KDE Plasma Desktop's Icons-and-Text Task Manager:

- Repository: https://invent.kde.org/plasma/plasma-desktop
- Tag: `v6.7.5`
- Commit: `43f55fff3480c6eb5f60133f045bfc74b9c67d84`
- Source directory: `applets/taskmanager`, copied to `applet/`.
- Supporting files: `kcms/recentFiles/kactivitymanagerd_plugins_settings.kcfg*`, copied to `config/`.
- Original copyright notices and applicable GPL/LGPL texts are retained.

Behavior changes are confined to `qml/main.qml`, `qml/Task.qml`,
`qml/code/LayoutMetrics.js`, `qml/ConfigAppearance.qml`, and `main.xml`:

1. Enable the existing `TasksModel.launchInPlace` behavior for manual sorting.
2. Add extra launcher cell space along the panel, excluding popup delegates.
3. Add a custom maximum task width alongside the three original presets.
   In custom mode, each task's width also respects the natural width of its title,
   with room for its icon, margins, and audio control. This title fitting can be
   disabled in Appearance settings and defaults to enabled.
4. Number only existing window tasks for Meta+number shortcuts, skipping launchers
   and startup placeholders while keeping the upstream window/group activation behavior.

The C++ implementations retain the upstream logic. The fork's native backend
and smart launcher types use the `AdjustableTaskManager` namespace to avoid Qt
metatype collisions with the stock plugin, which otherwise break context menus
when the stock plugin loads after this fork.
The fork has its own plugin ID and QML module URI. Unchanged QML
messages explicitly use the installed upstream translation domain; new messages
use this fork's catalog. No system KDE files are patched.

The top-level CMake project builds only this applet and an optional integration
smoke test. Plasma still provides `org.kde.taskmanager` and the other runtime
QML modules. Recheck these private APIs when updating the Plasma base version.
