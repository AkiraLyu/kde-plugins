pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.plasmoid

KCMUtils.SimpleKCM {
    id: root

    property alias cfg_iconSize: iconSize.value
    property alias cfg_forceDarkMode: forceDarkMode.checked
    property alias cfg_enableBackgroundBlur: enableBackgroundBlur.checked
    property alias cfg_useCustomBackgroundColor: useCustomBackgroundColor.checked
    property alias cfg_backgroundColor: backgroundColor.color
    property alias cfg_backgroundOpacity: backgroundOpacity.value
    property alias cfg_showDescriptionsInSearch: showDescriptions.checked
    property alias cfg_enableKRunnerSearch: enableKRunnerSearch.checked
    property alias cfg_rememberApplicationUsage: rememberApplicationUsage.checked
    property string cfg_launchHistoryData: Plasmoid.configuration.launchHistoryData
    property alias cfg_reduceAnimations: reduceAnimations.checked
    property string cfg_layoutData: Plasmoid.configuration.layoutData

    Kirigami.FormLayout {
        anchors.left: parent.left
        anchors.right: parent.right

        QQC2.SpinBox {
            id: iconSize

            Kirigami.FormData.label: i18nc("@label", "Icon size:")
            from: 64
            to: 112
            stepSize: 8
            editable: true
            textFromValue: value => i18nc("@item:valuesuffix", "%1 px", value)
            valueFromText: text => {
                const parsed = parseInt(text, 10);
                if (isNaN(parsed)) {
                    return value;
                }
                return Math.max(iconSize.from, Math.min(iconSize.to,
                    Math.round(parsed / iconSize.stepSize)
                        * iconSize.stepSize));
            }

            Accessible.name: Kirigami.FormData.label
        }

        QQC2.CheckBox {
            id: forceDarkMode

            Kirigami.FormData.label: i18nc("@title:group", "Appearance:")
            text: i18nc("@option:check", "Use the GNOME-style dark interface")
        }

        QQC2.CheckBox {
            id: enableBackgroundBlur

            text: i18nc("@option:check", "Blur the wallpaper behind the grid")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: enableBackgroundBlur.checked
            type: Kirigami.MessageType.Information
            text: i18nc(
                "@info",
                "Blur follows the Plasma theme and the Blur effect in KDE System Settings.")
        }

        QQC2.CheckBox {
            id: useCustomBackgroundColor

            text: i18nc("@option:check", "Use a custom background color")
        }

        KQuickControls.ColorButton {
            id: backgroundColor

            Kirigami.FormData.label: i18nc("@label", "Background color:")
            enabled: useCustomBackgroundColor.checked
            showAlphaChannel: false
            dialogTitle: i18nc("@title:window", "Select App Grid Background Color")
        }

        QQC2.SpinBox {
            id: backgroundOpacity

            Kirigami.FormData.label: i18nc("@label", "Background opacity:")
            from: 0
            to: 100
            stepSize: 1
            editable: true
            textFromValue: value => i18nc("@item:valuesuffix", "%1%", value)
            valueFromText: text => {
                const parsed = parseInt(text, 10);
                return isNaN(parsed)
                    ? value
                    : Math.max(backgroundOpacity.from,
                        Math.min(backgroundOpacity.to, parsed));
            }

            Accessible.name: Kirigami.FormData.label
        }

        QQC2.CheckBox {
            id: reduceAnimations

            text: i18nc("@option:check", "Reduce motion")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showDescriptions

            Kirigami.FormData.label: i18nc("@title:group", "Search:")
            text: i18nc("@option:check", "Match application descriptions")
        }

        QQC2.CheckBox {
            id: enableKRunnerSearch

            text: i18nc(
                "@option:check",
                "Include System Settings, calculator, unit conversions, and session actions")
        }

        Kirigami.InlineMessage {
            Layout.fillWidth: true
            visible: enableKRunnerSearch.checked
            type: Kirigami.MessageType.Information
            text: i18nc(
                "@info",
                "Additional results use your enabled KRunner plugins and their privacy settings.")
        }

        QQC2.CheckBox {
            id: rememberApplicationUsage

            text: i18nc("@option:check", "Prioritize frequently and recently opened apps")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: i18nc("@info", "Learns from apps opened through App Grid. History stays on this device.")
        }

        QQC2.Button {
            text: i18nc("@action:button", "Clear app launch history")
            icon.name: "edit-clear-history"
            enabled: root.cfg_launchHistoryData.length > 0
            onClicked: root.cfg_launchHistoryData = ""
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.Button {
            Kirigami.FormData.label: i18nc("@title:group", "Layout:")
            text: i18nc("@action:button", "Reset app order and folders…")
            icon.name: "edit-undo"
            onClicked: resetLayoutDialog.open()
        }
    }

    QQC2.Dialog {
        id: resetLayoutDialog

        anchors.centerIn: parent
        modal: true
        title: i18nc("@title:window", "Reset App Grid Layout?")
        standardButtons: QQC2.Dialog.Ok | QQC2.Dialog.Cancel

        contentItem: QQC2.Label {
            text: i18nc(
                "@info",
                "This removes all folders and custom ordering. Installed applications will return in KDE's current application order.")
            wrapMode: Text.Wrap
        }

        onAccepted: root.cfg_layoutData = '{"version":1,"items":[]}'
    }
}
