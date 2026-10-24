# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for export.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * A small sheet with a header row, a style and a gap.
 *
 * @return {Sheet} the fixture
 */
func exportFixture() {
    def s as Sheet init sheetOf(
        "Report",
        [
            [text("Item"), text("Qty"), text("Price")],
            [text("Bolt & nut"), integer(12), number(1.5)],
            [text("Washer"), empty(), number(0.25)]
        ]);
    return setStyle($s, "A1", withBold(style(), true));
}

func testToHtmlWrapsATable() {
    def body as string init toHtml(exportFixture());
    testing.assertTrue(strings.startsWith($body, "<table>"));
    testing.assertTrue(strings.endsWith($body, "</table>"));
    # One row element per row, and the header is not special in HTML terms.
    testing.assertEqual(len(strings.split($body, "<tr")) - 1, 3);
}

func testToHtmlEscapesContent() {
    def body as string init toHtml(exportFixture());
    # An ampersand that is not escaped is the classic way to produce a page
    # no parser will accept.
    testing.assertTrue(strings.contains($body, "Bolt &amp; nut"));
    testing.assertFalse(strings.contains($body, "Bolt & nut"));
}

func testToHtmlEscapesMarkupInACell() {
    def s as Sheet init sheetOf("S", [[text("<script>alert(1)</script>")]]);
    def body as string init toHtml($s);
    # A cell holding markup must not become markup: a sheet read from an
    # untrusted file goes straight into this.
    testing.assertFalse(strings.contains($body, "<script>"));
    testing.assertTrue(strings.contains($body, "&lt;script&gt;"));
}

func testToHtmlAppliesNumberFormats() {
    # A page is for a person, so a cell whose format says `0.0%` has to show
    # 7.5% and not 0.075.
    def s as Sheet init sheetOf("S", [[number(0.075), number(1234.5)]]);
    $s = setStyle($s, "A1", withFormat(style(), "0.0%"));
    $s = setStyle($s, "B1", withFormat(style(), "$#,##0.00"));
    def body as string init toHtml($s);
    testing.assertTrue(strings.contains($body, "7.5%"));
    testing.assertTrue(strings.contains($body, "$1,234.50"));
    testing.assertFalse(strings.contains($body, "0.075"));
}

func testToRecordsKeepsTheValue() {
    # The other direction: JSON is read by a program, which wants the number
    # rather than its presentation.
    def s as Sheet init sheetOf("S", [[text("Share")], [number(0.075)]]);
    $s = setStyle($s, "A2", withFormat(style(), "0.0%"));
    def records as list of map of string to string init toRecords($s);
    testing.assertEqual($records[0]["Share"], "0.075");
}

func testToPdfMeasuresTheFormattedText() {
    # The width has to follow what is drawn, or a column sized for `0.075`
    # would clip `7.5%`. Checked by the document growing when the format
    # makes the text wider.
    def plain as Sheet init sheetOf("S", [[number(0.075)]]);
    def wide as Sheet init setStyle(
        sheetOf("S", [[number(0.075)]]),
        "A1",
        withFormat(style(), "0.00000000%"));
    testing.assertTrue(len(toPdf($wide, a4())) != len(toPdf($plain, a4())));
}

func testToHtmlCarriesStyles() {
    def body as string init toHtml(exportFixture());
    testing.assertTrue(strings.contains($body, "font-weight:bold"));
}

func testToHtmlKeepsAGap() {
    def body as string init toHtml(exportFixture());
    # An empty cell still occupies its column, or every later cell in the row
    # would shift left.
    testing.assertTrue(strings.contains($body, "<td></td>") or
        strings.contains($body, "<td style"));
}

func testToHtmlOnAnEmptySheet() {
    testing.assertEqual(toHtml(newSheet("Empty")), "<table></table>");
}

func testWorkbookToHtmlLabelsEachSheet() {
    def wb as Workbook init addSheet(
        addSheet(newWorkbook(), exportFixture()),
        sheetOf("Second", [[integer(1)]]));
    def body as string init workbookToHtml($wb);
    testing.assertTrue(strings.contains($body, "Report"));
    testing.assertTrue(strings.contains($body, "Second"));
    testing.assertEqual(len(strings.split($body, "<table>")) - 1, 2);
}

func testToHtmlDocumentIsAWholePage() {
    def page as string init toHtmlDocument(exportFixture(), "Q3 & Q4");
    testing.assertTrue(strings.startsWith($page, "<!doctype html>"));
    testing.assertTrue(strings.contains($page, "<meta charset=\"utf-8\">"));
    testing.assertTrue(strings.contains($page, "</html>"));
    # The title is escaped too; it is caller-supplied text like any other.
    testing.assertTrue(strings.contains($page, "<title>Q3 &amp; Q4</title>"));
}

func testToRecordsUsesTheHeaderRow() {
    def records as list of map of string to string init toRecords(exportFixture());
    testing.assertEqual(len($records), 2);
    testing.assertEqual($records[0]["Item"], "Bolt & nut");
    testing.assertEqual($records[0]["Qty"], "12");
    testing.assertEqual($records[1]["Item"], "Washer");
    # A blank cell is an empty field, not a missing key.
    testing.assertEqual($records[1]["Qty"], "");
}

