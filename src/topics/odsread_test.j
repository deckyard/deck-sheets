# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for odsread.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * Wrap table markup in the document a reader expects around it.
 *
 * @param tables {string} one or more `<table:table>` elements
 * @return {bytes} a complete `content.xml`
 */
func odsDocument(tables as string) {
    return convert.bytesFromString(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
            "<office:document-content" +
            " xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\"" +
            " xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\"" +
            " xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\"" +
            " office:version=\"1.3\">" +
            "<office:body><office:spreadsheet>" + $tables +
            "</office:spreadsheet></office:body></office:document-content>",
        "utf-8");
}

/**
 * Wrap cell markup in one named table with one row.
 *
 * @param cells {string} one or more `<table:table-cell>` elements
 * @return {bytes} a complete `content.xml`
 */
func odsOneRow(cells as string) {
    return odsDocument("<table:table table:name=\"Sheet1\">" +
        "<table:table-row>" + $cells + "</table:table-row></table:table>");
}

func testReadOdsContentReadsSheetNames() {
    def wb as Workbook init readOdsContent(odsDocument("<table:table table:name=\"First\"><table:table-row>" +
        "<table:table-cell office:value-type=\"string\"><text:p>a</text:p>" +
        "</table:table-cell></table:table-row></table:table>" +
        "<table:table table:name=\"Second Sheet\"><table:table-row>" +
        "<table:table-cell office:value-type=\"string\"><text:p>b</text:p>" +
        "</table:table-cell></table:table-row></table:table>"));
    testing.assertEqual(sheetNames($wb), ["First", "Second Sheet"]);
}

func testAnUnnamedTableGetsAPositionalName() {
    def wb as Workbook init readOdsContent(odsDocument("<table:table><table:table-row><table:table-cell " +
        "office:value-type=\"string\"><text:p>a</text:p>" +
        "</table:table-cell></table:table-row></table:table>"));
    testing.assertEqual(sheetNames($wb), ["Sheet1"]);
}

func testReadsAStringCell() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"string\">" +
        "<text:p>Widget &amp; Co</text:p></table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asString(cell($s, "A1")), "Widget & Co");
    testing.assertEqual(kindOf(cell($s, "A1")), "text");
}

func testReadsAFloatCellFromItsAttributeNotItsText() {
    # The attribute is the machine-readable half: the text is a rendering and
    # may have lost precision or carry a locale's separator.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"float\" office:value=\"9.99\">" +
        "<text:p>9,99 EUR</text:p></table:table-cell>"));
    testing.assertEqual(asNumber(cell(sheetByName($wb, "Sheet1"), "A1")), 9.99);
}

func testReadsAPercentageAndACurrencyAsNumbers() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"percentage\" office:value=\"0.15\">" +
        "<text:p>15%</text:p></table:table-cell>" +
        "<table:table-cell office:value-type=\"currency\" office:value=\"12.5\">" +
        "<text:p>EUR 12.50</text:p></table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asNumber(cell($s, "A1")), 0.15);
    testing.assertEqual(asNumber(cell($s, "B1")), 12.5);
}

func testReadsABooleanCell() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"boolean\" " +
        "office:boolean-value=\"true\"><text:p>TRUE</text:p></table:table-cell>" +
        "<table:table-cell office:value-type=\"boolean\" " +
        "office:boolean-value=\"false\"><text:p>FALSE</text:p></table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertTrue(asBool(cell($s, "A1")));
    testing.assertFalse(asBool(cell($s, "B1")));
}

func testReadsADateCell() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"date\" " +
        "office:date-value=\"2026-10-02\"><text:p>2026-10-02</text:p>" +
        "</table:table-cell>"));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "A1");
    testing.assertEqual(kindOf($v), "stamp");
    testing.assertEqual(time.format(asTime($v), "%Y-%m-%d"), "2026-10-02");
}

