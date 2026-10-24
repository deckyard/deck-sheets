# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for odsfmt.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# The shapes asserted here were read off files LibreOffice wrote, and
# tools/format-oracle.sh checks that LibreOffice displays what this deck says
# these codes mean - through ODF's tree as well as through the two formats
# that store a code directly.

/**
 * Assert the components a format code becomes.
 *
 * @param code {string} the format code
 * @param want {string} the expected style element
 */
func assertOdfStyle(code as string, want as string) {
    testing.assertEqual(odfNumberStyle("N1", $code), $want);
}

/**
 * A format code written as ODF components and read back.
 *
 * @param code {string} the format code
 * @return {string} the code the components come back as
 */
func odfRoundTrip(code as string) {
    def s as Sheet init setStyle(sheetOf("S", [[number(1.0)]]), "A1", withFormat(style(), $code));
    def back as Sheet init sheetByName(readOds(writeOds(addSheet(newWorkbook(), $s))), "S");
    return styleAt($back, "A1").format;
}

/**
 * Assert that a format code survives the trip through ODF's components.
 *
 * @param code {string} the format code
 */
func assertOdfRoundTrip(code as string) {
    testing.assertEqual(odfRoundTrip($code), $code);
}

func testOdfPlainNumber() {
    assertOdfStyle(
        "0.00",
        "<number:number-style style:name=\"N1\">" +
            "<number:number number:decimal-places=\"2\" " +
            "number:min-decimal-places=\"2\" number:min-integer-digits=\"1\"/>" +
            "</number:number-style>");
    assertOdfRoundTrip("0.00");
    assertOdfRoundTrip("0");
    assertOdfRoundTrip("000");
}

func testOdfGrouping() {
    # `number:grouping` is the flag; the `#,##` in front of the zero is how a
    # code spells the same thing.
    testing.assertTrue(strings.contains(
        odfNumberStyle("N1", "#,##0.00"),
        "number:grouping=\"true\""));
    assertOdfRoundTrip("#,##0.00");
    assertOdfRoundTrip("#,##0");
}

func testOdfOptionalDecimals() {
    # `decimal-places` is how many are allowed and `min-decimal-places` how
    # many are insisted on, which is the difference between `0.0##` and
    # `0.000`.
    testing.assertTrue(strings.contains(
        odfNumberStyle("N1", "0.0##"),
        "number:decimal-places=\"3\""));
    testing.assertTrue(strings.contains(
        odfNumberStyle("N1", "0.0##"),
        "number:min-decimal-places=\"1\""));
    assertOdfRoundTrip("0.0##");
}

func testOdfPercentageIsItsOwnStyleKind() {
    # ODF does not put a `%` in a number style and scale it; the element type
    # is what says the value is a percentage.
    def body as string init odfNumberStyle("N1", "0.0%");
    testing.assertTrue(strings.contains($body, "number:percentage-style"));
    testing.assertTrue(strings.contains($body, "<number:text>%</number:text>"));
    assertOdfRoundTrip("0.0%");
    assertOdfRoundTrip("0%");
}

func testOdfLiterals() {
    def body as string init odfNumberStyle("N1", "$#,##0.00");
    testing.assertTrue(strings.contains($body, "<number:text>$</number:text>"));
    assertOdfRoundTrip("$#,##0.00");
    assertOdfRoundTrip("0.00");
}

func testOdfScientific() {
    def body as string init odfNumberStyle("N1", "0.00E+00");
    testing.assertTrue(strings.contains($body, "number:scientific-number"));
    testing.assertTrue(strings.contains($body, "number:min-exponent-digits=\"2\""));
    testing.assertTrue(strings.contains($body, "number:forced-exponent-sign=\"true\""));
    assertOdfRoundTrip("0.00E+00");
}

func testOdfFractionWholePartIsTheAttributeBeingThere() {
    # The difference between `# ?/?` and `?/?` is whether
    # `number:min-integer-digits` is present at all, not its value: absent
    # means the value is entirely a fraction, and a 0 means the whole part is
    # optional. Reading a 0 as "no whole part" turned `# ?/?` into `?/?`.
    testing.assertTrue(strings.contains(
        odfNumberStyle("N1", "# ?/?"),
        "number:min-integer-digits=\"0\""));
    testing.assertFalse(strings.contains(odfNumberStyle("N1", "?/?"), "number:min-integer-digits"));
    assertOdfRoundTrip("# ?/?");
    assertOdfRoundTrip("?/?");
    assertOdfRoundTrip("0 ?/?");
}

