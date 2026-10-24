# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for gnumeric.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# Gnumeric keeps less than the other two - a cached formula result has
# nowhere to go - and the tests assert exactly what it loses so that it
# cannot change unnoticed. Styles are *not* among the losses: they live in a
# block of rectangular regions before the cells rather than on each cell,
# which is why this codec carried none of them for its first three phases.

func testGnumericKeepsTheValuesAndTheFormulaSource() {
    def wb as Workbook init readGnumeric(writeGnumeric(fixtureWorkbook()));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asString(cell($s, "A1")), "Name");
    testing.assertEqual(asString(cell($s, "A2")), "Widget & Co");
    testing.assertEqual(asNumber(cell($s, "B2")), 4.0);
    testing.assertEqual(asNumber(cell($s, "C2")), 9.99);
    testing.assertTrue(asBool(cell($s, "A5")));
    testing.assertEqual(kindOf(cell($s, "B5")), "error");
    assertFormulaSource($s, "C3", "B3*C2");
    testing.assertEqual(sheetNames($wb), ["Sheet1", "Second Sheet"]);
}

func testGnumericLosesAFormulasCachedResult() {
    # An honest limitation, asserted so it cannot change without being noticed:
    # Gnumeric stores the expression in the cell body and recalculates on open,
    # so there is nowhere for the cached result to go.
    def wb as Workbook init readGnumeric(writeGnumeric(fixtureWorkbook()));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "C3");
    match ($v) {
        when Formula(f) {
            testing.assertEqual($f.source, "B3*C2");
            testing.assertEqual($f.cached, "");
        }
        else { throw Error{kind: "test", message: "not a formula", file: "", line: 0, col: 0}; }
    }
}

func testGnumericKeepsADateAsItsSerial() {
    # The format has no date type, so a date goes in as the number it is.
    def wb as Workbook init readGnumeric(writeGnumeric(fixtureWorkbook()));
    testing.assertEqual(asNumber(cell(sheetByName($wb, "Sheet1"), "C4")), 46297.0);
}

func testGnumericReadsAnUngzippedDocument() {
    def plain as bytes init writeGnumericXml(fixtureWorkbook());
    def wb as Workbook init readGnumeric($plain);
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "A1")), "Name");
}

func testAGnumericFileIsGzipped() {
    def raw as bytes init writeGnumeric(fixtureWorkbook());
    testing.assertEqual($raw[0], 0x1f);
    testing.assertEqual($raw[1], 0x8b);
}

func testTheDocumentDeclaresItsVersion() {
    # Gnumeric refuses a document with no <gnm:Version>.
    def doc as string init convert.stringFromBytes(writeGnumericXml(fixtureWorkbook()), "utf-8");
    testing.assertTrue(strings.contains($doc, "<gnm:Version "));
}

func testTheSheetNameIndexMatchesTheSheets() {
    # Gnumeric cross-checks the index against the sheets and refuses the file
    # when they disagree: "inconsistent SheetNameIndex element". LibreOffice
    # does not mind, which is why this was missed until the reference
    # implementation was asked.
    def doc as string init convert.stringFromBytes(writeGnumericXml(fixtureWorkbook()), "utf-8");
    testing.assertTrue(strings.contains($doc, "<gnm:SheetNameIndex>"));
    for (def name in sheetNames(fixtureWorkbook())) {
        testing.assertTrue(strings.contains($doc, ">" + $name + "</gnm:SheetName>"));
    }
}

func testAFormulaCellCarriesNoValueTypeAttribute() {
    # Three spellings, three behaviours, checked against both applications:
    #   ValueType="40"   LibreOffice reads NaN
    #   ValueType=""     LibreOffice reads the cell as blank
    #   absent           both read the formula, which is what Gnumeric writes
    # So an empty attribute is not the same as an omitted one here.
    def doc as string init convert.stringFromBytes(writeGnumericXml(fixtureWorkbook()), "utf-8");
    testing.assertTrue(strings.contains($doc, "=B3*C2</gnm:Cell>"));
    testing.assertFalse(strings.contains($doc, "ValueType=\"\""));
}

