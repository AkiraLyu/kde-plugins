import QtQuick
import QtQuick.Window
import QtTest

import org.kde.plasma.appgrid.effects 1.0

TestCase {
    id: testCase

    name: "BackgroundEffect"

    Window {
        id: testWindow

        width: 320
        height: 200
    }

    BackgroundEffect {
        id: effect

        window: testWindow
        enabled: false
    }

    function test_nonWaylandBackendRemainsSafeWhenDisabled() {
        compare(effect.enabled, false);
        compare(effect.active, false);
        compare(effect.usingStandardProtocol, false);
    }

    function test_windowCanBeDetachedAndReattached() {
        effect.window = null;
        compare(effect.window, null);
        compare(effect.active, false);

        effect.window = testWindow;
        compare(effect.window, testWindow);
    }
}