func testADateWithATimeKeepsIt() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"date\" " +
        "office:date-value=\"2026-10-02T14:30:00\"><text:p>x</text:p>" +
        "</table:table-cell>"));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "A1");
    testing.assertEqual(time.format(asTime($v), "%Y-%m-%d %H:%M:%S"), "2026-10-02 14:30:00");
    match ($v) {
        when Stamp(st) { testing.assertFalse($st.dateOnly); }
        else { throw Error{kind: "test", message: "not a stamp", file: "", line: 0, col: 0}; }
    }
}

func testReadsATimeOfDayAsAFractionOfADay() {
    # ODS writes a duration, which is the fractional part of a date serial.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"time\" " +
        "office:time-value=\"PT12H00M00S\"><text:p>12:00</text:p>" +
        "</table:table-cell>" +
        "<table:table-cell office:value-type=\"time\" " +
        "office:time-value=\"PT06H30M00S\"><text:p>06:30</text:p>" +
        "</table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asNumber(cell($s, "A1")), 0.5);
    testing.assertEqual(asNumber(cell($s, "B1")), 0.27083333333333331);
}

func testReadsAFormulaAndTranslatesItToA1() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell table:formula=\"of:=[.B3]*[.C2]\" " +
        "office:value-type=\"float\" office:value=\"19.98\">" +
        "<text:p>19.98</text:p></table:table-cell>"));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "A1");
    match ($v) {
        when Formula(f) {
            testing.assertEqual($f.source, "B3*C2");
            testing.assertEqual($f.cached, "19.98");
        }
        else { throw Error{kind: "test", message: "not a formula", file: "", line: 0, col: 0}; }
    }
}

func testReadsAnErrorCode() {
    # ODF has no error type, so an untyped cell whose text reads as a code is
    # the only signal there is.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell><text:p>#DIV/0!</text:p></table:table-cell>" +
        "<table:table-cell><text:p>#N/A</text:p></table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(kindOf(cell($s, "A1")), "error");
    testing.assertEqual(asString(cell($s, "A1")), "#DIV/0!");
    testing.assertEqual(kindOf(cell($s, "B1")), "error");
}

func testAnUntypedCellWithPlainTextIsText() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell><text:p>plain</text:p></table:table-cell>"));
    testing.assertEqual(kindOf(cell(sheetByName($wb, "Sheet1"), "A1")), "text");
}

func testAnEmptyCellStaysEmpty() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell/>" +
        "<table:table-cell office:value-type=\"string\"><text:p>b</text:p>" +
        "</table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertTrue(isEmpty(cell($s, "A1")));
    testing.assertEqual(asString(cell($s, "B1")), "b");
}

func testRepeatedColumnsAdvanceThePosition() {
    # The run-length encoding is how ODS writes a gap. Two repeated empty
    # cells must leave A1 and B1 empty and put the value in C1.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell table:number-columns-repeated=\"2\"/>" +
        "<table:table-cell office:value-type=\"float\" office:value=\"7\">" +
        "<text:p>7</text:p></table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertTrue(isEmpty(cell($s, "A1")));
    testing.assertTrue(isEmpty(cell($s, "B1")));
    testing.assertEqual(asNumber(cell($s, "C1")), 7.0);
}

func testARepeatedValueIsExpandedAcrossTheRun() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"float\" office:value=\"1\" " +
        "table:number-columns-repeated=\"3\"><text:p>1</text:p>" +
        "</table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asNumber(cell($s, "A1")), 1.0);
    testing.assertEqual(asNumber(cell($s, "B1")), 1.0);
    testing.assertEqual(asNumber(cell($s, "C1")), 1.0);
    testing.assertEqual(cellCount($s), 3);
}

func testAHugeEmptyRunDoesNotMaterialiseCells() {
    # A file routinely pads a row to the end of the grid. Expanding that
    # literally would turn a tiny file into millions of cells.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell table:number-columns-repeated=\"16384\"/>"));
    testing.assertEqual(cellCount(sheetByName($wb, "Sheet1")), 0);
}

