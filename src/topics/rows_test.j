# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for rows.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# The cursor has to agree with the whole-workbook readers cell for cell, in
# every format, or a caller who switches to streaming silently gets different
# data. That agreement is what most of these check.

/**
 * Every row of a sheet, read through the cursor.
 *
 * @param raw {bytes} the file
 * @param kind {Format} the format
 * @param sheetName {string} the sheet to walk
 * @return {list of list of string} each row rendered as text
 */
func streamRows(raw as bytes, kind as Format, sheetName as string) {
    def out as list of list of string init [];
    def r as RowReader init openRowsFromBytes($raw, $kind, $sheetName);
    while (hasRow($r)) {
        $r = nextRow($r);
        $out[] = rowStrings($r);
    }
    return $out;
}

func testStreamingOdsAgreesWithTheWholeRead() {
    def raw as bytes init writeOds(fixtureWorkbook());
    def streamed as list of list of string init streamRows($raw, Format.Ods, "Sheet1");
    def s as Sheet init sheetByName(readOds($raw), "Sheet1");
    testing.assertEqual(len($streamed), $s.rowCount);
    for (def i in 0..len($streamed)) {
        def whole as list of string init [];
        for (def v in row($s, $i)) {
            $whole[] = asString($v);
        }
        # The cursor trims trailing empties; the whole read pads to the width.
        for (def c in 0..len($streamed[$i])) {
            testing.assertEqual($streamed[$i][$c], $whole[$c]);
        }
    }
}

func testStreamingXlsxAgreesWithTheWholeRead() {
    def raw as bytes init writeXlsx(fixtureWorkbook());
    def streamed as list of list of string init streamRows($raw, Format.Xlsx, "Sheet1");
    def s as Sheet init sheetByName(readXlsx($raw), "Sheet1");
    testing.assertEqual(len($streamed), $s.rowCount);
    for (def i in 0..len($streamed)) {
        def whole as list of string init [];
        for (def v in row($s, $i)) {
            $whole[] = asString($v);
        }
        for (def c in 0..len($streamed[$i])) {
            testing.assertEqual($streamed[$i][$c], $whole[$c]);
        }
    }
}

func testTheCursorReadsValuesNotJustText() {
    def raw as bytes init writeXlsx(fixtureWorkbook());
    def r as RowReader init openRowsFromBytes($raw, Format.Xlsx, "Sheet1");
    $r = nextRow($r);
    $r = nextRow($r);
    def values as list of Value init rowValues($r);
    testing.assertEqual(asString($values[0]), "Widget & Co");
    testing.assertEqual(kindOf($values[1]), "number");
    testing.assertEqual(asNumber($values[2]), 9.99);
}

func testTheCursorKeepsAFormulaAFormula() {
    def raw as bytes init writeXlsx(fixtureWorkbook());
    def r as RowReader init openRowsFromBytes($raw, Format.Xlsx, "Sheet1");
    for (def i in 0..3) {
        $r = nextRow($r);
    }
    def v as Value init rowValues($r)[2];
    match ($v) {
        when Formula(f) { testing.assertEqual($f.source, "B3*C2"); }
        else {
            throw Error{
                kind: "test",
                message: "row 3 column C is not a formula but a " + kindOf($v),
                file: "",
                line: 0,
                col: 0
            };
        }
    }
}

func testRowNumberFollowsTheSheetNotTheCount() {
    # An XLSX sheet writes only the rows it has, so a gap must be reported.
    def members as list of Member init [];
    $members[] = member(
        "xl/workbook.xml",
        convert.bytesFromString(
            "<workbook xmlns:r=\"r\"><sheets><sheet name=\"S\" r:id=\"rId1\"/>" +
                "</sheets></workbook>",
            "utf-8"));
    $members[] = member(
        "xl/_rels/workbook.xml.rels",
        convert.bytesFromString(
            "<Relationships><Relationship Id=\"rId1\" " +
                "Target=\"worksheets/sheet1.xml\"/></Relationships>",
            "utf-8"));
    $members[] = member(
        "xl/worksheets/sheet1.xml",
        convert.bytesFromString(
            "<worksheet><sheetData>" +
                "<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>" +
                "<row r=\"7\"><c r=\"A7\"><v>7</v></c></row>" +
                "</sheetData></worksheet>",
            "utf-8"));
    def r as RowReader init openRowsFromBytes(zip($members), Format.Xlsx, "S");
    $r = nextRow($r);
    testing.assertEqual(rowNumber($r), 1);
    $r = nextRow($r);
    testing.assertEqual(rowNumber($r), 7);
    testing.assertFalse(hasRow($r));
}

