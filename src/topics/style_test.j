# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for style.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * A style exercising every property the model carries.
 *
 * Shared with the format overlays so one style is held to one contract, the
 * way `fixtureWorkbook` works for values.
 *
 * @return {Style} the style
 */
func fixtureStyle() {
    def st as Style init style();
    $st = withBold($st, true);
    $st = withItalic($st, true);
    $st = withUnderline($st, true);
    $st = withFont($st, "Georgia", 14.0);
    $st = withColour($st, "CC0000");
    $st = withBackground($st, "FFF2CC");
    $st = withAlign($st, Align.Centre);
    $st = withVerticalAlign($st, VAlign.Middle);
    $st = withWrap($st, true);
    $st = withBorder($st, BorderStyle.Thin);
    $st = withFormat($st, "#,##0.00");
    return $st;
}

/**
 * Assert that two styles agree on everything the model carries.
 *
 * @param got {Style} the style read back
 * @param want {Style} the style written
 * @param exactFormat {bool} whether the format code survives verbatim
 */
func assertStyleSurvived(got as Style, want as Style, exactFormat as bool) {
    testing.assertEqual($got.bold, $want.bold);
    testing.assertEqual($got.italic, $want.italic);
    testing.assertEqual($got.underline, $want.underline);
    testing.assertEqual($got.fontName, $want.fontName);
    testing.assertEqual($got.fontSize, $want.fontSize);
    testing.assertEqual($got.colour, $want.colour);
    testing.assertEqual($got.background, $want.background);
    testing.assertTrue($got.align == $want.align);
    testing.assertTrue($got.valign == $want.valign);
    testing.assertEqual($got.wrap, $want.wrap);
    testing.assertTrue($got.border == $want.border);
    if ($exactFormat) {
        testing.assertEqual($got.format, $want.format);
    } else {
        # ODF stores a format as a component tree rather than a code, so the
        # code is reconstructed rather than carried. What has to survive is
        # that there is a format and whether it is a date.
        testing.assertTrue($got.format != "");
        testing.assertEqual(isDateFormat($got), isDateFormat($want));
    }
}

func testWithFormatNormalisesGeneral() {
    # `General` *is* the absence of a format - it is what a file writes for a
    # cell that has none - so carrying it as a code made the three writers
    # disagree. XLSX wrote it back verbatim, Gnumeric dropped it, and ODF had
    # no component for it and wrote it as a literal, so the cell displayed the
    # word "General" instead of the number.
    testing.assertEqual(withFormat(style(), "General").format, "");
    testing.assertEqual(withFormat(style(), "general").format, "");
    testing.assertEqual(withFormat(style(), "  General  ").format, "");
    testing.assertTrue(isPlain(withFormat(style(), "General")));
    # A real code is kept, trimmed.
    testing.assertEqual(withFormat(style(), "0.00").format, "0.00");
    testing.assertEqual(withFormat(style(), " 0.00 ").format, "0.00");
    testing.assertFalse(isPlain(withFormat(style(), "0.00")));
}

func testTheDefaultStyleIsPlain() {
    testing.assertTrue(isPlain(style()));
    testing.assertFalse(isPlain(withBold(style(), true)));
}

func testTheBuildersAreValueSemantic() {
    def base as Style init style();
    def bolded as Style init withBold($base, true);
    testing.assertFalse($base.bold);
    testing.assertTrue($bolded.bold);
}

func testEveryBuilderSetsItsProperty() {
    def st as Style init fixtureStyle();
    testing.assertTrue($st.bold);
    testing.assertTrue($st.italic);
    testing.assertTrue($st.underline);
    testing.assertEqual($st.fontName, "Georgia");
    testing.assertEqual($st.fontSize, 14.0);
    testing.assertEqual($st.colour, "CC0000");
    testing.assertEqual($st.background, "FFF2CC");
    testing.assertTrue($st.align == Align.Centre);
    testing.assertTrue($st.valign == VAlign.Middle);
    testing.assertTrue($st.wrap);
    testing.assertTrue($st.border == BorderStyle.Thin);
    testing.assertEqual($st.format, "#,##0.00");
}

func testTwoStylesThatLookTheSameAreEqual() {
    # What lets a sheet intern them instead of holding one per cell.
    testing.assertTrue(fixtureStyle() == fixtureStyle());
    testing.assertFalse(fixtureStyle() == withBold(fixtureStyle(), false));
}

func testColoursAreNormalised() {
    # Two spellings of one colour have to intern to one style.
    testing.assertEqual(withColour(style(), "#cc0000").colour, "CC0000");
    testing.assertEqual(withColour(style(), "CC0000").colour, "CC0000");
    testing.assertTrue(withColour(style(), "#cc0000") == withColour(style(), "CC0000"));
    testing.assertEqual(withBackground(style(), "").background, "");
}

func failOnAShortColour() {
    withColour(style(), "CC0");
}

func failOnANonHexColour() {
    withColour(style(), "GGHHII");
}

func failOnABadBackground() {
    withBackground(style(), "red");
}

