# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# sheets - tests for xlsxread.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * Build an XLSX container by hand, part by part.
 *
 * A reader has to cope with what other writers produce, not just with what
 * this deck writes, so these fixtures are assembled directly rather than
 * going through `writeXlsx`.
 *
 * @param parts {map of string to string} the member paths and their contents
 * @return {bytes} the container
 */
func xlsxContainer(parts as map of string to string) {
    def members as list of Member init [];
    for (def path in $parts) {
        $members[] = member($path, encoding.encode("utf-8", $parts[$path]));
    }
    return zip($members);
}

/**
 * A one-sheet container around the given `<sheetData>` contents.
 *
 * @param rows {string} the `<row>` elements
 * @return {bytes} the container
 */
func xlsxOneSheet(rows as string) {
    return xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns=\"" +
            "http://schemas.openxmlformats.org/spreadsheetml/2006/main\"" +
            " xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/" +
            "relationships\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\"" +
            " r:id=\"rId1\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships xmlns=\"" +
            "http://schemas.openxmlformats.org/package/2006/relationships\">" +
            "<Relationship Id=\"rId1\" Type=\"x\" Target=\"worksheets/sheet1.xml\"/>" +
            "</Relationships>",
        "xl/worksheets/sheet1.xml": "<worksheet xmlns=\"" +
            "http://schemas.openxmlformats.org/spreadsheetml/2006/main\">" +
            "<sheetData>" + $rows + "</sheetData></worksheet>"
    });
}

func testReadXlsxReadsSheetNamesInWorkbookOrder() {
    # The part names run sheet1, sheet2, but nothing says the tabs do.
    def wb as Workbook init readXlsx(xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><sheets>" +
            "<sheet name=\"Second\" sheetId=\"2\" r:id=\"rIdB\"/>" +
            "<sheet name=\"First\" sheetId=\"1\" r:id=\"rIdA\"/>" +
            "</sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships>" +
            "<Relationship Id=\"rIdA\" Target=\"worksheets/sheet1.xml\"/>" +
            "<Relationship Id=\"rIdB\" Target=\"worksheets/sheet2.xml\"/>" +
            "</Relationships>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\">" +
            "<c r=\"A1\" t=\"inlineStr\"><is><t>a</t></is></c></row></sheetData>" +
            "</worksheet>",
        "xl/worksheets/sheet2.xml": "<worksheet><sheetData><row r=\"1\">" +
            "<c r=\"A1\" t=\"inlineStr\"><is><t>b</t></is></c></row></sheetData>" +
            "</worksheet>"
    }));
    testing.assertEqual(sheetNames($wb), ["Second", "First"]);
    testing.assertEqual(asString(cell(sheetByName($wb, "Second"), "A1")), "b");
    testing.assertEqual(asString(cell(sheetByName($wb, "First"), "A1")), "a");
}

func testReadsASharedString() {
    def wb as Workbook init readXlsx(xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><sheets>" +
            "<sheet name=\"S\" r:id=\"rId1\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships>" +
            "<Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\"/>" +
            "<Relationship Id=\"rId2\" Target=\"sharedStrings.xml\"/></Relationships>",
        "xl/sharedStrings.xml": "<sst><si><t>Widget &amp; Co</t></si>" +
            "<si><t>second</t></si></sst>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\">" +
            "<c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c>" +
            "</row></sheetData></worksheet>"
    }));
    def s as Sheet init sheetByName($wb, "S");
    testing.assertEqual(asString(cell($s, "A1")), "Widget & Co");
    testing.assertEqual(asString(cell($s, "B1")), "second");
}

func testASharedStringSplitIntoRunsIsJoined() {
    # A partly-formatted label is stored as several <r> runs; taking the first
    # would truncate it.
    def wb as Workbook init readXlsx(xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><sheets>" +
            "<sheet name=\"S\" r:id=\"rId1\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships>" +
            "<Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\"/>" +
            "<Relationship Id=\"rId2\" Target=\"sharedStrings.xml\"/></Relationships>",
        "xl/sharedStrings.xml": "<sst><si><r><t>Hello</t></r>" +
            "<r><rPr><b/></rPr><t> bold</t></r><r><t> world</t></r></si></sst>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\">" +
            "<c r=\"A1\" t=\"s\"><v>0</v></c></row></sheetData></worksheet>"
    }));
    testing.assertEqual(asString(cell(sheetByName($wb, "S"), "A1")), "Hello bold world");
}