func testRepeatedRowsAreExpanded() {
    def wb as Workbook init readOdsContent(odsDocument("<table:table table:name=\"Sheet1\">" +
        "<table:table-row table:number-rows-repeated=\"2\">" +
        "<table:table-cell office:value-type=\"string\"><text:p>x</text:p>" +
        "</table:table-cell></table:table-row>" +
        "</table:table>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asString(cell($s, "A1")), "x");
    testing.assertEqual(asString(cell($s, "A2")), "x");
}

func testRowsInsideAHeaderGroupAreStillRows() {
    def wb as Workbook init readOdsContent(odsDocument("<table:table table:name=\"Sheet1\">" +
        "<table:table-header-rows><table:table-row>" +
        "<table:table-cell office:value-type=\"string\"><text:p>head</text:p>" +
        "</table:table-cell></table:table-row></table:table-header-rows>" +
        "<table:table-row><table:table-cell office:value-type=\"string\">" +
        "<text:p>body</text:p></table:table-cell></table:table-row>" +
        "</table:table>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asString(cell($s, "A1")), "head");
    testing.assertEqual(asString(cell($s, "A2")), "body");
}

func testAMultiParagraphCellJoinsWithNewlines() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"string\">" +
        "<text:p>one</text:p><text:p>two</text:p></table:table-cell>"));
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "A1")), "one\ntwo");
}

func testAStyledRunInsideAParagraphIsNotLost() {
    # A styled fragment becomes a <text:span>; taking only the paragraph's own
    # text would drop it.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"string\">" +
        "<text:p>a<text:span>BOLD</text:span>b</text:p></table:table-cell>"));
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "A1")), "aBOLDb");
}

func testRepeatedSpacesAreRestored() {
    # ODS collapses a run of spaces into one element with a count, because XML
    # character data would lose them.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"string\">" +
        "<text:p>a<text:s text:c=\"3\"/>b</text:p></table:table-cell>"));
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "A1")), "a   b");
}

func testATabAndALineBreakInAParagraph() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"string\">" +
        "<text:p>a<text:tab/>b<text:line-break/>c</text:p></table:table-cell>"));
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "A1")), "a\tb\nc");
}

func testAStringValueAttributeWinsOverTheText() {
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"string\" " +
        "office:string-value=\"real\"><text:p>shown</text:p></table:table-cell>"));
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "A1")), "real");
}

func testACoveredCellStillTakesItsPosition() {
    # A merged region's hidden cells are <covered-table-cell>; they occupy a
    # column even though they show nothing.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"string\"><text:p>a</text:p>" +
        "</table:table-cell><table:covered-table-cell/>" +
        "<table:table-cell office:value-type=\"string\"><text:p>c</text:p>" +
        "</table:table-cell>"));
    def s as Sheet init sheetByName($wb, "Sheet1");
    testing.assertEqual(asString(cell($s, "A1")), "a");
    testing.assertTrue(isEmpty(cell($s, "B1")));
    testing.assertEqual(asString(cell($s, "C1")), "c");
}

func testAFloatWithAnUnreadableValueFallsBackToItsText() {
    # Damage, not bad data: keep the cell rather than refusing the file.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"float\" office:value=\"not a number\">" +
        "<text:p>oops</text:p></table:table-cell>"));
    def v as Value init cell(sheetByName($wb, "Sheet1"), "A1");
    testing.assertEqual(kindOf($v), "text");
    testing.assertEqual(asString($v), "oops");
}

func failOnContentWithNoSpreadsheet() {
    readOdsContent(convert.bytesFromString(
        "<office:document-content><office:body/></office:document-content>",
        "utf-8"));
}

func failOnEmptyContent() {
    readOdsContent(convert.bytesFromString("", "utf-8"));
}

func failOnSpreadsheetWithNoTables() {
    readOdsContent(odsDocument(""));
}

func testReadOdsContentRefusesWhatIsNotAWorkbook() {
    testing.assertThrows("failOnContentWithNoSpreadsheet", ERROR_KIND);
    testing.assertThrows("failOnEmptyContent", ERROR_KIND);
    testing.assertThrows("failOnSpreadsheetWithNoTables", ERROR_KIND);
}

func failOnNonContainer() {
    readOds(convert.bytesFromString("not a zip", "utf-8"));
}