func testANonFormulaCellStillCarriesItsType() {
    def doc as string init convert.stringFromBytes(writeGnumericXml(fixtureWorkbook()), "utf-8");
    testing.assertTrue(strings.contains($doc, "ValueType=\"60\">Name"));
    testing.assertTrue(strings.contains($doc, "ValueType=\"40\">4"));
    testing.assertTrue(strings.contains($doc, "ValueType=\"20\">TRUE"));
}

/**
 * A sheet carrying one of everything this codec can style.
 *
 * @return {Sheet} the fixture
 */
func styledGnumericSheet() {
    def s as Sheet init sheetOf(
        "Styled",
        [
            [text("Head"), text("Other")],
            [number(0.5), number(1234.5)],
            [text("edge"), text("plain")]
        ]);
    $s = setAreaStyle(
        $s,
        "A1:B1",
        withBackground(withColour(withBold(style(), true), "CC0000"), "EEEEEE"));
    $s = setStyle($s, "A2", withFormat(style(), "0.0%"));
    $s = setStyle($s, "B2", withFormat(withItalic(style(), true), "$#,##0.00"));
    $s = setStyle($s, "A3", withBorder(withAlign(style(), Align.Centre), BorderStyle.Thick));
    return $s;
}

/**
 * That fixture, written as Gnumeric and read back.
 *
 * @return {Sheet} the sheet after a round trip
 */
func gnumericStyleRoundTrip() {
    def wb as Workbook init addSheet(newWorkbook(), styledGnumericSheet());
    return sheetByName(readGnumeric(writeGnumeric($wb)), "Styled");
}

func testGnumericKeepsFontsAndColours() {
    # Gnumeric holds styles in a block of rectangular regions before the
    # cells, which is the opposite of the other two formats and is why this
    # codec carried no styles at all for its first three phases.
    def s as Sheet init gnumericStyleRoundTrip();
    testing.assertTrue(styleAt($s, "A1").bold);
    testing.assertEqual(styleAt($s, "A1").colour, "CC0000");
    testing.assertEqual(styleAt($s, "A1").background, "EEEEEE");
    testing.assertTrue(styleAt($s, "B1").bold);
    testing.assertTrue(styleAt($s, "B2").italic);
    testing.assertFalse(styleAt($s, "B2").bold);
}

func testGnumericKeepsTheNumberFormatCode() {
    # The code itself, not an approximation of it: Gnumeric stores a format
    # as a string in a `Format` attribute, as XLSX does and ODF does not.
    def s as Sheet init gnumericStyleRoundTrip();
    testing.assertEqual(styleAt($s, "A2").format, "0.0%");
    testing.assertEqual(styleAt($s, "B2").format, "$#,##0.00");
    testing.assertEqual(displayAt($s, "A2"), "50.0%");
    testing.assertEqual(displayAt($s, "B2"), "$1,234.50");
}

func testGnumericKeepsAlignmentAndBorders() {
    def s as Sheet init gnumericStyleRoundTrip();
    def st as Style init styleAt($s, "A3");
    match ($st.align) {
        when Centre {
        }
        else {
            throw Error{
                kind: "test",
                message: "the centre alignment was lost",
                file: "",
                line: 0,
                col: 0
            };
        }
    }
    match ($st.border) {
        when Thick {
        }
        else {
            throw Error{
                kind: "test",
                message: "the thick border was lost",
                file: "",
                line: 0,
                col: 0
            };
        }
    }
}

func testGnumericKeepsEveryBorderWeight() {
    # The weights are an enumeration with dashed and dotted among them, so
    # thick is 5 rather than 3. Each was checked against `ssconvert` output.
    def s as Sheet init sheetOf("S", [[text("a"), text("b"), text("c")]]);
    $s = setStyle($s, "A1", withBorder(style(), BorderStyle.Thin));
    $s = setStyle($s, "B1", withBorder(style(), BorderStyle.Medium));
    $s = setStyle($s, "C1", withBorder(style(), BorderStyle.Thick));
    def back as Sheet init sheetByName(
        readGnumeric(writeGnumeric(addSheet(newWorkbook(), $s))),
        "S");
    testing.assertEqual(borderToOoxml(styleAt($back, "A1").border), "thin");
    testing.assertEqual(borderToOoxml(styleAt($back, "B1").border), "medium");
    testing.assertEqual(borderToOoxml(styleAt($back, "C1").border), "thick");
}