func testAnOutOfRangeSharedStringIndexIsEmptyRatherThanFatal() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\" t=\"s\"><v>99</v></c></row>"));
    testing.assertTrue(isEmpty(cell(sheetByName($wb, "Sheet1"), "A1")));
}

func testReadsAnInlineString() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is><t>inline</t></is></c></row>"));
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "A1")), "inline");
}

func testReadsNumbersBooleansAndErrors() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\">" +
        "<c r=\"A1\"><v>9.99</v></c>" +
        "<c r=\"B1\" t=\"b\"><v>1</v></c>" +
        "<c r=\"C1\" t=\"b\"><v>0</v></c>" +
        "<c r=\"D1\" t=\"e\"><v>#DIV/0!</v></c>" +
        "<c r=\"E1\" t=\"str\">" + "<v>text result</v></c>" +
        "</row>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asNumber(cell($s, "A1")), 9.99);
    testing.assertTrue(asBool(cell($s, "B1")));
    testing.assertFalse(asBool(cell($s, "C1")));
    testing.assertEqual(kindOf(cell($s, "D1")), "error");
    testing.assertEqual(asString(cell($s, "D1")), "#DIV/0!");
    testing.assertEqual(asString(cell($s, "E1")), "text result");
}

func testReadsAnIsoDateCell() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\" t=\"d\"><v>2026-10-02</v></c></row>"));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "A1");
    testing.assertEqual(kindOf($v), "stamp");
    testing.assertEqual(time.format(asTime($v), "%Y-%m-%d"), "2026-10-02");
}

func testReadsAFormulaWithItsCachedResult() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\"><f>B3*C2</f><v>19.98</v></c></row>"));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "A1");
    match ($v) {
        when Formula(f) {
            testing.assertEqual($f.source, "B3*C2");
            testing.assertEqual($f.cached, "19.98");
        }
        else { throw Error{kind: "test", message: "not a formula", file: "", line: 0, col: 0}; }
    }
}

func testAFormulaKeepsItsA1SpellingUntranslated() {
    # XLSX already stores A1, which is the model's dialect, so nothing should
    # happen to the expression on the way in.
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\"><f>SUM(A1:A5)+Sheet2!B1</f><v>1</v></c></row>"));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "A1");
    match ($v) {
        when Formula(f) { testing.assertEqual($f.source, "SUM(A1:A5)+Sheet2!B1"); }
        else { throw Error{kind: "test", message: "not a formula", file: "", line: 0, col: 0}; }
    }
}

func testTheCellReferenceDecidesThePositionNotTheOrder() {
    # A row writes only its non-empty cells, so trusting position would close
    # up every gap.
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\"><v>1</v></c><c r=\"D1\"><v>4</v></c></row>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asNumber(cell($s, "A1")), 1.0);
    testing.assertTrue(isEmpty(cell($s, "B1")));
    testing.assertTrue(isEmpty(cell($s, "C1")));
    testing.assertEqual(asNumber(cell($s, "D1")), 4.0);
}

func testTheRowAttributeDecidesTheRow() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>" +
        "<row r=\"5\"><c r=\"A5\"><v>5</v></c></row>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asNumber(cell($s, "A1")), 1.0);
    testing.assertEqual(asNumber(cell($s, "A5")), 5.0);
    testing.assertEqual($s.rowCount, 5);
    testing.assertEqual(cellCount($s), 2);
}

func testARowWithNoAttributeFallsBackToItsPosition() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row><c><v>1</v></c></row><row><c><v>2</v></c></row>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asNumber(cell($s, "A1")), 1.0);
    testing.assertEqual(asNumber(cell($s, "A2")), 2.0);
}

