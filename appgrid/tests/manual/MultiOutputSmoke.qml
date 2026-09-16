import QtQuick
import QtQuick.Controls as QQC2

import "../../package/contents/ui"

QQC2.ApplicationWindow {
    id: panelWindow

    width: 64
    height: 64
    visible: true
    title: "App Grid multi-output smoke panel"

    property var dashboardWindow: null
    property string removedScreenName: ""
    property bool readyAnnounced: false
    property int reportedScreenCount: -1
    property bool mismatchReported: false
    property bool removalMismatchReported: false

    AppGridStyle {
        id: appGridStyle
    }

    LayoutController {
        id: layoutController

        enableKRunnerSearch: false
        runningTrackingEnabled: false
    }

    Item {
        id: visualParent

        anchors.fill: parent
    }

    Component {
        id: dashboardComponent

        AppGridWindow {
            controller: layoutController
            style: appGridStyle
        }
    }

    Timer {
        id: timeoutTimer

        interval: 15000
        onTriggered: {
            console.error("APPGRID_MULTI_OUTPUT_TIMEOUT");
            Qt.exit(2);
        }
    }

    Timer {
        id: pollTimer

        interval: 50
        repeat: true
        onTriggered: panelWindow.checkState()
    }

    function sameGeometry(window, screen): bool {
        if (!window || !screen) {
            return false;
        }
        return window.x === screen.virtualX && window.y === screen.virtualY
            && window.width === screen.width
            && window.height === screen.height;
    }

    function checkState(): void {
        const screens = Qt.application.screens;
        if (reportedScreenCount !== screens.length) {
            reportedScreenCount = screens.length;
            const names = [];
            for (let index = 0; index < screens.length; ++index) {
                names.push(screens[index].name);
            }
            console.info(`APPGRID_MULTI_OUTPUT_SCREENS ${names.join(",")}`);
        }
        if (!readyAnnounced) {
            if (screens.length < 2) {
                return;
            }
            if (!dashboardWindow) {
                dashboardWindow = dashboardComponent.createObject(
                    visualParent, {visualParent});
                if (!dashboardWindow) {
                    console.error("APPGRID_MULTI_OUTPUT_CREATE_FAILED");
                    Qt.exit(3);
                    return;
                }
                dashboardWindow.showFullScreen();
                return;
            }
            if (dashboardWindow.outputName === screen.name
                    && dashboardWindow.usingStandardBackgroundEffect
                    && sameGeometry(dashboardWindow, screen)) {
                removedScreenName = screen.name;
                readyAnnounced = true;
                console.info(`APPGRID_MULTI_OUTPUT_READY ${removedScreenName}`);
            } else if (!mismatchReported) {
                mismatchReported = true;
                console.info(
                    `APPGRID_MULTI_OUTPUT_WAIT panel=${screen.name} dashboard=${dashboardWindow.outputName} standardEffect=${dashboardWindow.usingStandardBackgroundEffect} blurActive=${dashboardWindow.backgroundBlurActive} geometry=${dashboardWindow.x},${dashboardWindow.y},${dashboardWindow.width}x${dashboardWindow.height} expected=${screen.virtualX},${screen.virtualY},${screen.width}x${screen.height}`);
            }
            return;
        }

        if (screens.length !== 1 || screen.name !== screens[0].name
                || dashboardWindow.outputName !== screens[0].name
                || !dashboardWindow.usingStandardBackgroundEffect
                || !sameGeometry(dashboardWindow, screens[0])) {
            if (screens.length === 1 && !removalMismatchReported) {
                removalMismatchReported = true;
                console.info(
                    `APPGRID_MULTI_OUTPUT_REMOVAL_WAIT panel=${screen.name} remaining=${screens[0].name} dashboard=${dashboardWindow.outputName} standardEffect=${dashboardWindow.usingStandardBackgroundEffect} blurActive=${dashboardWindow.backgroundBlurActive} geometry=${dashboardWindow.x},${dashboardWindow.y},${dashboardWindow.width}x${dashboardWindow.height} expected=${screens[0].virtualX},${screens[0].virtualY},${screens[0].width}x${screens[0].height}`);
            }
            return;
        }
        console.info(
            `APPGRID_MULTI_OUTPUT_PASSED ${removedScreenName} -> ${screen.name}`);
        pollTimer.stop();
        timeoutTimer.stop();
        Qt.callLater(() => Qt.exit(0));
    }

    Component.onCompleted: {
        timeoutTimer.start();
        pollTimer.start();
    }

    Component.onDestruction: {
        if (dashboardWindow) {
            dashboardWindow.destroy();
        }
    }
}
