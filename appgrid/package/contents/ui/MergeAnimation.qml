import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: root

    required property AppGridStyle style
    property string appId: ""
    property var iconSource: "application-x-executable"
    property rect destination: Qt.rect(0, 0, 0, 0)
    property bool fadeIntoFolder: false
    readonly property bool running: flight.running

    visible: appId.length > 0
    z: 3000
    Accessible.ignored: true

    function start(entry, origin, target, fade): void {
        stop();
        if (style.dragMergeDuration <= 0) {
            return;
        }
        iconSource = entry.icon || "application-x-executable";
        destination = target;
        fadeIntoFolder = fade;
        x = origin.x;
        y = origin.y;
        width = origin.width;
        height = origin.height;
        opacity = 1;
        appId = entry.id;
        flight.start();
    }

    function stop(): void {
        flight.stop();
        appId = "";
    }

    Kirigami.Icon {
        anchors.fill: parent
        source: root.iconSource
        smooth: true
    }

    ParallelAnimation {
        id: flight
        onFinished: root.appId = ""
        NumberAnimation {
            target: root
            property: "x"
            to: root.destination.x
            duration: root.style.dragMergeDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "y"
            to: root.destination.y
            duration: root.style.dragMergeDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            properties: "width,height"
            to: root.destination.width
            duration: root.style.dragMergeDuration
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "opacity"
            to: root.fadeIntoFolder ? 0 : 1
            duration: root.style.dragMergeDuration
            easing.type: Easing.InCubic
        }
    }
}