func testANumberIsADateOnlyWhenItsStyleSaysSo() {
    # The whole of XLSX date handling: the number is identical, and only the
    # style tells them apart.
    def wb as Workbook init readXlsx(xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><sheets>" +
            "<sheet name=\"S\" r:id=\"rId1\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships>" +
            "<Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\"/>" +
            "<Relationship Id=\"rId2\" Target=\"styles.xml\"/></Relationships>",
        "xl/styles.xml": "<styleSheet>" +
            "<numFmts><numFmt numFmtId=\"164\" formatCode=\"dd/mm/yyyy\"/>" +
            "<numFmt numFmtId=\"165\" formatCode=\"#,##0.00&quot;kg&quot;\"/>" +
            "</numFmts><cellXfs>" +
            "<xf numFmtId=\"0\"/><xf numFmtId=\"14\"/><xf numFmtId=\"164\"/>" +
            "<xf numFmtId=\"4\"/><xf numFmtId=\"165\"/><xf numFmtId=\"46\"/>" +
            "</cellXfs></styleSheet>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\">" +
            "<c r=\"A1\" s=\"0\"><v>46297</v></c>" +
            "<c r=\"B1\" s=\"1\"><v>46297</v></c>" +
            "<c r=\"C1\" s=\"2\"><v>46297</v></c>" +
            "<c r=\"D1\" s=\"3\"><v>46297</v></c>" +
            "<c r=\"E1\" s=\"4\"><v>46297</v></c>" +
            "<c r=\"F1\" s=\"5\"><v>46297</v></c>" +
            "</row></sheetData></worksheet>"
    }));
    def s as Sheet init sheetByName($wb, "S");
    # General, a plain numeric format, and a currency-ish custom format stay numbers.
    testing.assertEqual(kindOf(cell($s, "A1")), "number");
    testing.assertEqual(kindOf(cell($s, "D1")), "number");
    testing.assertEqual(kindOf(cell($s, "E1")), "number");
    # Built-in 14, a custom date code, and built-in 46 (elapsed time) are dates.
    testing.assertEqual(kindOf(cell($s, "B1")), "stamp");
    testing.assertEqual(kindOf(cell($s, "C1")), "stamp");
    testing.assertEqual(kindOf(cell($s, "F1")), "stamp");
    testing.assertEqual(time.format(asTime(cell($s, "B1")), "%Y-%m-%d"), "2026-10-02");
}

func testALooksLikeDateFormatIgnoresQuotedLiterals() {
    # A currency symbol inside quotes must not make a format a date.
    testing.assertFalse(looksLikeDateFormat("#,##0.00"));
    testing.assertFalse(looksLikeDateFormat("0.00\"kg\""));
    testing.assertFalse(looksLikeDateFormat("[$-409]#,##0"));
    testing.assertTrue(looksLikeDateFormat("yyyy-mm-dd"));
    testing.assertTrue(looksLikeDateFormat("dd/mm/yy"));
    testing.assertTrue(looksLikeDateFormat("hh:mm:ss"));
}

func testTheDate1904FlagIsRead() {
    def wb as Workbook init readXlsx(xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><workbookPr date1904=\"1\"/>" +
            "<sheets><sheet name=\"S\" r:id=\"rId1\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships>" +
            "<Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\"/>" +
            "</Relationships>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\">" +
            "<c r=\"A1\"><v>1</v></c></row></sheetData></worksheet>"
    }));
    testing.assertTrue($wb.date1904);
}

func testAnAbsentRelationshipPartStillReadsBySuffix() {
    # A hand-written file may omit the relationship part; the member names are
    # then the only thing to go on.
    def wb as Workbook init readXlsx(xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><sheets>" +
            "<sheet name=\"S\" r:id=\"rId1\"/></sheets></workbook>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\">" +
            "<c r=\"A1\" t=\"inlineStr\"><is><t>x</t></is></c></row></sheetData>" +
            "</worksheet>"
    }));
    # The sheet part cannot be resolved without the relationship, so the sheet
    # is present but empty rather than the file being refused.
    testing.assertEqual(sheetNames($wb), ["S"]);
    testing.assertEqual(cellCount(sheetByName($wb, "S")), 0);
}

func testASheetNamingAMissingPartIsEmptyNotFatal() {
    def wb as Workbook init readXlsx(xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><sheets>" +
            "<sheet name=\"Here\" r:id=\"rId1\"/>" +
            "<sheet name=\"Gone\" r:id=\"rId2\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships>" +
            "<Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\"/>" +
            "<Relationship Id=\"rId2\" Target=\"worksheets/missing.xml\"/>" +
            "</Relationships>",
        "xl/worksheets/sheet1.xml": "<worksheet><sheetData><row r=\"1\">" +
            "<c r=\"A1\" t=\"inlineStr\"><is><t>x</t></is></c></row></sheetData>" +
            "</worksheet>"
    }));
    testing.assertEqual(sheetNames($wb), ["Here", "Gone"]);
    testing.assertEqual(asString(cell(sheetByName($wb, "Here"), "A1")), "x");
    testing.assertEqual(cellCount(sheetByName($wb, "Gone")), 0);
}

