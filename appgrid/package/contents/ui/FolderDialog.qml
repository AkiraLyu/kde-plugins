pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

Item {
    id: root

    required property AppGridStyle style
    required property LayoutController controller
    property string folderId: ""
    property string displayFolderId: ""
    property point originPoint: Qt.point(width / 2, height / 2)
    property int layoutDirectionOverride: -1
    property string suppressedAppId: ""
    readonly property bool opened: folderId.length > 0
    readonly property alias grid: folderGrid
    readonly property Item nameEditor: headerLoader.item
        ? headerLoader.item.titleFieldItem : null
    readonly property real revealProgress: panel.revealProgress
    readonly property real scrimOpacity: scrim.opacity
    readonly property real panelOpacity: panel.opacity
    readonly property real panelScale: panel.scale
    readonly property bool transitionActive: opened || scrim.opacity > 0.001
        || panel.revealProgress > 0.001
    property bool nameEditing: false

    signal closeRequested()
    signal nameEditEnded()
    signal itemActivated(int index)

    visible: transitionActive
    enabled: opened
    z: 2000
    Accessible.name: opened
        ? controller.folderName(displayFolderId) : ""
    Accessible.role: Accessible.Dialog
    Accessible.ignored: !opened

    Rectangle {
        id: scrim

        anchors.fill: parent
        color: "#78000000"
        opacity: root.opened ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                // Fade the dimmer in promptly, but keep it coupled to the
                // panel for the entire closing return so the last frames do
                // not flash the undimmed grid behind a still-visible panel.
                duration: root.opened
                    ? root.style.folderScrimDuration
                    : root.style.folderDuration
                easing.type: root.opened ? Easing.OutCubic : Easing.InCubic
            }
        }
    }

    TapHandler {
        onTapped: eventPoint => {
            const point = panel.mapFromItem(root, eventPoint.position);
            if (point.x < 0 || point.y < 0
                    || point.x > panel.width || point.y > panel.height) {
                root.closeRequested();
            }
        }
    }

    DropArea {
        anchors.fill: parent
        keys: ["plasma-appgrid-item"]
        z: 1

        onDropped: drop => {
            const source = drop.source as AppTile;
            if (!source || source.sourceMode !== "folder" || source.sourceFolderId !== root.folderId) {
                return;
            }

            const point = panel.mapFromItem(root, drop.x, drop.y);
            const outsidePanel = point.x < 0 || point.y < 0
                || point.x > panel.width || point.y > panel.height;
            if (outsidePanel) {
                root.controller.removeFromFolder(root.folderId, source.entry.id, -1);
                drop.accept(Qt.MoveAction);
            }
        }
    }

    Rectangle {
        id: panel
        anchors.centerIn: parent
        width: Math.min(720, parent.width - 72)
        height: Math.min(720, parent.height - 96)
        radius: root.style.folderCornerRadius
        color: root.style.folderPanel
        border.width: 1
        border.color: root.style.subtleBorder
        z: 2
        readonly property real collapsedScale: Math.max(0.16, Math.min(
            0.32,
            root.style.iconSize * 1.25 / Math.max(1, Math.min(width, height))))
        property real revealProgress: root.opened ? 1 : 0
        scale: collapsedScale + revealProgress * (1 - collapsedScale)
        // Keep the panel legible through most of the return trip. Previously
        // its opacity was multiplied by the dialog's opacity, producing an
        // unintended quadratic fade at both ends of the transition.
        opacity: Math.min(1, revealProgress * 1.6)
        transformOrigin: Item.Center

        transform: Translate {
            x: (root.originPoint.x - (panel.x + panel.width / 2))
                * (1 - panel.revealProgress)
            y: (root.originPoint.y - (panel.y + panel.height / 2))
                * (1 - panel.revealProgress)
        }

        Behavior on revealProgress {
            NumberAnimation {
                duration: root.style.folderDuration
                easing.type: root.opened ? Easing.OutCubic : Easing.InCubic
                onFinished: {
                    if (!root.opened) {
                        root.displayFolderId = "";
                    }
                }
            }
        }

        Item {
            id: header
            anchors.top: parent.top
            anchors.topMargin: 24
            anchors.left: parent.left
            anchors.leftMargin: 32
            anchors.right: parent.right
            anchors.rightMargin: 24
            height: 52

            // Destroy the editable control while the dialog is closed. Qt's
            // text-field implementation contains internal accessibility
            // children which can otherwise be reparented into the app's
            // AT-SPI tree even when their outer control is ignored.
            Loader {
                id: headerLoader
                anchors.fill: parent
                // Keep the contents alive for the closing zoom, then destroy
                // the text field again for a clean accessibility tree.
                active: root.displayFolderId.length > 0

                sourceComponent: Component {
                    Row {
                        id: headerContent
                        readonly property alias titleFieldItem: titleField

                        width: header.width
                        height: header.height
                        spacing: 12

                        Item { width: closeButton.width; height: 1 }

                        PlasmaComponents.TextField {
                            id: titleField
                            width: headerContent.width
                                - closeButton.width * 2
                                - headerContent.spacing * 2
                            height: 48
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.controller.folderName(
                                root.displayFolderId)
                            color: root.style.foreground
                            font.pointSize: root.style.folderTitlePointSize
                            font.weight: Font.ExtraBold
                            selectByMouse: true
                            activeFocusOnTab: true
                            background: Rectangle {
                                color: titleField.activeFocus
                                    ? root.style.tileHover : "transparent"
                                radius: 14
                                border.width: titleField.activeFocus ? 1 : 0
                                border.color: root.style.focusRing
                            }
                            onEditingFinished: root.controller.renameFolder(
                                root.displayFolderId, text)
                            onActiveFocusChanged:
                                root.nameEditing = activeFocus
                            onAccepted: {
                                root.controller.renameFolder(
                                    root.displayFolderId, text);
                                focus = false;
                                root.nameEditEnded();
                            }
                            Keys.onEscapePressed: event => {
                                root.cancelRename();
                                event.accepted = true;
                            }

                            Accessible.name: i18nc("@label", "Folder name")
                        }

                        QQC2.ToolButton {
                            id: closeButton
                            width: 48
                            height: 48
                            icon.name: "window-close-symbolic"
                            icon.color: root.style.foreground
                            display: QQC2.AbstractButton.IconOnly
                            activeFocusOnTab: true
                            onClicked: root.closeRequested()
                            background: Rectangle {
                                radius: width / 2
                                color: closeButton.hovered
                                    ? root.style.tileHover : "transparent"
                            }

                            Accessible.name: i18nc(
                                "@action:button", "Close folder")
                        }
                    }
                }
            }
        }

        PagedGrid {
            id: folderGrid
            anchors.top: header.bottom
            anchors.topMargin: 12
            anchors.left: parent.left
            anchors.leftMargin: 26
            anchors.right: parent.right
            anchors.rightMargin: 26
            anchors.bottom: folderDots.top
            anchors.bottomMargin: 14
            style: root.style
            controller: root.controller
            sourceMode: "folder"
            folderId: root.displayFolderId
            maximumColumns: 3
            maximumRows: 3
            adaptiveGridModes: false
            activationHandledExternally: true
            layoutDirectionOverride: root.layoutDirectionOverride
            accessibilityEnabled: root.opened
            suppressedAppId: root.suppressedAppId
            onItemActivated: index => root.itemActivated(index)
        }

        PageDots {
            id: folderDots
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 24
            style: root.style
            pageCount: folderGrid.pageCount
            currentPosition: folderGrid.pagePosition
            accessibilityEnabled: root.opened
            onPageRequested: page => folderGrid.goToPage(page, true)
        }

        Column {
            anchors.centerIn: folderGrid
            spacing: 12
            visible: root.opened
                && root.controller.folderCount(root.displayFolderId) === 0

            Kirigami.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 64
                source: "folder-open"
                color: root.style.secondaryForeground
                Accessible.ignored: true
            }

            PlasmaComponents.Label {
                text: i18nc("@info", "This folder is empty")
                color: root.style.secondaryForeground
                Accessible.ignored: !parent.visible
            }
        }
    }

    Connections {
        target: root.controller
        function onFolderRemoved(folderId): void {
            if (folderId === root.folderId) {
                root.closeRequested();
            }
        }
    }

    onFolderIdChanged: {
        // Read the changed value directly. The derived `opened` binding may
        // still hold its previous value while this change handler is running.
        if (folderId.length > 0) {
            displayFolderId = folderId;
            folderGrid.reset();
        } else {
            nameEditing = false;
            if (style.folderDuration <= 0) {
                displayFolderId = "";
            }
        }
    }

    function beginRename(): void {
        const titleField = nameEditor;
        if (!opened || !titleField) {
            return;
        }
        titleField.forceActiveFocus(Qt.ShortcutFocusReason);
        titleField.selectAll();
    }

    function cancelRename(): bool {
        const titleField = nameEditor;
        if (!titleField || !titleField.activeFocus) {
            return false;
        }
        titleField.text = controller.folderName(displayFolderId);
        titleField.focus = false;
        nameEditEnded();
        return true;
    }
}