func testToRecordsNamesAnEmptyHeaderCellByItsColumn() {
    def s as Sheet init sheetOf(
        "S",
        [[text("a"), empty(), text("c")], [integer(1), integer(2), integer(3)]]);
    def records as list of map of string to string init toRecords($s);
    # A record needs a key for every column, so a blank header falls back to
    # the column letter rather than colliding on "".
    testing.assertEqual($records[0]["a"], "1");
    testing.assertEqual($records[0]["B"], "2");
    testing.assertEqual($records[0]["c"], "3");
}

func testToRecordsDisambiguatesRepeatedHeaders() {
    def s as Sheet init sheetOf("S", [[text("a"), text("a")], [integer(1), integer(2)]]);
    def records as list of map of string to string init toRecords($s);
    # Two columns named the same would otherwise lose one silently.
    testing.assertEqual(len(maps.keys($records[0])), 2);
}

func failOnRecordsFromAnEmptySheet() {
    toRecords(newSheet("Empty"));
}

func testToRecordsNeedsAHeader() {
    testing.assertThrows("failOnRecordsFromAnEmptySheet", ERROR_KIND);
}

func testToJsonIsAnArrayOfObjects() {
    def body as string init toJson(exportFixture());
    testing.assertTrue(strings.startsWith($body, "["));
    testing.assertTrue(strings.endsWith(strings.trim($body), "]"));
    testing.assertTrue(strings.contains($body, "\"Qty\": \"12\""));
    # Jennifer's JSON encoder escapes an ampersand as `\u0026`, which is
    # valid JSON and decodes back to `&`. Pinned so a change is noticed,
    # since it is what a consumer of this output will see.
    testing.assertTrue(strings.contains($body, "Bolt \\u0026 nut"));
}

func testToJsonLinesIsOneObjectPerLine() {
    def body as string init toJsonLines(exportFixture());
    def lines as list of string init strings.split(strings.trim($body), "\n");
    testing.assertEqual(len($lines), 2);
    # Each line has to stand on its own, which is the point of the format.
    # Raw strings: a brace in a cooked string opens or closes an
    # interpolation slot.
    for (def line in $lines) {
        testing.assertTrue(strings.startsWith($line, '{'));
        testing.assertTrue(strings.endsWith($line, '}'));
    }
    testing.assertTrue(strings.contains($lines[0], "\"Qty\":\"12\""));
}

func testPageSizes() {
    testing.assertEqual(a4().width, 595);
    testing.assertEqual(a4().height, 842);
    # Landscape is the same paper turned over.
    testing.assertEqual(a4Landscape().width, a4().height);
    testing.assertEqual(a4Landscape().height, a4().width);
    testing.assertEqual(letter().width, 612);
    testing.assertEqual(letter().height, 792);
    # Every page needs room for text inside its margins.
    for (def size in [a4(), a4Landscape(), letter()]) {
        testing.assertTrue($size.margin > 0);
        testing.assertTrue($size.fontSize > 0);
        testing.assertTrue($size.width > $size.margin * 2);
    }
}

func testToPdfProducesAPdf() {
    def doc as bytes init toPdf(exportFixture(), a4());
    testing.assertTrue(len($doc) > 0);
    # The magic and the trailer are what a reader looks for.
    testing.assertEqual(convert.stringFromBytes(binary.slice($doc, 0, 5), "utf-8"), "%PDF-");
    testing.assertTrue(binary.indexOf($doc, convert.bytesFromString("%%EOF", "utf-8"), 0) > 0);
    testing.assertTrue(binary.indexOf($doc, convert.bytesFromString("/Type /Page", "utf-8"), 0) > 0);
}

func testToPdfPaginates() {
    # More rows than one page holds must produce more than one page, rather
    # than running off the bottom.
    def lines as list of list of Value init [];
    for (def i in 0..300) {
        $lines[] = [text("row " + convert.toString($i)), integer($i)];
    }
    def doc as bytes init toPdf(sheetOf("Long", $lines), a4());
    # One /MediaBox per page, which is how a reader counts them too.
    def pages as int init 0;
    def at as int init 0;
    def marker as bytes init convert.bytesFromString("/MediaBox", "utf-8");
    while (true) {
        def hit as int init binary.indexOf($doc, $marker, $at);
        if ($hit < 0) {
            break;
        }
        $pages = $pages + 1;
        $at = $hit + 1;
    }
    testing.assertTrue($pages > 1);
}

func testToPdfOnAnEmptySheet() {
    # One blank page, not a document with no pages, which no reader accepts.
    def doc as bytes init toPdf(newSheet("Empty"), a4());
    testing.assertEqual(convert.stringFromBytes(binary.slice($doc, 0, 5), "utf-8"), "%PDF-");
}

func failOnExportingTooManyRows() {
    def s as Sheet init newSheet("Huge");
    $s = setCellAt($s, Ref{row: MAX_EXPORT_ROWS + 10, col: 0}, integer(1));
    toHtml($s);
}

func testExportsRefuseASheetTooLargeToLayOut() {
    # The cap is what stops a million-row sheet from being turned into one
    # HTML string in memory.
    testing.assertThrows("failOnExportingTooManyRows", ERROR_KIND);
    testing.assertEqual(MAX_EXPORT_ROWS, 100000);
}