func testACellWithNoValueIsEmpty() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\" s=\"0\"/><c r=\"B1\"><v>2</v></c></row>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertTrue(isEmpty(cell($s, "A1")));
    testing.assertEqual(asNumber(cell($s, "B1")), 2.0);
}

func testAnUnreadableNumberFallsBackToItsText() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\"><v>not a number</v></c></row>"));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "A1");
    testing.assertEqual(kindOf($v), "text");
    testing.assertEqual(asString($v), "not a number");
}

func testResolveXlPathHandlesEveryTargetShape() {
    testing.assertEqual(resolveXlPath("worksheets/sheet1.xml"), "xl/worksheets/sheet1.xml");
    testing.assertEqual(resolveXlPath("xl/worksheets/sheet1.xml"), "xl/worksheets/sheet1.xml");
    testing.assertEqual(resolveXlPath("/xl/styles.xml"), "xl/styles.xml");
}

func failOnXlsxWithNoWorkbookPart() {
    readXlsx(xlsxContainer({"xl/worksheets/sheet1.xml": "<worksheet/>"}));
}

func failOnXlsxThatIsNotAContainer() {
    readXlsx(encoding.encode("utf-8", "not a zip"));
}

func failOnWorkbookListingNoSheets() {
    readXlsx(xlsxContainer({"xl/workbook.xml": "<workbook><sheets/></workbook>"}));
}

func testReadXlsxRefusesWhatIsNotAWorkbook() {
    testing.assertThrows("failOnXlsxWithNoWorkbookPart", ERROR_KIND);
    testing.assertThrows("failOnXlsxThatIsNotAContainer", ERROR_KIND);
    testing.assertThrows("failOnWorkbookListingNoSheets", ERROR_KIND);
}

func testAnOffGridRowNumberIsDroppedNotBelieved() {
    # A file may claim any row number. Believing r="999999999999" made it the
    # sheet's extent, after which any caller walking the sheet looped about a
    # trillion times - a denial of service out of a 657-byte file.
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"999999999999\"><c r=\"A999999999999\"><v>1</v></c></row>" +
        "<row r=\"1\"><c r=\"A1\"><v>7</v></c></row>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertTrue($s.rowCount <= MAX_ROW + 1);
    testing.assertEqual(asNumber(cell($s, "A1")), 7.0);
}