func testReadOdsRefusesWhatIsNotAContainer() {
    testing.assertThrows("failOnNonContainer", ERROR_KIND);
}

func failOnWrongMimetype() {
    def members as list of Member init [];
    $members[] = storedMember(
        "mimetype",
        convert.bytesFromString("application/vnd.oasis.opendocument.text", "utf-8"));
    $members[] = member("content.xml", odsOneRow("<table:table-cell/>"));
    readOds(zip($members));
}

func testReadOdsRefusesAnotherDocumentType() {
    testing.assertThrows("failOnWrongMimetype", ERROR_KIND);
}

func testAMissingMimetypeIsTolerated() {
    # Required by ODF, but some writers omit it and content.xml is the
    # authority on what is actually inside.
    def members as list of Member init [];
    $members[] = member(
        "content.xml",
        odsOneRow("<table:table-cell office:value-type=\"string\"><text:p>a</text:p>" +
            "</table:table-cell>"));
    def wb as Workbook init readOds(zip($members));
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "A1")), "a");
}

func failOnContainerWithNoContent() {
    def members as list of Member init [];
    $members[] = storedMember("mimetype", convert.bytesFromString(ODS_MIMETYPE, "utf-8"));
    readOds(zip($members));
}

func testReadOdsRefusesAContainerWithNoContent() {
    testing.assertThrows("failOnContainerWithNoContent", ERROR_KIND);
}

func testOdsFormulaSourceStripsThePrefixAndTranslates() {
    testing.assertEqual(odsFormulaSource("of:=[.B3]*[.C2]"), "B3*C2");
    testing.assertEqual(odsFormulaSource("=[.A1]"), "A1");
    testing.assertEqual(odsFormulaSource("[.A1]"), "A1");
}

func testAnExternalEntityIsNotResolved() {
    # XXE: the deck decodes only the five predefined entities and numeric
    # references itself, rather than handing the document to a DTD-aware
    # parser, so a SYSTEM entity is left standing as text and no file is read.
    def wb as Workbook init readOdsContent(convert.bytesFromString(
        "<?xml version=\"1.0\"?>" +
            "<!DOCTYPE d [<!ENTITY x SYSTEM \"file:///etc/passwd\">]>" +
            "<office:document-content" +
            " xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\"" +
            " xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\"" +
            " xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\">" +
            "<office:body><office:spreadsheet>" +
            "<table:table table:name=\"S\"><table:table-row>" +
            "<table:table-cell office:value-type=\"string\"><text:p>&x;</text:p>" +
            "</table:table-cell></table:table-row></table:table>" +
            "</office:spreadsheet></office:body></office:document-content>",
        "utf-8"));
    testing.assertEqual(asString(cell(sheetByName($wb, "S"), "A1")), "&x;");
}

func testAnEntityBombIsNotExpanded() {
    # Billion laughs: the nested entity definitions are never expanded, for
    # the same reason, so the cell holds the reference as text.
    def wb as Workbook init readOdsContent(convert.bytesFromString(
        "<?xml version=\"1.0\"?>" +
            "<!DOCTYPE d [<!ENTITY e0 \"AAAA\">" +
            "<!ENTITY e1 \"&e0;&e0;\"><!ENTITY e2 \"&e1;&e1;\">]>" +
            "<office:document-content" +
            " xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\"" +
            " xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\"" +
            " xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\">" +
            "<office:body><office:spreadsheet>" +
            "<table:table table:name=\"S\"><table:table-row>" +
            "<table:table-cell office:value-type=\"string\"><text:p>&e2;</text:p>" +
            "</table:table-cell></table:table-row></table:table>" +
            "</office:spreadsheet></office:body></office:document-content>",
        "utf-8"));
    testing.assertEqual(asString(cell(sheetByName($wb, "S"), "A1")), "&e2;");
}

