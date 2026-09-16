import QtQuick
import QtTest

import "../package/contents/ui"

TestCase {
    id: testCase

    name: "CompactGlyph"

    AppGridGlyph {
        id: compactGlyph
        slotExtent: 27
    }

    AppGridGlyph {
        id: regularGlyph
        slotExtent: 40
    }

    AppGridGlyph {
        id: constrainedGlyph
        slotExtent: 12
    }

    function test_usesMostOfCompactPanelSlot() {
        verify(compactGlyph.width >= compactGlyph.slotExtent * 0.78);
        compare(compactGlyph.width, compactGlyph.height);
    }

    function test_scalesUpForRegularPanel() {
        verify(regularGlyph.width > compactGlyph.width);
        verify(regularGlyph.width >= regularGlyph.slotExtent * 0.78);
        compare(regularGlyph.width, regularGlyph.height);
    }

    function test_neverOverflowsThinPanel() {
        verify(constrainedGlyph.width <= constrainedGlyph.slotExtent);
        verify(constrainedGlyph.height <= constrainedGlyph.slotExtent);
    }

    function test_dotsFillGlyphBounds() {
        const contentExtent = regularGlyph.dotExtent * 3
            + regularGlyph.dotSpacing * 2;
        fuzzyCompare(contentExtent, regularGlyph.width, 0.01);
        verify(regularGlyph.dotExtent >= 2);
    }
}
