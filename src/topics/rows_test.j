# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

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
        encoding.encode(
            "utf-8",
            "<workbook xmlns:r=\"r\"><sheets><sheet name=\"S\" r:id=\"rId1\"/>" +
                "</sheets></workbook>"));
    $members[] = member(
        "xl/_rels/workbook.xml.rels",
        encoding.encode(
            "utf-8",
            "<Relationships><Relationship Id=\"rId1\" " +
                "Target=\"worksheets/sheet1.xml\"/></Relationships>"));
    $members[] = member(
        "xl/worksheets/sheet1.xml",
        encoding.encode(
            "utf-8",
            "<worksheet><sheetData>" +
                "<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>" +
                "<row r=\"7\"><c r=\"A7\"><v>7</v></c></row>" +
                "</sheetData></worksheet>"));
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
        encoding.encode(
            "utf-8",
            "<workbook xmlns:r=\"r\"><sheets><sheet name=\"S\" r:id=\"rId1\"/>" +
                "</sheets></workbook>"));
    $members[] = member(
        "xl/_rels/workbook.xml.rels",
        encoding.encode(
            "utf-8",
            "<Relationships><Relationship Id=\"rId1\" " +
                "Target=\"worksheets/sheet1.xml\"/></Relationships>"));
    $members[] = member(
        "xl/worksheets/sheet1.xml",
        encoding.encode(
            "utf-8",
            "<worksheet><sheetData><row r=\"1\">" +
                "<c r=\"A1\"><v>1</v></c><c r=\"D1\"><v>4</v></c>" +
                "</row></sheetData></worksheet>"));
    def r as RowReader init openRowsFromBytes(zip($members), Format.Xlsx, "S");
    $r = nextRow($r);
    def values as list of Value init rowValues($r);
    testing.assertEqual(len($values), 4);
    testing.assertEqual(asNumber($values[0]), 1.0);
    testing.assertTrue(isEmpty($values[1]));
    testing.assertTrue(isEmpty($values[2]));
    testing.assertEqual(asNumber($values[3]), 4.0);
}