func testGnumericLeavesAnUnstyledCellPlain() {
    # A region is an override, so a cell with nothing to say gets none and
    # the block stays proportional to the styling rather than to the sheet.
    def s as Sheet init gnumericStyleRoundTrip();
    testing.assertTrue(isPlain(styleAt($s, "B3")));
    def bare as Workbook init addSheet(newWorkbook(), sheetOf("S", [[text("a"), text("b")]]));
    def xml as string init convert.stringFromBytes(writeGnumericXml($bare), "utf-8");
    testing.assertFalse(strings.contains($xml, "gnm:Styles"));
}

func testGnumericMergesARunOfMatchingStyles() {
    # Adjacent cells of a kind become one region, which is the shape
    # `ssconvert` writes. Three cells, one region.
    def s as Sheet init sheetOf("S", [[text("a"), text("b"), text("c")]]);
    $s = setAreaStyle($s, "A1:C1", withBold(style(), true));
    def xml as string init convert.stringFromBytes(
        writeGnumericXml(addSheet(newWorkbook(), $s)),
        "utf-8");
    testing.assertEqual(len(strings.split($xml, "<gnm:StyleRegion")) - 1, 1);
    testing.assertTrue(strings.contains($xml, "startCol=\"0\""));
    testing.assertTrue(strings.contains($xml, "endCol=\"2\""));
}

func testGnumericMergesABlockIntoOneRegion() {
    # A region is rectangular, so a run merges along both axes. A format
    # applied to a block - which is what "format this column" produces - is
    # one region, not one per row. Per-row regions made the file eleven times
    # the size of the equivalent ODS and twice as slow to read back.
    def lines as list of list of Value init [];
    for (def i in 0..4) {
        $lines[] = [number(1.0), number(2.0), number(3.0)];
    }
    def s as Sheet init setAreaStyle(
        sheetOf("S", $lines),
        "A1:C4",
        withFormat(withBold(style(), true), "0.00"));
    def xml as string init convert.stringFromBytes(
        writeGnumericXml(addSheet(newWorkbook(), $s)),
        "utf-8");
    testing.assertEqual(len(strings.split($xml, "<gnm:StyleRegion")) - 1, 1);
    testing.assertTrue(strings.contains(
        $xml,
        "startCol=\"0\" startRow=\"0\" endCol=\"2\" endRow=\"3\""));
    # And every corner of it survives the round trip.
    def back as Sheet init sheetByName(
        readGnumeric(writeGnumeric(addSheet(newWorkbook(), $s))),
        "S");
    for (def ref in ["A1", "C1", "A4", "C4", "B2"]) {
        testing.assertEqual(styleAt($back, $ref).format, "0.00");
        testing.assertTrue(styleAt($back, $ref).bold);
    }
}

func testGnumericDoesNotMergeRowsThatDiffer() {
    # Two rows styled the same but over different columns cannot be one
    # rectangle, and neither can two rows whose styles differ.
    def s as Sheet init sheetOf(
        "S",
        [[number(1.0), number(2.0)], [number(3.0), number(4.0)], [number(5.0), number(6.0)]]);
    $s = setAreaStyle($s, "A1:B1", withBold(style(), true));
    $s = setStyle($s, "A2", withBold(style(), true));
    $s = setAreaStyle($s, "A3:B3", withItalic(style(), true));
    def xml as string init convert.stringFromBytes(
        writeGnumericXml(addSheet(newWorkbook(), $s)),
        "utf-8");
    testing.assertEqual(len(strings.split($xml, "<gnm:StyleRegion")) - 1, 3);
    def back as Sheet init sheetByName(
        readGnumeric(writeGnumeric(addSheet(newWorkbook(), $s))),
        "S");
    testing.assertTrue(styleAt($back, "B1").bold);
    testing.assertTrue(isPlain(styleAt($back, "B2")));
    testing.assertTrue(styleAt($back, "A3").italic);
}

func testGnumericDoesNotMergeAcrossAChangeOfStyle() {
    def s as Sheet init sheetOf("S", [[text("a"), text("b"), text("c")]]);
    $s = setStyle($s, "A1", withBold(style(), true));
    $s = setStyle($s, "C1", withBold(style(), true));
    def xml as string init convert.stringFromBytes(
        writeGnumericXml(addSheet(newWorkbook(), $s)),
        "utf-8");
    testing.assertEqual(len(strings.split($xml, "<gnm:StyleRegion")) - 1, 2);
}

