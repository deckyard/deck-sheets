# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for odswrite.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# The round-trip tests are the ones that matter most: a codec can be
# individually correct and still lose something when paired with another.
# The fixture and the per-value assertions live in model_test.j, so every
# format is held to one contract.

func assertFormulaSource(s as Sheet, at as string, source as string) {
    def v as Value init cell($s, $at);
    match ($v) {
        when Formula(f) { testing.assertEqual($f.source, $source); }
        else {
            throw Error{
                kind: "test",
                message: "cell " + $at + " is not a formula but a " + kindOf($v),
                file: "",
                line: 0,
                col: 0
            };
        }
    }
}

func testOdsKeepsEverythingTheModelHolds() {
    def wb as Workbook init readOds(writeOds(fixtureWorkbook()));
    assertFixtureSurvived($wb, true);
}

/**
 * Assert that a cell holds a formula with a given source.
 *
 * @param s {Sheet} the sheet
 * @param at {string} the A1 reference
 * @param source {string} the expected A1 expression
 */
func testTheOdsFileIsWrittenAsOdfRequires() {
    # mimetype first and uncompressed, so that a magic-byte sniffer finds the
    # media type at a fixed offset. This is the whole reason zip.j exists, and
    # the offsets are what `file(1)` actually reads:
    #   0..30   the local file header
    #   30..38  the member name, which must be exactly "mimetype"
    #   38..    the media type, stored uncompressed so it is readable in place
    def raw as bytes init writeOds(fixtureWorkbook());
    def name as bytes init convert.bytesFromString("mimetype", "utf-8");
    def marker as bytes init convert.bytesFromString(ODS_MIMETYPE, "utf-8");
    testing.assertEqual(binary.indexOf($raw, $name), 30);
    testing.assertEqual(binary.indexOf($raw, $marker), 38);
}

func testAWrittenOdsCarriesTheRequiredParts() {
    def parts as map of string to bytes init unzip(writeOds(fixtureWorkbook()));
    for (def required in ["mimetype", "META-INF/manifest.xml", "content.xml", "styles.xml"]) {
        testing.assertTrue(maps.has($parts, $required));
    }
}

func testEveryWrittenPartIsWellFormedXml() {
    # The emitter writes text, not a tree, so nothing but a test proves the
    # output parses.
    def parts as map of string to bytes init unzip(writeOds(fixtureWorkbook()));
    for (def name in $parts) {
        if (strings.endsWith($name, ".xml")) {
            xml.decode(convert.stringFromBytes($parts[$name], "utf-8"));
        }
    }
    def xlsxParts as map of string to bytes init unzip(writeXlsx(fixtureWorkbook()));
    for (def name in $xlsxParts) {
        if (strings.endsWith($name, ".xml") or strings.endsWith($name, ".rels")) {
            xml.decode(convert.stringFromBytes($xlsxParts[$name], "utf-8"));
        }
    }
}

func testWritingTheSameWorkbookTwiceGivesTheSameBytes() {
    # No timestamps anywhere, so a golden file stays stable and a rebuild is
    # reproducible.
    def wb as Workbook init fixtureWorkbook();
    testing.assertEqual(len(writeOds($wb)), len(writeOds($wb)));
    testing.assertEqual(len(writeXlsx($wb)), len(writeXlsx($wb)));
    testing.assertEqual(
        convert.stringFromBytes(writeOdsContent($wb), "utf-8"),
        convert.stringFromBytes(writeOdsContent($wb), "utf-8"));
}

func failOnAnUnknownExtension() {
    formatOf("a.numbers");
}

func failOnNoExtension() {
    formatOf("spreadsheet");
}

func failOnAZipThatIsNoSpreadsheet() {
    def members as list of Member init [];
    $members[] = member("readme.txt", convert.bytesFromString("hi", "utf-8"));
    formatOfBytes(zip($members));
}

func testOdsKeepsEveryStyleProperty() {
    def s as Sheet init sheetOf("S", [[text("styled")]]);
    $s = setStyle($s, "A1", fixtureStyle());
    def back as Workbook init readOds(writeOds(addSheet(newWorkbook(), $s)));
    # ODF stores a format as a component tree, not a code, so the code is
    # reconstructed rather than carried verbatim.
    assertStyleSurvived(styleAt(sheetByName($back, "S"), "A1"), fixtureStyle(), false);
}

func testOdsWritesTheFontAsAFamilyNotAReference() {
    # `style:font-name` points at a font face that has to be declared in
    # `<office:font-face-decls>`; without the declaration LibreOffice silently
    # ignores it. `fo:font-family` needs no declaration.
    def s as Sheet init sheetOf("S", [[text("x")]]);
    $s = setStyle($s, "A1", withFont(style(), "Georgia", 12.0));
    def doc as string init convert.stringFromBytes(
        writeOdsContent(addSheet(newWorkbook(), $s)),
        "utf-8");
    testing.assertTrue(strings.contains($doc, "fo:font-family=\"Georgia\""));
    testing.assertFalse(strings.contains($doc, "style:font-name"));
}

func testAnUnstyledOdsSheetDeclaresNoCellStyles() {
    # A plain sheet should not grow style machinery it does not use.
    def doc as string init convert.stringFromBytes(writeOdsContent(fixtureWorkbook()), "utf-8");
    testing.assertFalse(strings.contains($doc, "style:name=\"ce0x1\""));
}

func testAStyledBlankCellIsStillWritten() {
    def s as Sheet init newSheet("S");
    $s = setStyle($s, "B1", withBackground(style(), "FFF2CC"));
    def back as Workbook init readOds(writeOds(addSheet(newWorkbook(), $s)));
    def b as Sheet init sheetByName($back, "S");
    testing.assertTrue(isEmpty(cell($b, "B1")));
    testing.assertEqual(styleAt($b, "B1").background, "FFF2CC");
}

func testOdsStylesSurviveAlongsideValuesAndFormulas() {
    def wb as Workbook init fixtureWorkbook();
    def s as Sheet init sheetByName($wb, "Sheet1");
    $s = setAreaStyle($s, "A1:C1", withBold(style(), true));
    $wb = putSheet($wb, $s);
    def back as Workbook init readOds(writeOds($wb));
    assertFixtureSurvived($back, true);
    testing.assertTrue(styleAt(sheetByName($back, "Sheet1"), "B1").bold);
    testing.assertFalse(styleAt(sheetByName($back, "Sheet1"), "A2").bold);
}