func testAnOffGridColumnIsDroppedToo() {
    def wb as Workbook init readXlsx(xlsxOneSheet("<row r=\"1\"><c r=\"A1\"><v>1</v></c></row>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertTrue($s.colCount <= MAX_COLUMN + 1);
}

/**
 * A one-sheet container around a whole worksheet part.
 *
 * @param worksheet {string} the worksheet part
 * @return {bytes} the container
 */
func oneWorksheetContainer(worksheet as string) {
    return xlsxContainer({
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><sheets>" +
            "<sheet name=\"S\" r:id=\"rId1\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships>" +
            "<Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
        "xl/worksheets/sheet1.xml": $worksheet
    });
}

/**
 * The first row of a sheet, as both readers see it.
 *
 * @param raw {bytes} the container
 * @return {list of list of Value} the whole read's row, then the cursor's
 */
func firstRowBothWays(raw as bytes) {
    def whole as list of Value init rows(sheetByName(readXlsx($raw), "S"))[0];
    def r as RowReader init openRowsFromBytes($raw, Format.Xlsx, "S");
    $r = nextRow($r);
    return [$whole, rowValues($r)];
}

func testExtensionAttributesOnARowAreRead() {
    def both as list of list of Value init firstRowBothWays(oneWorksheetContainer(
        "<worksheet xmlns:x14ac=\"http://schemas.microsoft.com/office/spreadsheetml/2009/9/ac\">" +
            "<sheetData><row r=\"1\" x14ac:dyDescent=\"0.35\">" +
            "<c r=\"A1\"><v>1</v></c><c r=\"B1\" t=\"inlineStr\"><is><t>b</t></is></c>" +
            "</row></sheetData></worksheet>"));
    for (def line in $both) {
        testing.assertEqual($line, [number(1.0), text("b")]);
    }
}

func testAPrefixedWorksheetReadsLikeAPlainOne() {
    # Some writers spell SpreadsheetML with a prefix: every child is matched
    # on its local name.
    def both as list of list of Value init firstRowBothWays(oneWorksheetContainer(
        "<x:worksheet xmlns:x=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">" +
            "<x:sheetData><x:row r=\"1\">" +
            "<x:c r=\"A1\"><x:v>1</x:v></x:c>" +
            "<x:c r=\"B1\" t=\"inlineStr\"><x:is><x:t>b</x:t></x:is></x:c>" +
            "<x:c r=\"C1\"><x:f>A1+1</x:f><x:v>2</x:v></x:c>" +
            "</x:row></x:sheetData></x:worksheet>"));
    for (def line in $both) {
        testing.assertEqual(
            $line,
            [number(1.0), text("b"), Value.Formula{source: "A1+1", cached: "2"}]);
    }
}

func testAnInlineStringSplitIntoRunsIsJoined() {
    def both as list of list of Value init firstRowBothWays(oneWorksheetContainer(
        "<worksheet><sheetData><row r=\"1\"><c r=\"A1\" t=\"inlineStr\"><is>" +
            "<r><t>Hello</t></r><r><rPr><b/></rPr><t> bold</t></r></is></c>" +
            "</row></sheetData></worksheet>"));
    for (def line in $both) {
        testing.assertEqual($line, [text("Hello bold")]);
    }
}

func testARowCutShortStillReadsWhatItHas() {
    # A row that does not decode is walked by the scanner instead, which reads
    # the cells written before the damage.
    def wb as Workbook init readXlsx(oneWorksheetContainer(
        "<worksheet><sheetData><row r=\"1\"><c r=\"A1\"><v>1</v></c>" +
            "<c r=\"B1\"><v>2</v></c></sheetData></worksheet>"));
    def s as Sheet init sheetByName($wb, "S");
    testing.assertEqual(cell($s, "A1"), number(1.0));
    testing.assertEqual(cell($s, "B1"), number(2.0));
}

func testAStyledCellKeepsItsStyleThroughTheIndex() {
    def s as Sheet init sheetOf("S", [[text("a"), text("b"), text("c")]]);
    $s = setStyle($s, "A1", withBold(style(), true));
    $s = setStyle($s, "C1", withBold(style(), true));
    def back as Sheet init sheetByName(readXlsx(writeXlsx(addSheet(newWorkbook(), $s))), "S");
    testing.assertTrue(styleAt($back, "A1").bold);
    testing.assertFalse(styleAt($back, "B1").bold);
    testing.assertTrue(styleAt($back, "C1").bold);
    testing.assertEqual(len($back.styles), len($s.styles));
}

func testExcelColumnRangesAreKeptInsideTheSheet() {
    # Excel gives a run of columns, often to the grid's edge, one <col>.
    def back as Sheet init sheetByName(
        readXlsx(oneWorksheetContainer(
            "<worksheet><cols><col min=\"1\" max=\"1\" width=\"20.5\" customWidth=\"1\"/>" +
                "<col min=\"2\" max=\"16384\" width=\"9.140625\"/></cols><sheetData>" +
                "<row r=\"1\"><c r=\"A1\"><v>1</v></c><c r=\"C1\"><v>3</v></c></row>" +
                "</sheetData></worksheet>")),
        "S");
    testing.assertEqual($back.layout.columnWidths, {"A": 20.5, "B": 9.140625, "C": 9.140625});
}

func testAPlainSplitIsNotAFreeze() {
    def back as Sheet init sheetByName(
        readXlsx(oneWorksheetContainer(
            "<worksheet><sheetViews><sheetView workbookViewId=\"0\">" +
                "<pane xSplit=\"2000\" ySplit=\"1500\" topLeftCell=\"B2\"/>" +
                "</sheetView></sheetViews><sheetData>" +
                "<row r=\"1\"><c r=\"A1\"><v>1</v></c></row></sheetData></worksheet>")),
        "S");
    testing.assertEqual($back.layout.frozenRows, 0);
    testing.assertEqual($back.layout.frozenColumns, 0);
}