func testGnumericColoursAreSixteenBitChannels() {
    # `CC` becomes `CCCC`: an 8-bit channel is the value repeated, which
    # makes the conversion textual in both directions.
    testing.assertEqual(gnumericColourText("CC0000"), "CCCC:0000:0000");
    testing.assertEqual(gnumericColourText("EEEEEE"), "EEEE:EEEE:EEEE");
    # And back, including the short form Gnumeric writes for a zero channel.
    testing.assertEqual(gnumericColour("CCCC:0:0", ""), "CC0000");
    testing.assertEqual(gnumericColour("EEEE:EEEE:EEEE", ""), "EEEEEE");
    testing.assertEqual(gnumericColour("FFFF:FFFF:FFFF", ""), "FFFFFF");
    # The value that means "nothing here" comes back as no colour.
    testing.assertEqual(gnumericColour("0:0:0", "000000"), "");
    testing.assertEqual(gnumericColour("FFFF:FFFF:FFFF", "FFFFFF"), "");
    testing.assertEqual(gnumericColour("", ""), "");
    testing.assertEqual(gnumericColour("nonsense", ""), "");
}

func testGnumericDefaultFontIsNotAChoice() {
    # Gnumeric writes Calibri at 11 points on every cell, so reading those
    # as a choice would make every cell in the file carry a font it never
    # asked for - and every style stop being plain.
    def s as Sheet init sheetOf("S", [[text("a")]]);
    $s = setStyle($s, "A1", withBold(style(), true));
    def back as Sheet init sheetByName(
        readGnumeric(writeGnumeric(addSheet(newWorkbook(), $s))),
        "S");
    testing.assertEqual(styleAt($back, "A1").fontName, "");
    testing.assertEqual(styleAt($back, "A1").fontSize, 0.0);
    # A font that *was* chosen does come back.
    def chosen as Sheet init setStyle(
        sheetOf("S", [[text("a")]]),
        "A1",
        withFont(style(), "Georgia", 14.0));
    def kept as Sheet init sheetByName(
        readGnumeric(writeGnumeric(addSheet(newWorkbook(), $chosen))),
        "S");
    testing.assertEqual(styleAt($kept, "A1").fontName, "Georgia");
    testing.assertEqual(styleAt($kept, "A1").fontSize, 14.0);
}

func testGnumericIgnoresAStyleRegionCoveringTheWholeGrid() {
    # `ssconvert` fills the unused part of a sheet with a region spanning
    # every column and row. Expanding one would ask for 17 billion entries,
    # so a region whose style says nothing is never walked at all.
    def document as string init "<?xml version=\"1.0\"?>" +
        "<gnm:Workbook xmlns:gnm=\"http://www.gnumeric.org/v10.dtd\">" +
        "<gnm:Sheets><gnm:Sheet><gnm:Name>S</gnm:Name>" +
        "<gnm:Styles><gnm:StyleRegion startCol=\"0\" startRow=\"0\" " +
        "endCol=\"16383\" endRow=\"1048575\"><gnm:Style Format=\"General\" " +
        "Fore=\"0:0:0\" Back=\"FFFF:FFFF:FFFF\" Shade=\"0\"/>" +
        "</gnm:StyleRegion></gnm:Styles>" +
        "<gnm:Cells><gnm:Cell Row=\"0\" Col=\"0\" ValueType=\"60\">a</gnm:Cell>" +
        "</gnm:Cells></gnm:Sheet></gnm:Sheets></gnm:Workbook>";
    def s as Sheet init sheetByName(readGnumeric(convert.bytesFromString($document, "utf-8")), "S");
    testing.assertEqual(asString(cell($s, "A1")), "a");
    testing.assertTrue(isPlain(styleAt($s, "A1")));
}

