import QtQuick
import QtTest

import "../package/contents/ui"

TestCase {
    id: testCase

    name: "AppGridStyle"

    AppGridStyle {
        id: highContrastStyle

        darkMode: false
        systemTextColor: "#ffffff"
        systemDisabledTextColor: "#ffffff"
        systemBackgroundColor: "#000000"
        systemHighlightColor: "#ffff00"
    }

    AppGridStyle {
        id: darkStyle
    }

    AppGridStyle {
        id: customStyle

        useCustomBackgroundColor: true
        customBackgroundColor: "#336699"
        backgroundOpacity: 40
    }

    AppGridStyle {
        id: lightCustomStyle

        useCustomBackgroundColor: true
        customBackgroundColor: "#f5e8c8"
    }

    function linearChannel(channel): real {
        return channel <= 0.04045
            ? channel / 12.92
            : Math.pow((channel + 0.055) / 1.055, 2.4);
    }

    function luminance(color): real {
        return 0.2126 * linearChannel(color.r)
            + 0.7152 * linearChannel(color.g)
            + 0.0722 * linearChannel(color.b);
    }

    function contrast(left, right): real {
        const lighter = Math.max(luminance(left), luminance(right));
        const darker = Math.min(luminance(left), luminance(right));
        return (lighter + 0.05) / (darker + 0.05);
    }

    function composite(foreground, background): color {
        const alpha = foreground.a + background.a * (1 - foreground.a);
        if (alpha <= 0) {
            return "transparent";
        }
        return Qt.rgba(
            (foreground.r * foreground.a
                + background.r * background.a * (1 - foreground.a)) / alpha,
            (foreground.g * foreground.a
                + background.g * background.a * (1 - foreground.a)) / alpha,
            (foreground.b * foreground.a
                + background.b * background.a * (1 - foreground.a)) / alpha,
            alpha);
    }

    function test_darkPaletteHasReadablePrimaryAndSecondaryText() {
        const surface = Qt.rgba(0x1d / 255, 0x20 / 255, 0x28 / 255, 1);
        verify(contrast(darkStyle.foreground, surface) >= 7);
        verify(contrast(darkStyle.secondaryForeground, surface) >= 7);
        verify(contrast(darkStyle.searchForeground,
            darkStyle.searchBackground) >= 7);
        verify(contrast(darkStyle.searchSecondaryForeground,
            darkStyle.searchBackground) >= 4.5);
    }

    function test_systemPaletteIsUsedWithoutForcedDarkMode() {
        compare(highContrastStyle.foreground, "#ffffff");
        compare(highContrastStyle.secondaryForeground, "#ffffff");
        compare(highContrastStyle.folderPanel.r, 0);
        compare(highContrastStyle.folderPanel.g, 0);
        compare(highContrastStyle.folderPanel.b, 0);
        compare(highContrastStyle.folderPanel.a,
            highContrastStyle.folderPanelSurfaceOpacity);
        compare(highContrastStyle.searchBackground, "#000000");
        compare(highContrastStyle.searchForeground, "#ffffff");
        compare(highContrastStyle.focusRing, "#ffff00");
    }

    function test_pageTransitionDurationTracksRemainingDistance() {
        compare(darkStyle.pageTransitionDuration(0), 0);
        compare(darkStyle.pageTransitionDuration(1), darkStyle.pageDuration);
        compare(darkStyle.pageTransitionDuration(4), darkStyle.pageDuration);

        const partialDuration = darkStyle.pageTransitionDuration(0.25);
        verify(partialDuration >= darkStyle.pageSnapMinimumDuration);
        verify(partialDuration < darkStyle.pageDuration);

        darkStyle.animationsEnabled = false;
        try {
            compare(darkStyle.pageTransitionDuration(1), 0);
        } finally {
            darkStyle.animationsEnabled = true;
        }
    }

    function test_dragSafeguardsDoNotDisappearWithAnimations() {
        verify(darkStyle.pointerDragThreshold
            > Qt.styleHints.startDragDistance);
        verify(darkStyle.touchDragThreshold > 0);
        verify(darkStyle.touchDragThreshold
            < darkStyle.pointerDragThreshold);
        const mergeDelay = darkStyle.dragMergeDelay;
        const existingFolderDelay = darkStyle.dragExistingFolderMergeDelay;
        const reorderDelay = darkStyle.dragReorderDelay;
        verify(reorderDelay >= 140 && reorderDelay < mergeDelay);
        verify(existingFolderDelay < mergeDelay);

        darkStyle.animationsEnabled = false;
        try {
            compare(darkStyle.dragShiftDuration, 0);
            compare(darkStyle.dragSettleDuration, 0);
            compare(darkStyle.dragMergeDuration, 0);
            compare(darkStyle.dragMergeDelay, mergeDelay);
            compare(darkStyle.dragReorderDelay, reorderDelay);
            compare(darkStyle.dragExistingFolderMergeDelay,
                existingFolderDelay);
            verify(darkStyle.pointerDragThreshold > 0);
            verify(darkStyle.touchDragThreshold > 0);
        } finally {
            darkStyle.animationsEnabled = true;
        }
    }

    function test_highContrastBackdropRemainsReadableOverAnyWallpaper() {
        const overBlack = composite(highContrastStyle.backdrop, "#000000");
        const overWhite = composite(highContrastStyle.backdrop, "#ffffff");
        verify(contrast(highContrastStyle.foreground, overBlack) >= 7);
        verify(contrast(highContrastStyle.foreground, overWhite) >= 7);
        verify(contrast(highContrastStyle.searchForeground,
            highContrastStyle.searchBackground) >= 7);
    }

    function test_customBackdropKeepsChosenColorAndOpacitySeparate() {
        compare(customStyle.backgroundBaseColor, "#336699");
        verify(Math.abs(customStyle.backdrop.r - 0x33 / 255) < 0.001);
        verify(Math.abs(customStyle.backdrop.g - 0x66 / 255) < 0.001);
        verify(Math.abs(customStyle.backdrop.b - 0x99 / 255) < 0.001);
        verify(Math.abs(customStyle.backdrop.a - 0.4) < 0.001);

        customStyle.backgroundOpacity = 140;
        compare(customStyle.normalizedBackgroundOpacity, 1);
        customStyle.backgroundOpacity = -20;
        compare(customStyle.normalizedBackgroundOpacity, 0);
        customStyle.backgroundOpacity = 40;
    }

    function test_customBackgroundChoosesReadableLabelColors() {
        verify(customStyle.customBackgroundIsDark);
        verify(contrast(customStyle.foreground,
            customStyle.backgroundBaseColor) >= 4.5);
        verify(contrast(customStyle.secondaryForeground,
            customStyle.backgroundBaseColor) >= 4.5);

        verify(!lightCustomStyle.customBackgroundIsDark);
        verify(contrast(lightCustomStyle.foreground,
            lightCustomStyle.backgroundBaseColor) >= 7);
        verify(contrast(lightCustomStyle.secondaryForeground,
            lightCustomStyle.backgroundBaseColor) >= 4.5);

        // Folder surfaces follow the chosen grid background color instead of
        // remaining on the hard-coded dark GNOME palette.
        verify(Math.abs(customStyle.folderPanel.r
            - customStyle.backgroundBaseColor.r) < 0.001);
        verify(Math.abs(customStyle.folderPanel.g
            - customStyle.backgroundBaseColor.g) < 0.001);
        verify(Math.abs(customStyle.folderPanel.b
            - customStyle.backgroundBaseColor.b) < 0.001);
        verify(customStyle.folderPanel.a < 1);
        verify(Math.abs(customStyle.folderPanel.a
            - customStyle.folderPanelSurfaceOpacity) < 0.001);
        verify(Math.abs(customStyle.folderBackground.r
            - customStyle.backgroundBaseColor.r) < 0.001);
    }
}