func testOdfFixedDenominator() {
    def body as string init odfNumberStyle("N1", "?/8");
    testing.assertTrue(strings.contains($body, "number:denominator-value=\"8\""));
    # The 8 is the fraction element's business, and writing it again as a
    # literal put a stray 8 after the fraction.
    testing.assertFalse(strings.contains($body, "<number:text>8</number:text>"));
    assertOdfRoundTrip("?/8");
}

func testOdfScalingIsADisplayFactor() {
    # ODF says "divide by a thousand" with a factor rather than by writing a
    # comma anywhere.
    testing.assertTrue(strings.contains(
        odfNumberStyle("N1", "0.0,,"),
        "number:display-factor=\"1000000\""));
    assertOdfRoundTrip("0.0,,");
    assertOdfRoundTrip("0,");
}

func testOdfDateComponents() {
    assertOdfStyle(
        "yyyy-mm-dd",
        "<number:date-style style:name=\"N1\">" +
            "<number:year number:style=\"long\"/><number:text>-</number:text>" +
            "<number:month number:style=\"long\"/><number:text>-</number:text>" +
            "<number:day number:style=\"long\"/></number:date-style>");
    assertOdfRoundTrip("yyyy-mm-dd");
    assertOdfRoundTrip("dd/mm/yyyy");
}

func testOdfDateSeparatorsSurviveAsWritten() {
    # A space in `<number:text> </number:text>` is the content, not
    # insignificant whitespace around it. `nodeText` trims - rightly, for
    # every other reader - which turned `d mmm yyyy` into `dmmmyyyy`.
    assertOdfRoundTrip("d mmm yyyy");
    assertOdfRoundTrip("dddd d mmmm yyyy");
    assertOdfRoundTrip("mmm-yy");
}

func testOdfTextualMonths() {
    testing.assertTrue(strings.contains(odfNumberStyle("N1", "mmm"), "number:textual=\"true\""));
    testing.assertTrue(strings.contains(odfNumberStyle("N1", "mmmm"), "number:style=\"long\""));
    assertOdfRoundTrip("mmm");
    assertOdfRoundTrip("mmmm");
    assertOdfRoundTrip("ddd");
    assertOdfRoundTrip("dddd");
}

func testOdfTimeIsASeparateStyleKind() {
    # ODF splits what one format code covers in two: a code naming only a
    # time is a `number:time-style`, and one naming a date is a date style
    # even when it also names a time.
    testing.assertTrue(strings.contains(odfNumberStyle("N1", "hh:mm:ss"), "number:time-style"));
    testing.assertTrue(strings.contains(
        odfNumberStyle("N1", "yyyy-mm-dd hh:mm"),
        "number:date-style"));
    assertOdfRoundTrip("hh:mm:ss");
    assertOdfRoundTrip("h:mm AM/PM");
    assertOdfRoundTrip("yyyy-mm-dd hh:mm:ss");
}

func testOdfMinuteVersusMonth() {
    # ODF has separate elements for the two, so the ambiguity has to be
    # settled before writing rather than after: `hh:mm` is minutes.
    testing.assertTrue(strings.contains(odfNumberStyle("N1", "hh:mm"), "number:minutes"));
    testing.assertFalse(strings.contains(odfNumberStyle("N1", "hh:mm"), "number:month"));
    testing.assertTrue(strings.contains(odfNumberStyle("N1", "mm/dd/yyyy"), "number:month"));
    assertOdfRoundTrip("hh:mm");
    assertOdfRoundTrip("mm/dd/yyyy");
}

func testOdfElapsedTimeIsAStyleAttribute() {
    # `[h]` is a span rather than an hour of the day, and ODF says so on the
    # style rather than on the hours element.
    testing.assertTrue(strings.contains(
        odfNumberStyle("N1", "[h]:mm"),
        "number:truncate-on-overflow=\"false\""));
    testing.assertFalse(strings.contains(
        odfNumberStyle("N1", "hh:mm"),
        "number:truncate-on-overflow"));
}

func testOdfSectionsBecomeSubStyles() {
    # The main style carries the *last* section and maps the earlier ones
    # onto volatile sub-styles, which is what LibreOffice writes.
    def body as string init odfNumberStyle("N1", "0.00;(0.00)");
    testing.assertTrue(strings.contains($body, "style:name=\"N1P0\" style:volatile=\"true\""));
    testing.assertTrue(strings.contains($body, "style:condition=\"value()&gt;=0\""));
    testing.assertTrue(strings.contains($body, "style:apply-style-name=\"N1P0\""));
    assertOdfRoundTrip("0.00;(0.00)");
    assertOdfRoundTrip("#,##0;(#,##0)");
}