func testTheCursorReadsRowsWithExtensionAttributes() {
    # Excel 2010 and later declare x14ac on <worksheet> and write
    # x14ac:dyDescent on nearly every row, so a row decoded on its own must
    # still see the declaration.
    def members as list of Member init [];
    $members[] = member(
        "xl/workbook.xml",
        encoding.encode(
            "utf-8",
            "<workbook xmlns:r=\"r\"><sheets><sheet name=\"S\" r:id=\"rId1\"/>" +
                "</sheets></workbook>"));
    $members[] = member(
        "xl/_rels/workbook.xml.rels",
        encoding.encode(
            "utf-8",
            "<Relationships><Relationship Id=\"rId1\" " +
                "Target=\"worksheets/sheet1.xml\"/></Relationships>"));
    $members[] = member(
        "xl/worksheets/sheet1.xml",
        encoding.encode(
            "utf-8",
            "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" " +
                "xmlns:mc=\"http://schemas.openxmlformats.org/markup-compatibility/2006\" " +
                "xmlns:x14ac=\"http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac\" " +
                "mc:Ignorable=\"x14ac\"><sheetData>" +
                "<row r=\"1\" spans=\"1:2\" x14ac:dyDescent=\"0.35\">" +
                "<c r=\"A1\"><v>1</v></c><c r=\"B1\"><v>2</v></c></row>" +
                "</sheetData></worksheet>"));
    def r as RowReader init openRowsFromBytes(zip($members), Format.Xlsx, "S");
    $r = nextRow($r);
    def values as list of Value init rowValues($r);
    testing.assertEqual(len($values), 2);
    testing.assertEqual(asNumber($values[1]), 2.0);
    testing.assertFalse(hasRow($r));
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
    openRowsFromBytes(encoding.encode("utf-8", "nope"), Format.Xlsx, "");
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

/**
 * A string made of a piece repeated.
 *
 * @param piece {string} the piece
 * @param times {int} how many times
 * @return {string} the pieces joined
 */
func repeatedText(piece as string, times as int) {
    def out as string init "";
    def chunk as string init $piece;
    def n as int init $times;
    while ($n > 0) {
        if ($n % 2 == 1) {
            $out = $out + $chunk;
        }
        $chunk = $chunk + $chunk;
        $n = $n // 2;
    }
    return $out;
}

/**
 * An XLSX container around one sheet's `<sheetData>` content.
 *
 * @param rowsMarkup {string} the rows
 * @return {bytes} the file
 */
func xlsxAroundRows(rowsMarkup as string) {
    def members as list of Member init [];
    $members[] = member(
        "xl/workbook.xml",
        encoding.encode(
            "utf-8",
            "<workbook xmlns:r=\"r\"><sheets><sheet name=\"S\" r:id=\"rId1\"/>" +
                "</sheets></workbook>"));
    $members[] = member(
        "xl/_rels/workbook.xml.rels",
        encoding.encode(
            "utf-8",
            "<Relationships><Relationship Id=\"rId1\" " +
                "Target=\"worksheets/sheet1.xml\"/></Relationships>"));
    $members[] = member(
        "xl/worksheets/sheet1.xml",
        encoding.encode(
            "utf-8",
            "<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">" +
                "<sheetData>" + $rowsMarkup + "</sheetData></worksheet>"));
    return zip($members);
}

/**
 * Whether a sheet streams to the same rows the whole read gives.
 *
 * @param raw {bytes} the file
 * @param kind {Format} the format
 */
func assertStreamMatchesWholeRead(raw as bytes, kind as Format) {
    def streamed as list of list of string init streamRows($raw, $kind, "");
    def s as Sheet init readFormat($raw, $kind).sheets[0];
    testing.assertEqual(len($streamed), $s.rowCount);
    for (def i in 0..len($streamed)) {
        def whole as list of Value init row($s, $i);
        testing.assertEqual(len($streamed[$i]), len(trimTrailingEmpty($whole)));
        for (def c in 0..len($streamed[$i])) {
            testing.assertEqual($streamed[$i][$c], asString($whole[$c]));
        }
    }
}

func testTheCursorReadsAcrossWindowRefills() {
    # Over a megabyte of rows, so the window is refilled several times: cuts
    # land inside rows, tags, comments and multi-byte characters, and one row
    # is longer than a window on its own.
    def parts as list of string init [];
    for (def i in 1..9) {
        def body as string init repeatedText("ä€x" + convert.toString($i), 12000 + $i * 997);
        $parts[] = "<row r=\"" + convert.toString($i) + "\"><c r=\"A" + convert.toString($i) +
            "\"><v>" + convert.toString($i) + "</v></c><c r=\"C" + convert.toString($i) +
            "\" t=\"inlineStr\"><is><t>" + $body + "</t></is></c></row>";
        $parts[] = "<!--" + repeatedText("-x", 3001) + "-->";
    }
    $parts[] = "<row r=\"9\"><c r=\"B9\" t=\"inlineStr\"><is><t>" +
        repeatedText("ü", ROW_WINDOW * 2 + 17) + "</t></is></c></row>";
    $parts[] = "<row r=\"10\"><c r=\"A10\" t=\"b\"><v>1</v></c></row>";
    assertStreamMatchesWholeRead(xlsxAroundRows(strings.join($parts, "")), Format.Xlsx);
}

func testTheOdsCursorReadsAcrossWindowRefills() {
    def lines as list of list of Value init [];
    for (def i in 0..12) {
        $lines[] = [number($i * 1.0), text(repeatedText("ö" + convert.toString($i), 25000 + $i))];
    }
    def raw as bytes init writeOds(addSheet(newWorkbook(), sheetOf("S", $lines)));
    assertStreamMatchesWholeRead($raw, Format.Ods);
}

func testTheWindowStaysBoundedOnALongSheet() {
    # The cursor is copied for every row by a caller that keeps it in a
    # top-level variable, so it must not carry the whole sheet as bytes.
    def parts as list of string init [];
    for (def i in 1..2001) {
        $parts[] = "<row r=\"" + convert.toString($i) + "\"><c t=\"inlineStr\"><is><t>" +
            repeatedText("y", 500) + "</t></is></c></row>";
    }
    def r as RowReader init openRowsFromBytes(
        xlsxAroundRows(strings.join($parts, "")),
        Format.Xlsx,
        "");
    def rowsRead as int init 0;
    def widest as int init 0;
    while (hasRow($r)) {
        $r = nextRow($r);
        $rowsRead = $rowsRead + 1;
        if (len($r.src) > $widest) {
            $widest = len($r.src);
        }
    }
    testing.assertEqual($rowsRead, 2000);
    testing.assertTrue($widest <= ROW_WINDOW + 2000);
}

/**
 * The best of three times for streaming every row of a file.
 *
 * @param raw {bytes} the file
 * @return {int} nanoseconds
 */
func bestStreamNanos(raw as bytes) {
    def best as int init -1;
    for (def round in 0..3) {
        def t0 as time.Time init time.now();
        def r as RowReader init openRowsFromBytes($raw, Format.Xlsx, "");
        while (hasRow($r)) {
            $r = nextRow($r);
        }
        def took as int init time.sub(time.now(), $t0).nanos;
        if ($best < 0 or $took < $best) {
            $best = $took;
        }
    }
    return $best;
}

/**
 * A sheet of short rows, each padded with a comment so the sheet is large
 * next to the work of decoding a row.
 *
 * @param count {int} the rows
 * @return {bytes} the file
 */
func paddedRows(count as int) {
    def pad as string init "<!--" + repeatedText("z", 4000) + "-->";
    def parts as list of string init [];
    for (def i in 1..$count + 1) {
        $parts[] = "<row r=\"" + convert.toString($i) + "\"><c><v>" + convert.toString($i) +
            "</v></c>" + $pad + "</row>";
    }
    return xlsxAroundRows(strings.join($parts, ""));
}

func testStreamingTimeGrowsLinearlyWithTheRows() {
    # A cost per row that grows with the sheet (a copy of the sheet's bytes
    # for every row) makes twice the rows take four times as long.
    def once as int init bestStreamNanos(paddedRows(300));
    def twice as int init bestStreamNanos(paddedRows(600));
    testing.assertTrue($twice < $once * 5 // 2);
}
