import QtQuick

import org.kde.kirigami as Kirigami

QtObject {
    id: root

    property bool darkMode: true
    property bool backgroundBlurEnabled: true
    property bool useCustomBackgroundColor: false
    property color customBackgroundColor: "#1d2028"
    property int backgroundOpacity: 85
    property int requestedIconSize: 96
    property color systemTextColor: Kirigami.Theme.textColor
    property color systemDisabledTextColor: Kirigami.Theme.disabledTextColor
    property color systemBackgroundColor: Kirigami.Theme.backgroundColor
    property color systemHighlightColor: Kirigami.Theme.highlightColor

    // Accessibility: when false every non-essential animation is disabled.
    property bool animationsEnabled: true

    // Kirigami duration units already track KDE's global animation-speed
    // setting and become zero when animations are disabled. 200 ms is the
    // documented/default Kirigami long duration, so this preserves GNOME's
    // base timings at normal speed while following the KDE preference.
    readonly property real systemDurationScale: {
        const duration = Number(Kirigami.Units.longDuration);
        return isFinite(duration) ? Math.max(0, duration) / 200 : 1;
    }

    readonly property int iconSize: Math.max(64, Math.min(112, requestedIconSize))
    readonly property int tileWidth: iconSize + 56
    // GNOME Shell caps the extra row/column spacing at six base units,
    // currently 36 logical pixels.
    readonly property int maximumGridSpacing: 36
    // GNOME Shell uses 3 × its 8 px base radius for overview tiles and
    // 4 × its 16 px modal radius for the expanded folder surface.
    readonly property int cornerRadius: 24
    readonly property int folderCornerRadius: 64
    readonly property real systemFontPointSize: {
        const size = Number(Kirigami.Theme.defaultFont.pointSize);
        return isFinite(size) && size > 0 ? size : 10;
    }
    readonly property real applicationLabelPointSize: Math.max(
        10, systemFontPointSize)
    property var applicationLabelMetrics: FontMetrics {
        font.pointSize: root.applicationLabelPointSize
    }
    readonly property int applicationLabelHeight: Math.ceil(
        applicationLabelMetrics.lineSpacing * 2)
    readonly property int tileTopPadding: 8
    readonly property int tileIconLabelSpacing: 5
    readonly property int tileBottomPadding: 7
    readonly property int tileTextReserve: tileTopPadding
        + tileIconLabelSpacing + applicationLabelHeight + tileBottomPadding
    // The preferred height encloses two text lines and leaves four logical
    // pixels between their box and the three-pixel-inset selection frame.
    // Keep the former compact footprint for adaptive row selection; if a
    // screen is constrained, AppTile shrinks the icon rather than allowing
    // its label to escape the frame.
    readonly property int tileHeight: iconSize + tileTextReserve
    readonly property int minimumTileHeight: iconSize + 48
    readonly property real searchFontPointSize: Math.max(
        11, systemFontPointSize)
    // GNOME's search entry is 24 em wide. At Qt's 96-DPI logical baseline,
    // one point is 4/3 px, hence 24 × 4/3 = 32.
    readonly property int searchWidth: Math.round(searchFontPointSize * 32)
    readonly property real folderTitlePointSize: Math.max(
        18, systemFontPointSize)

    readonly property int pageDuration: _duration(300)
    // A partially dragged page should only animate the distance that remains.
    // Keep a short floor so a snap still reads as motion instead of a jump.
    readonly property int pageSnapMinimumDuration: _duration(90)
    readonly property int folderDuration: _duration(200)
    readonly property int folderScrimDuration: _duration(160)
    readonly property int entranceDuration: _duration(210)
    readonly property int entranceScaleDuration: _duration(260)
    readonly property int exitDuration: _duration(250)
    readonly property real overviewInitialScale: 0.96
    readonly property real overviewExitScale: 0.96
    // A short acknowledgement runs before the application is triggered. This
    // keeps a newly mapped window from cutting the feedback off mid-frame.
    readonly property int appLaunchDuration: _duration(140)
    readonly property real appLaunchScale: 1.85
    readonly property int tileMoveDuration: _duration(240)
    // Gap previews are frequently retargeted while the pointer crosses cells,
    // so they settle a little faster than a cancelled tile returning home.
    readonly property int dragShiftDuration: _duration(190)
    readonly property int dragSettleDuration: _duration(260)
    readonly property int dragMergeDuration: _duration(280)
    readonly property int tileLiftDuration: _duration(160)
    readonly property real tileLiftScale: 1.10
    readonly property int tileFeedbackDuration: _duration(120)
    readonly property int tilePressDuration: _duration(80)
    readonly property int tileReleaseDuration: _duration(150)
    readonly property int hintDuration: _duration(100)

    // Interaction safeguards intentionally do not follow animation speed:
    // disabling motion must not also make an accidental drag or folder merge
    // easier to trigger. Respect KDE's start distance, then add a small buffer
    // for hand tremor and high-density touchpads.
    readonly property int pointerDragThreshold: Math.max(14, Math.round(
        Math.max(Qt.styleHints.startDragDistance * 1.35,
            Kirigami.Units.gridUnit * 0.85)))
    readonly property int touchDragThreshold: Math.max(4, Math.round(
        pointerDragThreshold * 0.35))
    readonly property int dragMergeDelay: 320
    // Adding to an existing folder is visually unambiguous and reversible,
    // so it should not inherit the longer new-folder confirmation delay.
    readonly property int dragExistingFolderMergeDelay: 180
    readonly property real dragMergeMoveTolerance: Math.max(9, iconSize * 0.11)
    readonly property int dragReorderDelay: 160
    readonly property int dragHoverExitDelay: 100
    readonly property int dragEdgeDelay: 500

    function folderPreviewRect(size, index, rightToLeft = false): rect {
        const miniature = Math.floor(size * 0.4);
        const spacing = Math.max(4, size * 0.07);
        const inset = (size - miniature * 2 - spacing) / 2;
        const column = rightToLeft ? 1 - (index % 2) : index % 2;
        return Qt.rect(inset + column * (miniature + spacing),
            inset + Math.floor(index / 2) * (miniature + spacing),
            miniature, miniature);
    }

    function _duration(baseMilliseconds): int {
        if (!animationsEnabled) {
            return 0;
        }
        return Math.round(baseMilliseconds * systemDurationScale);
    }

    function pageTransitionDuration(distanceInPages): int {
        const distance = Math.max(0, Math.min(
            1, Math.abs(Number(distanceInPages))));
        if (distance <= 0 || pageDuration <= 0) {
            return 0;
        }
        // Square-root scaling keeps short corrections crisp without making a
        // mostly complete transition look like an instantaneous cut.
        return Math.min(pageDuration, Math.max(
            pageSnapMinimumDuration,
            Math.round(pageDuration * Math.sqrt(distance))));
    }

    readonly property color backgroundBaseColor: useCustomBackgroundColor
        ? customBackgroundColor
        : (darkMode ? "#1d2028" : systemBackgroundColor)
    readonly property bool customBackgroundIsDark:
        // At this luminance pure black and white have equal WCAG contrast;
        // choosing either side guarantees at least 4.5:1 for app labels.
        _relativeLuminance(backgroundBaseColor) < 0.179
    readonly property color foreground: useCustomBackgroundColor
        ? (customBackgroundIsDark ? "#ffffff" : "#000000")
        : (darkMode ? "#f7f7f8" : systemTextColor)
    readonly property color secondaryForeground: useCustomBackgroundColor
        ? (customBackgroundIsDark ? "#e0e0e0" : "#333333")
        : (darkMode ? "#b9bbc1" : systemDisabledTextColor)
    readonly property real normalizedBackgroundOpacity: Math.max(
        0, Math.min(100, backgroundOpacity)) / 100
    readonly property color backdrop: _alpha(
        backgroundBaseColor, normalizedBackgroundOpacity)
    readonly property color tileHover: darkMode
        ? "#26ffffff" : _alpha(systemHighlightColor, 0.18)
    readonly property color tilePressed: darkMode
        ? "#3dffffff" : _alpha(systemHighlightColor, 0.28)
    readonly property color folderBackground: useCustomBackgroundColor
        ? _alpha(backgroundBaseColor, customBackgroundIsDark ? 0.42 : 0.30)
        : (darkMode ? "#3bffffff" : _alpha(systemHighlightColor, 0.16))
    readonly property real folderPanelSurfaceOpacity: 0.88
    readonly property color folderPanel: useCustomBackgroundColor
        ? _alpha(backgroundBaseColor, folderPanelSurfaceOpacity)
        : _alpha(darkMode ? "#2a2d36" : systemBackgroundColor,
            folderPanelSurfaceOpacity)
    readonly property color searchBackground: darkMode
        ? "#f2ffffff" : systemBackgroundColor
    readonly property color searchForeground: darkMode
        ? "#25262b" : systemTextColor
    readonly property color searchSecondaryForeground: darkMode
        ? "#696b73" : systemDisabledTextColor
    readonly property color searchBorder: darkMode
        ? "#18000000" : _alpha(systemTextColor, 0.28)
    readonly property color searchButtonHover: darkMode
        ? "#16000000" : _alpha(systemHighlightColor, 0.18)
    readonly property color focusRing: systemHighlightColor
    readonly property color subtleBorder: darkMode
        ? "#30ffffff" : _alpha(systemTextColor, 0.28)
    readonly property color edgeGlow: darkMode
        ? "#22ffffff" : _alpha(systemHighlightColor, 0.22)

    function _alpha(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }

    function _linearColorChannel(channel) {
        return channel <= 0.04045
            ? channel / 12.92
            : Math.pow((channel + 0.055) / 1.055, 2.4);
    }

    function _relativeLuminance(color) {
        return 0.2126 * _linearColorChannel(color.r)
            + 0.7152 * _linearColorChannel(color.g)
            + 0.0722 * _linearColorChannel(color.b);
    }
}