func failOnAHugeStyledRegion() {
    # The same shape with a style that *does* say something is the hostile
    # case, and it is clipped to the sheet rather than taken at its word.
    def document as string init "<?xml version=\"1.0\"?>" +
        "<gnm:Workbook xmlns:gnm=\"http://www.gnumeric.org/v10.dtd\">" +
        "<gnm:Sheets><gnm:Sheet><gnm:Name>S</gnm:Name>" +
        "<gnm:Styles><gnm:StyleRegion startCol=\"0\" startRow=\"0\" " +
        "endCol=\"16383\" endRow=\"1048575\"><gnm:Style Format=\"0.00\" " +
        "Fore=\"0:0:0\" Back=\"FFFF:FFFF:FFFF\" Shade=\"0\"/>" +
        "</gnm:StyleRegion></gnm:Styles>" +
        "<gnm:Cells><gnm:Cell Row=\"0\" Col=\"0\" ValueType=\"40\">1</gnm:Cell>" +
        "</gnm:Cells></gnm:Sheet></gnm:Sheets></gnm:Workbook>";
    readGnumeric(convert.bytesFromString($document, "utf-8"));
}

func testGnumericSurvivesMalformedStyleRegions() {
    # Nonsense bounds, a region with no style, and five hundred regions each
    # claiming the whole grid. None of these may hang or throw: a style is a
    # presentation detail and a file full of odd ones should still be read.
    def regions as list of string init [
        "<gnm:StyleRegion startCol=\"-5\" startRow=\"-5\" endCol=\"x\" " +
            "endRow=\"\"><gnm:Style Format=\"0.00\" Shade=\"0\"/>" +
            "</gnm:StyleRegion>",
        "<gnm:StyleRegion startCol=\"0\" startRow=\"0\" endCol=\"0\" " +
            "endRow=\"0\"/>",
        "<gnm:StyleRegion startCol=\"0\" startRow=\"0\" " +
            "endCol=\"99999999\" endRow=\"99999999\"><gnm:Style " +
            "Format=\"0.00\" Shade=\"0\"/></gnm:StyleRegion>"
    ];
    for (def region in $regions) {
        def s as Sheet init sheetByName(
            readGnumeric(convert.bytesFromString(gnumericDocumentWith($region), "utf-8")),
            "S");
        testing.assertEqual(asString(cell($s, "A1")), "1");
    }
}

/**
 * A one-cell Gnumeric document carrying the given style regions.
 *
 * @param regions {string} the `<gnm:StyleRegion>` markup
 * @return {string} the document
 */
func gnumericDocumentWith(regions as string) {
    return "<?xml version=\"1.0\"?><gnm:Workbook " +
        "xmlns:gnm=\"http://www.gnumeric.org/v10.dtd\"><gnm:Sheets>" +
        "<gnm:Sheet><gnm:Name>S</gnm:Name><gnm:Styles>" + $regions +
        "</gnm:Styles><gnm:Cells><gnm:Cell Row=\"0\" Col=\"0\" " +
        "ValueType=\"40\">1</gnm:Cell></gnm:Cells></gnm:Sheet>" +
        "</gnm:Sheets></gnm:Workbook>";
}

func testGnumericClipsAStyledRegionToTheSheet() {
    # It must not throw and must not hang: one cell, one styled cell.
    failOnAHugeStyledRegion();
    def document as string init "<?xml version=\"1.0\"?>" +
        "<gnm:Workbook xmlns:gnm=\"http://www.gnumeric.org/v10.dtd\">" +
        "<gnm:Sheets><gnm:Sheet><gnm:Name>S</gnm:Name>" +
        "<gnm:Styles><gnm:StyleRegion startCol=\"0\" startRow=\"0\" " +
        "endCol=\"16383\" endRow=\"1048575\"><gnm:Style Format=\"0.00\" " +
        "Fore=\"0:0:0\" Back=\"FFFF:FFFF:FFFF\" Shade=\"0\"/>" +
        "</gnm:StyleRegion></gnm:Styles>" +
        "<gnm:Cells><gnm:Cell Row=\"0\" Col=\"0\" ValueType=\"40\">1</gnm:Cell>" +
        "</gnm:Cells></gnm:Sheet></gnm:Sheets></gnm:Workbook>";
    def s as Sheet init sheetByName(readGnumeric(convert.bytesFromString($document, "utf-8")), "S");
    testing.assertEqual(styleAt($s, "A1").format, "0.00");
    testing.assertEqual(displayAt($s, "A1"), "1.00");
}