func testAColourMustBeSixHexDigits() {
    testing.assertThrows("failOnAShortColour", ERROR_KIND);
    testing.assertThrows("failOnANonHexColour", ERROR_KIND);
    testing.assertThrows("failOnABadBackground", ERROR_KIND);
}

func failOnANegativeFontSize() {
    withFont(style(), "Calibri", -1.0);
}

func failOnAnAbsurdFontSize() {
    withFont(style(), "Calibri", 100000.0);
}

func testAFontSizeIsBounded() {
    testing.assertThrows("failOnANegativeFontSize", ERROR_KIND);
    testing.assertThrows("failOnAnAbsurdFontSize", ERROR_KIND);
}

func testAZeroFontSizeMeansTheDefault() {
    def st as Style init withFont(style(), "", 0.0);
    testing.assertTrue(isPlain($st));
}

func testIsDateFormatReadsTheCode() {
    testing.assertTrue(isDateFormat(withFormat(style(), "yyyy-mm-dd")));
    testing.assertTrue(isDateFormat(withFormat(style(), "dd/mm/yy hh:mm")));
    testing.assertFalse(isDateFormat(withFormat(style(), "#,##0.00")));
    testing.assertFalse(isDateFormat(withFormat(style(), "0%")));
    testing.assertFalse(isDateFormat(style()));
}

func testAlignNamesMapFromEveryFormatsSpelling() {
    # The three applications spell the same alignment differently, so the
    # match is on the tail of whatever was written.
    testing.assertTrue(alignFromName("left") == Align.Left);
    testing.assertTrue(alignFromName("start") == Align.Left);
    testing.assertTrue(alignFromName("center") == Align.Centre);
    testing.assertTrue(alignFromName("GNM_HALIGN_CENTER") == Align.Centre);
    testing.assertTrue(alignFromName("right") == Align.Right);
    testing.assertTrue(alignFromName("end") == Align.Right);
    testing.assertTrue(alignFromName("") == Align.General);
    testing.assertTrue(alignFromName("justify") == Align.General);
}

func testVerticalAlignNamesMap() {
    testing.assertTrue(valignFromName("top") == VAlign.Top);
    testing.assertTrue(valignFromName("middle") == VAlign.Middle);
    testing.assertTrue(valignFromName("center") == VAlign.Middle);
    testing.assertTrue(valignFromName("bottom") == VAlign.Bottom);
    testing.assertTrue(valignFromName("") == VAlign.Bottom);
}

func testBorderNamesFallToTheNearestWeight() {
    # A weight this deck does not carry has to land on something, or a box
    # drawn elsewhere would vanish.
    testing.assertTrue(borderFromName("thin") == BorderStyle.Thin);
    testing.assertTrue(borderFromName("medium") == BorderStyle.Medium);
    testing.assertTrue(borderFromName("thick") == BorderStyle.Thick);
    testing.assertTrue(borderFromName("double") == BorderStyle.Medium);
    testing.assertTrue(borderFromName("dashed") == BorderStyle.Thin);
    testing.assertTrue(borderFromName("hair") == BorderStyle.Thin);
    testing.assertTrue(borderFromName("none") == BorderStyle.NoBorder);
    testing.assertTrue(borderFromName("") == BorderStyle.NoBorder);
}

func testTheFormatSpecificSpellings() {
    testing.assertEqual(alignToOoxml(Align.Centre), "center");
    testing.assertEqual(alignToOdf(Align.Centre), "center");
    testing.assertEqual(alignToOdf(Align.Left), "start");
    testing.assertEqual(alignToOdf(Align.Right), "end");
    testing.assertEqual(alignToOoxml(Align.General), "");
    testing.assertEqual(valignToOoxml(VAlign.Middle), "center");
    testing.assertEqual(valignToOdf(VAlign.Middle), "middle");
    testing.assertEqual(valignToOoxml(VAlign.Bottom), "");
    testing.assertEqual(borderToOoxml(BorderStyle.Thin), "thin");
    testing.assertEqual(borderToOoxml(BorderStyle.NoBorder), "");
    testing.assertTrue(strings.contains(borderToOdf(BorderStyle.Thick), "2pt"));
    testing.assertEqual(borderToOdf(BorderStyle.NoBorder), "");
}

func testEveryAlignmentRoundTripsThroughItsSpelling() {
    for (def how in [Align.Left, Align.Centre, Align.Right]) {
        testing.assertTrue(alignFromName(alignToOoxml($how)) == $how);
        testing.assertTrue(alignFromName(alignToOdf($how)) == $how);
    }
    for (def how in [VAlign.Top, VAlign.Middle]) {
        testing.assertTrue(valignFromName(valignToOoxml($how)) == $how);
        testing.assertTrue(valignFromName(valignToOdf($how)) == $how);
    }
    for (def weight in [BorderStyle.Thin, BorderStyle.Medium, BorderStyle.Thick]) {
        testing.assertTrue(borderFromName(borderToOoxml($weight)) == $weight);
    }
}
