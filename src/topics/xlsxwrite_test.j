# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# sheets - tests for xlsxwrite.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# Includes the cross-format conversions, which are what the formula dialect
# translator exists for.

func testXlsxKeepsEverythingTheModelHolds() {
    def wb as Workbook init readXlsx(writeXlsx(fixtureWorkbook()));
    assertFixtureSurvived($wb, true);
}

func testOdsToXlsx() {
    # The conversion the formula dialect translator exists for.
    def wb as Workbook init readXlsx(writeXlsx(readOds(writeOds(fixtureWorkbook()))));
    assertFixtureSurvived($wb, true);
}

func testXlsxToOds() {
    def wb as Workbook init readOds(writeOds(readXlsx(writeXlsx(fixtureWorkbook()))));
    assertFixtureSurvived($wb, true);
}

func testAWrittenXlsxCarriesTheRequiredParts() {
    def parts as map of string to bytes init unzip(writeXlsx(fixtureWorkbook()));
    for (def required in [
        "[Content_Types].xml",
        "_rels/.rels",
        "xl/workbook.xml",
        "xl/_rels/workbook.xml.rels",
        "xl/styles.xml",
        "xl/sharedStrings.xml",
        "xl/worksheets/sheet1.xml",
        "xl/worksheets/sheet2.xml"
    ]) {
        testing.assertTrue(maps.has($parts, $required));
    }
}

func testAnEmptyTextIsNotTheFirstSharedString() {
    # "" used to be left out of the shared table and its cell pointed at
    # entry 0, so it showed the first string of the workbook. Read back, an
    # empty text is an empty cell, as in every format.
    def s as Sheet init sheetOf("S", [[text("Header")], [text("")]]);
    def back as Workbook init readXlsx(writeXlsx(addSheet(newWorkbook(), $s)));
    testing.assertEqual(cellAt(sheetByName($back, "S"), Ref{row: 1, col: 0}), empty());
}

func testATextMissingFromTheSharedTableIsRefused() {
    testing.assertThrows("lookUpAMissingSharedString", ERROR_KIND);
}

func lookUpAMissingSharedString() {
    sharedIndex(SharedStrings{texts: ["a"], index: {"a": 0}}, "b");
}

func testABuiltInFormatIsWrittenByItsId() {
    # As Excel writes them: Text is id 49, "0.00" id 2, with no <numFmt>.
    def s as Sheet init sheetOf("S", [[text("a"), number(1.5), number(2.0)]]);
    $s = setStyle($s, "A1", withFormat(style(), "@"));
    $s = setStyle($s, "B1", withFormat(style(), "0.00"));
    $s = setStyle($s, "C1", withFormat(style(), "dd/mm/yyyy"));
    def raw as bytes init writeXlsx(addSheet(newWorkbook(), $s));
    def doc as string init encoding.decode("utf-8", unzip($raw)["xl/styles.xml"]);
    testing.assertTrue(strings.contains($doc, "numFmtId=\"49\""));
    testing.assertTrue(strings.contains($doc, "numFmtId=\"2\""));
    testing.assertFalse(strings.contains($doc, "formatCode=\"@\""));
    # A date code is the file's own: a built-in date id is drawn per locale.
    testing.assertTrue(strings.contains($doc, "formatCode=\"dd/mm/yyyy\""));
    def back as Sheet init sheetByName(readXlsx($raw), "S");
    testing.assertEqual(styleAt($back, "A1").format, "@");
    testing.assertEqual(styleAt($back, "B1").format, "0.00");
    testing.assertEqual(styleAt($back, "C1").format, "dd/mm/yyyy");
}

func testXlsxKeepsEveryStyleProperty() {
    def s as Sheet init sheetOf("S", [[text("styled")]]);
    $s = setStyle($s, "A1", fixtureStyle());
    def back as Workbook init readXlsx(writeXlsx(addSheet(newWorkbook(), $s)));
    # OOXML stores the format as a code, so it survives verbatim.
    assertStyleSurvived(styleAt(sheetByName($back, "S"), "A1"), fixtureStyle(), true);
}

func testTheWorkbookHasOneStyleTable() {
    # OOXML has one cellXfs for the package, so two sheets using the same
    # style must share an entry rather than each getting one.
    def a as Sheet init sheetOf("A", [[text("x")]]);
    def b as Sheet init sheetOf("B", [[text("y")]]);
    def st as Style init withBold(style(), true);
    $a = setStyle($a, "A1", $st);
    $b = setStyle($b, "A1", $st);
    def wb as Workbook init addSheet(addSheet(newWorkbook(), $a), $b);
    def doc as string init encoding.decode("utf-8", unzip(writeXlsx($wb))["xl/styles.xml"]);
    # The three reserved entries plus one shared style.
    testing.assertTrue(strings.contains($doc, "<cellXfs count=\"4\">"));
    def back as Workbook init readXlsx(writeXlsx($wb));
    testing.assertTrue(styleAt(sheetByName($back, "A"), "A1").bold);
    testing.assertTrue(styleAt(sheetByName($back, "B"), "A1").bold);
}