func testAColumnRepeatIsCappedPerAxis() {
    # A row repeat belongs on the row element, so on a cell it is ignored and
    # only the column axis applies: 16384 columns clamp to MAX_REPEAT.
    def wb as Workbook init readOdsContent(odsOneRow("<table:table-cell office:value-type=\"string\" " +
        "table:number-columns-repeated=\"16384\" " +
        "table:number-rows-repeated=\"1048576\"><text:p>x</text:p>" +
        "</table:table-cell>"));
    testing.assertEqual(cellCount(sheetByName($wb, "Sheet1")), MAX_REPEAT);
}

func testARepeatBombIsClamped() {
    # The two axes multiply once the repeats sit where the format puts them:
    # 1048576 rows on the row element by 16384 columns on the cell asks for
    # 16.7 million cells, and a 474-byte file built that way reached 7.1 GB
    # before the kernel killed it. Capping the product bounds the damage.
    def wb as Workbook init readOdsContent(odsDocument("<table:table table:name=\"Sheet1\">" +
        "<table:table-row table:number-rows-repeated=\"1048576\">" +
        "<table:table-cell office:value-type=\"string\" " +
        "table:number-columns-repeated=\"16384\"><text:p>x</text:p>" +
        "</table:table-cell></table:table-row></table:table>"));
    testing.assertEqual(cellCount(sheetByName($wb, "Sheet1")), MAX_BLOCK_CELLS);
}

func testOdsReadsNumberStylesFromTheStylesPart() {
    # LibreOffice splits its number styles between the two parts - a file it
    # wrote had two in the content and forty-nine in `styles.xml` - so a
    # reader that looks only at the content loses most of a real document's
    # formats. Five of seven were lost before this.
    def content as string init odsDocumentWithParts();
    def styles as string init "<?xml version=\"1.0\"?><office:document-styles " +
        odsTestNamespaces() + "><office:styles>" +
        "<number:number-style style:name=\"N2\">" +
        "<number:number number:decimal-places=\"2\" " +
        "number:min-integer-digits=\"1\"/></number:number-style>" +
        "</office:styles></office:document-styles>";
    def raw as bytes init zip([
        storedMember("mimetype", convert.bytesFromString(ODS_MIMETYPE, "utf-8")),
        member("content.xml", convert.bytesFromString($content, "utf-8")),
        member("styles.xml", convert.bytesFromString($styles, "utf-8"))
    ]);
    def s as Sheet init sheetByName(readOds($raw), "S");
    testing.assertEqual(styleAt($s, "A1").format, "0.00");
    testing.assertEqual(displayAt($s, "A1"), "1234.50");
}

/**
 * The namespace declarations an ODF test document needs.
 *
 * @return {string} the attributes
 */
func odsTestNamespaces() {
    return "xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" " +
        "xmlns:number=\"urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0\" " +
        "xmlns:style=\"urn:oasis:names:tc:opendocument:xmlns:style:1.0\" " +
        "xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" " +
        "xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\"";
}

/**
 * A content part whose cell takes its format from a column default.
 *
 * The shape LibreOffice writes when a format is applied to a whole column:
 * the cell names no style, the column names one, and the number style it
 * points at lives in the other part.
 *
 * @return {string} the content part
 */
func odsDocumentWithParts() {
    return "<?xml version=\"1.0\"?><office:document-content " +
        odsTestNamespaces() + "><office:automatic-styles>" +
        "<style:style style:name=\"ce1\" style:family=\"table-cell\" " +
        "style:data-style-name=\"N2\"/>" +
        "</office:automatic-styles><office:body><office:spreadsheet>" +
        "<table:table table:name=\"S\">" +
        "<table:table-column table:default-cell-style-name=\"ce1\"/>" +
        "<table:table-row><table:table-cell office:value-type=\"float\" " +
        "office:value=\"1234.5\"><text:p>1234.5</text:p>" +
        "</table:table-cell></table:table-row>" +
        "</table:table></office:spreadsheet></office:body>" +
        "</office:document-content>";
}

