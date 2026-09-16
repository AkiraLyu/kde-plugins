pragma ComponentBehavior: Bound

import QtQuick

Row {
    id: root

    required property AppGridStyle style
    property int pageCount: 1
    property real currentPosition: 0
    property int maximumVisibleIndicators: 9
    property bool accessibilityEnabled: true
    readonly property int visibleIndicatorCount: Math.min(
        Math.max(1, pageCount), Math.max(3, maximumVisibleIndicators))
    readonly property int firstVisiblePage: Math.max(0, Math.min(
        pageCount - visibleIndicatorCount,
        Math.round(currentPosition) - Math.floor(visibleIndicatorCount / 2)))
    signal pageRequested(int page)

    visible: pageCount > 1
    spacing: 10

    Repeater {
        model: Math.max(3, root.maximumVisibleIndicators)

        delegate: Rectangle {
            id: dot
            required property int index
            readonly property int pageIndex: root.firstVisiblePage + index
            readonly property bool hasHiddenPagesBefore:
                index === 0 && pageIndex > 0
            readonly property bool hasHiddenPagesAfter:
                index === root.visibleIndicatorCount - 1
                    && pageIndex < root.pageCount - 1
            readonly property real activeWeight: Math.max(0, 1 - Math.abs(
                pageIndex - root.currentPosition))

            visible: index < root.visibleIndicatorCount
            width: 10
            height: 10
            radius: 5
            color: root.style.foreground
            border.width: activeFocus ? 2 : 0
            border.color: root.style.focusRing
            // pagePosition already follows the page's animated/scrubbed
            // contentX. Interpolate directly so indicators stay phase-locked
            // to a touchpad gesture instead of chasing it through a second,
            // independent 400 ms animation.
            opacity: 0.32 + 0.68 * activeWeight
            scale: (0.78 + 0.22 * activeWeight)
                * (hasHiddenPagesBefore || hasHiddenPagesAfter ? 0.68 : 1)
            activeFocusOnTab: root.accessibilityEnabled && visible

            Accessible.ignored: !root.accessibilityEnabled || !root.visible || !visible
            Accessible.name: i18nc(
                "@action:button",
                "Page %1 of %2", dot.pageIndex + 1, root.pageCount)
            Accessible.role: Accessible.Button
            Accessible.onPressAction: dot.activate()

            TapHandler {
                enabled: root.enabled && dot.visible
                onTapped: dot.activate()
            }

            Keys.onReturnPressed: dot.activate()
            Keys.onEnterPressed: dot.activate()
            Keys.onSpacePressed: dot.activate()

            function activate(): void {
                if (root.enabled && visible && index < root.visibleIndicatorCount) {
                    root.pageRequested(dot.pageIndex);
                }
            }
        }
    }
}