func testADateKeepsADateFormatEvenWithAStyle() {
    # A style with no number format of its own must not cost a date cell its
    # date format, or the serial would display.
    def s as Sheet init sheetOf("S", [[date(time.fromIso("2026-10-02T00:00:00Z"))]]);
    $s = setStyle($s, "A1", withBold(style(), true));
    def back as Workbook init readXlsx(writeXlsx(addSheet(newWorkbook(), $s)));
    def v as Value init cell(sheetByName($back, "S"), "A1");
    testing.assertEqual(kindOf($v), "stamp");
    testing.assertEqual(time.format(asTime($v), "%Y-%m-%d"), "2026-10-02");
}

func testAStyleWithItsOwnDateFormatIsKept() {
    def s as Sheet init sheetOf("S", [[date(time.fromIso("2026-10-02T00:00:00Z"))]]);
    $s = setStyle($s, "A1", withFormat(style(), "dd/mm/yyyy"));
    def back as Workbook init readXlsx(writeXlsx(addSheet(newWorkbook(), $s)));
    def b as Sheet init sheetByName($back, "S");
    testing.assertEqual(styleAt($b, "A1").format, "dd/mm/yyyy");
    testing.assertEqual(kindOf(cell($b, "A1")), "stamp");
}

func testTheStyleTablesAreBuiltFromWhatIsUsed() {
    def s as Sheet init sheetOf("S", [[text("a"), text("b")]]);
    $s = setStyle($s, "A1", withBackground(style(), "FFF2CC"));
    $s = setStyle($s, "B1", withFormat(style(), "#,##0.000"));
    def doc as string init encoding.decode(
        "utf-8",
        unzip(writeXlsx(addSheet(newWorkbook(), $s)))["xl/styles.xml"]);
    # Two reserved fills plus the one used; a file's own formats start at 164.
    testing.assertTrue(strings.contains($doc, "<fills count=\"3\">"));
    testing.assertTrue(strings.contains($doc, "numFmtId=\"164\""));
    testing.assertTrue(strings.contains($doc, "formatCode=\"#,##0.000\""));
    # Excel ignores a property the xf does not claim to apply.
    testing.assertTrue(strings.contains($doc, "applyFill=\"1\""));
    testing.assertTrue(strings.contains($doc, "applyNumberFormat=\"1\""));
}

func testStylesCrossBetweenTheFormats() {
    def s as Sheet init sheetOf("S", [[text("x")]]);
    $s = setStyle($s, "A1", fixtureStyle());
    def viaOds as Workbook init readOds(writeOds(addSheet(newWorkbook(), $s)));
    def andBack as Workbook init readXlsx(writeXlsx($viaOds));
    def got as Style init styleAt(sheetByName($andBack, "S"), "A1");
    # Everything but the exact format code, which ODF cannot carry verbatim.
    assertStyleSurvived($got, fixtureStyle(), false);
}

func testXlsxKeepsColumnWidthsAndFrozenPanes() {
    def s as Sheet init sheetOf("S", [[text("a"), text("b"), text("c")]]);
    $s = setColumnWidth($s, "A", 30.0);
    $s = setColumnWidth($s, "C", 8.25);
    $s = freezePanes($s, 1, 1);
    def raw as bytes init writeXlsx(addSheet(newWorkbook(), $s));
    def doc as string init encoding.decode("utf-8", unzip($raw)["xl/worksheets/sheet1.xml"]);
    # The schema's order, or Excel repairs the file.
    testing.assertTrue(strings.indexOf($doc, "<sheetViews>") < strings.indexOf($doc, "<cols>"));
    testing.assertTrue(strings.indexOf($doc, "<cols>") < strings.indexOf($doc, "<sheetData>"));
    def back as Sheet init sheetByName(readXlsx($raw), "S");
    testing.assertEqual($back.layout, $s.layout);
}

func testOdsKeepsColumnWidthsAndFrozenPanes() {
    def s as Sheet init sheetOf("S", [[text("a"), text("b"), text("c")]]);
    $s = setColumnWidth($s, "B", 30.0);
    $s = setColumnWidth($s, "C", 8.25);
    $s = freezePanes($s, 2, 0);
    def raw as bytes init writeOds(addSheet(newWorkbook(), $s));
    testing.assertTrue(maps.has(unzip($raw), "settings.xml"));
    def back as Sheet init sheetByName(readOds($raw), "S");
    testing.assertEqual($back.layout, $s.layout);
}

func testAnUnfrozenOdsHasNoSettingsPart() {
    def raw as bytes init writeOds(addSheet(newWorkbook(), sheetOf("S", [[text("a")]])));
    testing.assertFalse(maps.has(unzip($raw), "settings.xml"));
}