func testOdfThreeAndFourSections() {
    def three as string init odfNumberStyle("N1", "0.00;-0.00;\"nil\"");
    testing.assertTrue(strings.contains($three, "value()&gt;0"));
    testing.assertTrue(strings.contains($three, "value()&lt;0"));
    # A four-section code's main style is the text one, because the fourth
    # section is the text section.
    def four as string init odfNumberStyle("N1", "0.00;-0.00;\"nil\";\"<\"@\">\"");
    testing.assertTrue(strings.contains($four, "number:text-style"));
    testing.assertTrue(strings.contains($four, "<number:text-content/>"));
}

func testOdfConditionsSurvive() {
    # A section may state its own condition, and ODF's `style:map` can carry
    # it, so the position is not the only thing that can select a section.
    def body as string init odfNumberStyle("N1", "[>100]\"big\";0.0");
    testing.assertTrue(strings.contains($body, "style:condition=\"value()&gt;100\""));
    assertOdfRoundTrip("[>100]\"big\";0.0");
}

func testOdfColourModifierBecomesTextProperties() {
    # The one part of a bracketed modifier ODF has somewhere to put.
    def body as string init odfNumberStyle("N1", "0.00;[Red]-0.00");
    testing.assertTrue(strings.contains($body, "fo:color=\"#ff0000\""));
}

func testOdfTextSection() {
    def body as string init odfNumberStyle("N1", "@");
    testing.assertTrue(strings.contains($body, "number:text-style"));
    testing.assertTrue(strings.contains($body, "<number:text-content/>"));
    assertOdfRoundTrip("@");
}

func testOdfColourLivesInThePropertiesNotTheCode() {
    # ODF has `fo:color` for a `[Red]` modifier and no component for it in
    # the code, so the code loses the modifier and the appearance does not.
    # The only code of 48 that does not round-trip identically through all
    # three formats, and it is this on purpose.
    def s as Sheet init setStyle(
        sheetOf("S", [[number(-12.5)]]),
        "A1",
        withFormat(style(), "0.00;[Red]-0.00"));
    def raw as bytes init writeOds(addSheet(newWorkbook(), $s));
    def content as string init convert.stringFromBytes(
        writeOdsContent(addSheet(newWorkbook(), $s)),
        "utf-8");
    testing.assertTrue(strings.contains($content, "fo:color=\"#ff0000\""));
    def back as Sheet init sheetByName(readOds($raw), "S");
    testing.assertEqual(styleAt($back, "A1").format, "0.00;-0.00");
    # The number still renders through the negative section.
    testing.assertEqual(displayAt($back, "A1"), "-12.50");
}

func testOdfGeneralIsNoStyleAtAll() {
    # A cell with no format needs no number style, and writing one would
    # make every plain cell carry a format it never asked for.
    def s as Sheet init sheetOf("S", [[number(1.5)]]);
    def back as Sheet init sheetByName(readOds(writeOds(addSheet(newWorkbook(), $s))), "S");
    testing.assertEqual(styleAt($back, "A1").format, "");
}

func testOdfSurvivesAMalformedStyle() {
    # A style with no components, and one whose map points nowhere. Neither
    # may throw: a format is a presentation detail.
    def document as string init "<?xml version=\"1.0\"?>" +
        "<office:document-content " +
        "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" " +
        "xmlns:number=\"urn:oasis:names:tc:opendocument:xmlns:" +
        "datastyle:1.0\" xmlns:style=\"urn:oasis:names:tc:opendocument:" +
        "xmlns:style:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:" +
        "xmlns:table:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:" +
        "xmlns:text:1.0\">" +
        "<office:automatic-styles>" +
        "<number:number-style style:name=\"N1\"/>" +
        "<number:number-style style:name=\"N2\">" +
        "<style:map style:condition=\"value()&gt;=0\" " +
        "style:apply-style-name=\"missing\"/></number:number-style>" +
        "<style:style style:name=\"ce1\" style:family=\"table-cell\" " +
        "style:data-style-name=\"N2\"/>" +
        "</office:automatic-styles><office:body><office:spreadsheet>" +
        "<table:table table:name=\"S\"><table:table-row>" +
        "<table:table-cell table:style-name=\"ce1\" " +
        "office:value-type=\"float\" office:value=\"1\">" +
        "<text:p>1</text:p></table:table-cell>" +
        "</table:table-row></table:table>" +
        "</office:spreadsheet></office:body></office:document-content>";
    def s as Sheet init sheetByName(
        readOdsContent(convert.bytesFromString($document, "utf-8")),
        "S");
    testing.assertEqual(asString(cell($s, "A1")), "1");
}
