pragma ComponentBehavior: Bound

import QtQuick
import org.kde.kirigami as Kirigami

// Share the folder geometry between the tile, its merge preview and the
// incoming icon's landing point. Only the armed preview morphs into a folder.
Item {
    id: root

    required property AppGridStyle style
    required property var entry
    property bool previewFolder: false
    property string incomingAppId: ""
    property bool animate: true
    property bool rightToLeft: false
    property real folderProgress: entry.type === "folder" || previewFolder ? 1 : 0
    readonly property rect firstPreview: style.folderPreviewRect(width, 0, rightToLeft)

    Accessible.ignored: true
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: false

    Behavior on folderProgress {
        enabled: root.animate
        NumberAnimation {
            duration: root.style.tileLiftDuration
            easing.type: Easing.OutCubic
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Math.max(18, width * 0.22)
        color: root.style.folderBackground
        border.width: 1
        border.color: root.style.subtleBorder
        opacity: root.folderProgress
        scale: 0.88 + 0.12 * root.folderProgress
    }

    Kirigami.Icon {
        x: root.firstPreview.x * root.folderProgress
        y: root.firstPreview.y * root.folderProgress
        width: root.width + (root.firstPreview.width - root.width)
            * root.folderProgress
        height: width
        visible: root.entry.type !== "folder"
        source: root.entry.icon || "application-x-executable"
        smooth: true
    }

    Repeater {
        model: root.entry.type === "folder" && root.entry.previewIcons
            ? root.entry.previewIcons.slice(0, 4) : []

        delegate: Kirigami.Icon {
            required property int index
            required property var modelData
            readonly property rect miniature:
                root.style.folderPreviewRect(root.width, index, root.rightToLeft)
            x: miniature.x
            y: miniature.y
            width: miniature.width
            height: miniature.height
            source: modelData
            visible: !root.incomingAppId || !root.entry.apps
                || root.entry.apps[index] !== root.incomingAppId
            smooth: true
        }
    }
}
