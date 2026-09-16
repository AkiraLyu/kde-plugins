pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

import org.kde.plasma.appgrid.effects 1.0 as AppGridEffects
import org.kde.plasma.private.kicker as Kicker

Kicker.DashboardWindow {
    id: root

    required property LayoutController controller
    required property AppGridStyle style

    backgroundColor: "transparent"
    keyEventProxy: view.keyEventProxy
    title: i18nc("@title:window", "Applications")
    readonly property string outputName: view.Screen.name
    readonly property bool backgroundBlurActive: backgroundEffect.active
    readonly property bool usingStandardBackgroundEffect:
        backgroundEffect.usingStandardProtocol
    property bool dismissing: false

    property AppGridEffects.BackgroundEffect backgroundEffect:
        AppGridEffects.BackgroundEffect {
            window: root
            // A fully opaque veil cannot show the compositor result, so avoid
            // paying for blur until transparency makes it visible.
            enabled: root.style.backgroundBlurEnabled
                && root.style.normalizedBackgroundOpacity < 1
        }

    mainItem: AppGridView {
        id: view
        anchors.fill: parent
        controller: root.controller
        style: root.style
        onCloseRequested: root.dismissAnimated()
        onExitFinished: {
            if (root.dismissing) {
                root.hide();
            }
        }
    }

    onKeyEscapePressed: view.handleEscape()

    onActiveChanged: {
        if (!active && visible && !dismissing) {
            hide();
        }
    }

    onVisibleChanged: {
        view.reset();
        if (visible) {
            dismissing = false;
            view.playEntrance();
        } else {
            dismissing = false;
            view.cancelTransitions();
        }
    }

    property Connections controllerConnections: Connections {
        target: root.controller
        function onApplicationLaunched(): void {
            root.dismissAnimated();
        }
        function onInteractionConcluded(): void {
            root.dismissAnimated();
        }
    }

    function dismissAnimated(): void {
        if (!visible || dismissing) {
            return;
        }
        dismissing = true;
        view.playExit();
    }
}
