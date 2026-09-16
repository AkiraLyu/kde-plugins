pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import org.kde.kirigami as Kirigami
import org.kde.plasma.plasmoid
import org.kde.plasma.private.kicker as Kicker

Item {
    id: root

    required property Component windowComponent
    readonly property Kicker.DashboardWindow dashboardWindow:
        windowComponent.status === Component.Ready
            ? windowComponent.createObject(root, {visualParent: root}) as Kicker.DashboardWindow
            : null

    Layout.minimumWidth: Kirigami.Units.iconSizes.small
    Layout.minimumHeight: Kirigami.Units.iconSizes.small
    Layout.maximumWidth: Kirigami.Units.iconSizes.huge
    Layout.maximumHeight: Kirigami.Units.iconSizes.huge

    AppGridGlyph {
        anchors.centerIn: parent
        slotExtent: Math.min(root.width, root.height)
        active: hoverHandler.hovered
    }

    HoverHandler { id: hoverHandler }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (root.dashboardWindow) {
                root.dashboardWindow.toggle();
            }
        }
    }

    Keys.onReturnPressed: Plasmoid.activated()
    Keys.onEnterPressed: Plasmoid.activated()
    Keys.onSpacePressed: Plasmoid.activated()

    Accessible.name: Plasmoid.title
    Accessible.description: i18nc("@info:tooltip", "Open the full-screen application grid")
    Accessible.role: Accessible.Button
    Accessible.onPressAction: {
        if (dashboardWindow) {
            dashboardWindow.toggle();
        }
    }

    Connections {
        target: Plasmoid
        function onActivated(): void {
            if (root.dashboardWindow) {
                root.dashboardWindow.toggle();
            }
        }
    }

    Component.onDestruction: {
        if (dashboardWindow) {
            dashboardWindow.destroy();
        }
    }
}