func testOdsAppliesAColumnDefaultCellStyle() {
    # `table:default-cell-style-name` on a column is how an application
    # stores "format this whole column", which is the most ordinary way a
    # person applies one. The cell itself names no style at all.
    def content as string init "<?xml version=\"1.0\"?>" +
        "<office:document-content " + odsTestNamespaces() + ">" +
        "<office:automatic-styles>" +
        "<number:number-style style:name=\"N1\">" +
        "<number:number number:decimal-places=\"1\" " +
        "number:min-integer-digits=\"1\"/></number:number-style>" +
        "<style:style style:name=\"ce1\" style:family=\"table-cell\" " +
        "style:data-style-name=\"N1\"/>" +
        "</office:automatic-styles><office:body><office:spreadsheet>" +
        "<table:table table:name=\"S\">" +
        "<table:table-column/>" +
        "<table:table-column table:default-cell-style-name=\"ce1\"/>" +
        "<table:table-row>" +
        "<table:table-cell office:value-type=\"float\" office:value=\"1\">" +
        "<text:p>1</text:p></table:table-cell>" +
        "<table:table-cell office:value-type=\"float\" office:value=\"2\">" +
        "<text:p>2</text:p></table:table-cell>" +
        "</table:table-row></table:table>" +
        "</office:spreadsheet></office:body></office:document-content>";
    def s as Sheet init sheetByName(
        readOdsContent(convert.bytesFromString($content, "utf-8")),
        "S");
    # The first column declares no default, so its cell stays plain.
    testing.assertTrue(isPlain(styleAt($s, "A1")));
    testing.assertEqual(styleAt($s, "B1").format, "0.0");
    testing.assertEqual(displayAt($s, "B1"), "2.0");
}

func testOdsCellStyleBeatsTheColumnDefault() {
    def content as string init "<?xml version=\"1.0\"?>" +
        "<office:document-content " + odsTestNamespaces() + ">" +
        "<office:automatic-styles>" +
        "<number:number-style style:name=\"N1\">" +
        "<number:number number:decimal-places=\"1\" " +
        "number:min-integer-digits=\"1\"/></number:number-style>" +
        "<number:number-style style:name=\"N2\">" +
        "<number:number number:decimal-places=\"3\" " +
        "number:min-integer-digits=\"1\"/></number:number-style>" +
        "<style:style style:name=\"ce1\" style:family=\"table-cell\" " +
        "style:data-style-name=\"N1\"/>" +
        "<style:style style:name=\"ce2\" style:family=\"table-cell\" " +
        "style:data-style-name=\"N2\"/>" +
        "</office:automatic-styles><office:body><office:spreadsheet>" +
        "<table:table table:name=\"S\">" +
        "<table:table-column table:default-cell-style-name=\"ce1\"/>" +
        "<table:table-row>" +
        "<table:table-cell table:style-name=\"ce2\" " +
        "office:value-type=\"float\" office:value=\"1\">" +
        "<text:p>1</text:p></table:table-cell>" +
        "</table:table-row></table:table>" +
        "</office:spreadsheet></office:body></office:document-content>";
    def s as Sheet init sheetByName(
        readOdsContent(convert.bytesFromString($content, "utf-8")),
        "S");
    testing.assertEqual(styleAt($s, "A1").format, "0.000");
}

func testOdsColumnDefaultsAreBoundedByTheGrid() {
    # A file is free to repeat a column sixteen thousand times, and every
    # file LibreOffice writes does.
    def content as string init "<?xml version=\"1.0\"?>" +
        "<office:document-content " + odsTestNamespaces() + ">" +
        "<office:body><office:spreadsheet>" +
        "<table:table table:name=\"S\">" +
        "<table:table-column table:number-columns-repeated=\"999999999\" " +
        "table:default-cell-style-name=\"ce1\"/>" +
        "<table:table-row>" +
        "<table:table-cell office:value-type=\"float\" office:value=\"1\">" +
        "<text:p>1</text:p></table:table-cell>" +
        "</table:table-row></table:table>" +
        "</office:spreadsheet></office:body></office:document-content>";
    def s as Sheet init sheetByName(
        readOdsContent(convert.bytesFromString($content, "utf-8")),
        "S");
    testing.assertEqual(asString(cell($s, "A1")), "1");
}