func testTheCursorFillsAGapWithinARow() {
    def members as list of Member init [];
    $members[] = member(
        "xl/workbook.xml",
        convert.bytesFromString(
            "<workbook xmlns:r=\"r\"><sheets><sheet name=\"S\" r:id=\"rId1\"/>" +
                "</sheets></workbook>",
            "utf-8"));
    $members[] = member(
        "xl/_rels/workbook.xml.rels",
        convert.bytesFromString(
            "<Relationships><Relationship Id=\"rId1\" " +
                "Target=\"worksheets/sheet1.xml\"/></Relationships>",
            "utf-8"));
    $members[] = member(
        "xl/worksheets/sheet1.xml",
        convert.bytesFromString(
            "<worksheet><sheetData><row r=\"1\">" +
                "<c r=\"A1\"><v>1</v></c><c r=\"D1\"><v>4</v></c>" +
                "</row></sheetData></worksheet>",
            "utf-8"));
    def r as RowReader init openRowsFromBytes(zip($members), Format.Xlsx, "S");
    $r = nextRow($r);
    def values as list of Value init rowValues($r);
    testing.assertEqual(len($values), 4);
    testing.assertEqual(asNumber($values[0]), 1.0);
    testing.assertTrue(isEmpty($values[1]));
    testing.assertTrue(isEmpty($values[2]));
    testing.assertEqual(asNumber($values[3]), 4.0);
}

func testAnEmptySheetNameTakesTheFirstSheet() {
    def raw as bytes init writeOds(fixtureWorkbook());
    def r as RowReader init openRowsFromBytes($raw, Format.Ods, "");
    $r = nextRow($r);
    testing.assertEqual(rowStrings($r)[0], "Name");
}

func testTheCursorWalksTheSecondSheetToo() {
    def raw as bytes init writeXlsx(fixtureWorkbook());
    def rowsRead as list of list of string init streamRows($raw, Format.Xlsx, "Second Sheet");
    testing.assertEqual(len($rowsRead), 1);
    testing.assertEqual($rowsRead[0][0], "hello");
}

func testEveryFormatCanBeStreamed() {
    # Gnumeric and delimited text do not reward streaming, but they accept the
    # same loop so a caller need not branch.
    def wb as Workbook init fixtureWorkbook();
    for (def kind in [Format.Ods, Format.Xlsx, Format.Gnumeric, Format.Csv, Format.Tsv]) {
        def rowsRead as list of list of string init streamRows(writeFormat($wb, $kind), $kind, "");
        testing.assertTrue(len($rowsRead) >= 1);
        testing.assertEqual($rowsRead[0][0], "Name");
    }
}

func testTrailingEmptyCellsAreTrimmed() {
    def s as Sheet init newSheet("S");
    $s = setCell($s, "A1", text("a"));
    $s = setCell($s, "D3", text("d"));
    def raw as bytes init writeXlsx(addSheet(newWorkbook(), $s));
    def r as RowReader init openRowsFromBytes($raw, Format.Xlsx, "S");
    $r = nextRow($r);
    # Row 1 holds only A1, so the row is one wide rather than four.
    testing.assertEqual(len(rowValues($r)), 1);
}

func failOnReadingPastTheLastRow() {
    def r as RowReader init openRowsFromBytes(
        writeXlsx(fixtureWorkbook()),
        Format.Xlsx,
        "Second Sheet");
    $r = nextRow($r);
    $r = nextRow($r);
}

func testReadingPastTheLastRowIsRefused() {
    testing.assertThrows("failOnReadingPastTheLastRow", ERROR_KIND);
}

func failOnStreamingAMissingSheet() {
    openRowsFromBytes(writeXlsx(fixtureWorkbook()), Format.Xlsx, "Nope");
}

func failOnStreamingAMissingOdsSheet() {
    openRowsFromBytes(writeOds(fixtureWorkbook()), Format.Ods, "Nope");
}

func failOnStreamingSomethingThatIsNotAContainer() {
    openRowsFromBytes(convert.bytesFromString("nope", "utf-8"), Format.Xlsx, "");
}

func testTheCursorRefusesWhatItCannotOpen() {
    testing.assertThrows("failOnStreamingAMissingSheet", ERROR_KIND);
    testing.assertThrows("failOnStreamingAMissingOdsSheet", ERROR_KIND);
    testing.assertThrows("failOnStreamingSomethingThatIsNotAContainer", ERROR_KIND);
}

func failOnStreamingAMissingFile() {
    openRows("definitely-not-here.xlsx", "");
}

func testOpenRowsRefusesAMissingFile() {
    testing.assertThrows("failOnStreamingAMissingFile", ERROR_KIND);
}
