pragma ComponentBehavior: Bound

import QtQuick

import org.kde.kirigami as Kirigami

Item {
    id: root

    required property real slotExtent
    property bool active: false

    readonly property real targetExtent: Math.max(0, Math.min(
        slotExtent,
        Kirigami.Units.iconSizes.medium,
        Math.max(
            Math.min(slotExtent, Kirigami.Units.iconSizes.small),
            Math.round(slotExtent * 0.8))))
    readonly property real dotExtent: targetExtent > 0
        ? Math.max(2, Math.round(targetExtent * 0.18))
        : 0
    readonly property real dotSpacing: targetExtent > 0
        ? Math.max(0, (targetExtent - dotExtent * 3) / 2)
        : 0

    width: targetExtent
    height: targetExtent

    Grid {
        anchors.centerIn: parent
        columns: 3
        rows: 3
        spacing: root.dotSpacing

        Repeater {
            model: 9

            delegate: Rectangle {
                required property int index

                width: root.dotExtent
                height: root.dotExtent
                radius: Math.max(1, width * 0.22)
                color: root.active
                    ? Kirigami.Theme.highlightColor
                    : Kirigami.Theme.textColor
                antialiasing: true
            }
        }
    }
}
