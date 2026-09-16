pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2

import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents

FocusScope {
    id: root

    required property AppGridStyle style
    property string text: ""
    property string placeholderText: ""
    readonly property Item inputItem: fieldLoader.item
    property int layoutDirectionOverride: -1
    property bool accessibilityEnabled: true
    readonly property bool rightToLeft: layoutDirectionOverride >= 0
        ? layoutDirectionOverride === Qt.RightToLeft
        : Application.layoutDirection === Qt.RightToLeft

    signal escapePressed()
    signal navigationPressed(int key, int modifiers)
    signal activationPressed()
    signal contextMenuPressed()
    signal renamePressed()

    Keys.onPressed: event => root.handleKeyEvent(event)

    onAccessibilityEnabledChanged: Qt.callLater(() => {
        if (root.accessibilityEnabled) {
            root.takeFocus(Qt.OtherFocusReason);
        }
    })

    implicitWidth: style.searchWidth
    implicitHeight: 48

    LayoutMirroring.enabled: rightToLeft
    LayoutMirroring.childrenInherit: true
    Accessible.ignored: !accessibilityEnabled

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.style.searchBackground
        border.color: fieldLoader.item && fieldLoader.item.activeFocus
            ? root.style.focusRing : root.style.searchBorder
        border.width: fieldLoader.item && fieldLoader.item.activeFocus ? 2 : 1

        Behavior on border.color {
            ColorAnimation { duration: root.style.tileFeedbackDuration }
        }
    }

    Kirigami.Icon {
        id: searchIcon
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 22
        source: "search"
        color: root.style.searchSecondaryForeground
    }

    Loader {
        id: fieldLoader
        anchors.fill: parent
        active: root.accessibilityEnabled

        sourceComponent: Component {
            PlasmaComponents.TextField {
                id: field
                objectName: "appGridSearchField"
                text: root.text
                placeholderText: root.placeholderText
                leftPadding: root.rightToLeft
                    ? (clearButton.visible ? clearButton.width + 24 : 18)
                    : searchIcon.x + searchIcon.width + 12
                rightPadding: root.rightToLeft
                    ? root.width - searchIcon.x + 12
                    : (clearButton.visible ? clearButton.width + 24 : 18)
                verticalAlignment: TextInput.AlignVCenter
                color: root.style.searchForeground
                placeholderTextColor: root.style.searchSecondaryForeground
                font.pointSize: root.style.searchFontPointSize
                focus: true
                activeFocusOnTab: true
                selectByMouse: true
                background: Item {}

                Accessible.name: placeholderText

                onTextEdited: root.text = text
                Keys.onPressed: event => root.handleKeyEvent(event)

                Connections {
                    target: root
                    function onTextChanged(): void {
                        if (field.text !== root.text) {
                            field.text = root.text;
                        }
                    }
                }
            }
        }
    }

    QQC2.ToolButton {
        id: clearButton
        anchors.right: parent.right
        anchors.rightMargin: 7
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 34
        visible: root.text.length > 0
        enabled: root.accessibilityEnabled
        activeFocusOnTab: root.accessibilityEnabled
        icon.name: "edit-clear-symbolic"
        icon.color: root.style.searchForeground
        display: QQC2.AbstractButton.IconOnly
        background: Rectangle {
            radius: width / 2
            color: clearButton.hovered
                ? root.style.searchButtonHover : "transparent"
        }
        onClicked: {
            root.clear();
            root.takeFocus(Qt.MouseFocusReason);
        }

        Accessible.name: i18nc("@action:button", "Clear search")
        Accessible.ignored: !root.accessibilityEnabled || !visible
    }

    function clear(): void {
        root.text = "";
    }

    function takeFocus(reason): void {
        const field = inputItem;
        if (field) {
            field.forceActiveFocus(reason ?? Qt.OtherFocusReason);
        }
    }

    function handleKeyEvent(event): void {
        switch (event.key) {
        case Qt.Key_Escape:
            root.escapePressed();
            event.accepted = true;
            break;
        case Qt.Key_Down:
        case Qt.Key_Up:
        case Qt.Key_PageDown:
        case Qt.Key_PageUp:
            root.navigationPressed(event.key, event.modifiers);
            event.accepted = true;
            break;
        case Qt.Key_Home:
        case Qt.Key_End:
            if (root.text.length === 0
                    || (event.modifiers & Qt.ControlModifier)) {
                root.navigationPressed(event.key, event.modifiers);
                event.accepted = true;
            } else {
                // Preserve normal text-editing Home/End behavior while a
                // query is present. Ctrl+Home/End remains grid navigation.
                event.accepted = false;
            }
            break;
        case Qt.Key_Left:
        case Qt.Key_Right:
            // Like GNOME's overview, an unmodified horizontal arrow navigates
            // the visible results even though the search field retains focus
            // so further typing can continue. Ctrl/Shift keep their standard
            // text-editing and selection behavior; Alt remains an explicit
            // grid-navigation modifier for compatibility.
            const textEditingModifiers = event.modifiers
                & (Qt.ControlModifier | Qt.ShiftModifier);
            if (root.text.length === 0
                    || !textEditingModifiers
                    || (event.modifiers & Qt.AltModifier)) {
                root.navigationPressed(event.key, event.modifiers);
                event.accepted = true;
            } else {
                event.accepted = false;
            }
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            root.activationPressed();
            event.accepted = true;
            break;
        case Qt.Key_Menu:
            root.contextMenuPressed();
            event.accepted = true;
            break;
        case Qt.Key_F2:
            root.renamePressed();
            event.accepted = true;
            break;
        case Qt.Key_F10:
            if (event.modifiers & Qt.ShiftModifier) {
                root.contextMenuPressed();
                event.accepted = true;
            } else {
                event.accepted = false;
            }
            break;
        default:
            event.accepted = false;
        }
    }
}
