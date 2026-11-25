# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# sheets - tests for patch.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * A workbook as another application leaves it: a shared formula, an array
 * formula, a calculation chain, styles with a date format, shared strings.
 *
 * @param sheetData {string} the `<sheetData>` element
 * @return {bytes} the container
 */
func patchFixture(sheetData as string) {
    return xlsxContainer({
        "[Content_Types].xml": "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
            "<Override PartName=\"/xl/workbook.xml\" ContentType=\"wb\"/>" +
            "<Override PartName=\"/xl/calcChain.xml\" ContentType=\"cc\"/></Types>",
        "xl/workbook.xml": "<workbook xmlns:r=\"r\"><sheets>" +
            "<sheet name=\"S\" r:id=\"rId1\"/></sheets></workbook>",
        "xl/_rels/workbook.xml.rels": "<Relationships>" +
            "<Relationship Id=\"rId1\" Target=\"worksheets/sheet1.xml\"/>" +
            "<Relationship Id=\"rId2\" Target=\"sharedStrings.xml\"/>" +
            "<Relationship Id=\"rId3\" Target=\"styles.xml\"/>" +
            "<Relationship Id=\"rId4\" Target=\"calcChain.xml\"/></Relationships>",
        "xl/sharedStrings.xml": "<sst><si><t>Name</t></si><si><t>Qty</t></si></sst>",
        "xl/styles.xml": "<styleSheet><cellXfs count=\"3\"><xf numFmtId=\"0\"/>" +
            "<xf numFmtId=\"14\" applyNumberFormat=\"1\"/><xf numFmtId=\"2\"/></cellXfs></styleSheet>",
        "xl/calcChain.xml": "<calcChain><c r=\"C2\" i=\"1\"/><c r=\"C3\"/></calcChain>",
        "xl/worksheets/sheet1.xml": "<worksheet><dimension ref=\"A1:C3\"/>" + $sheetData +
            "<pageMargins left=\"0.7\"/></worksheet>"
    });
}

/** The fixture's sheet data: a header, two rows, a shared formula down C. */
def const PATCH_ROWS as string init "<sheetData>" +
    "<row r=\"1\" spans=\"1:3\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c></row>" +
    "<row r=\"2\" spans=\"1:3\"><c r=\"A2\" s=\"1\"><v>45000</v></c><c r=\"B2\" s=\"2\"><v>3</v></c>" +
    "<c r=\"C2\"><f t=\"shared\" ref=\"C2:C3\" si=\"0\">B2*2</f><v>6</v></c></row>" +
    "<row r=\"3\" spans=\"1:3\"><c r=\"A3\" s=\"1\"><v>45001</v></c><c r=\"B3\" s=\"2\"><v>4</v></c>" +
    "<c r=\"C3\"><f t=\"shared\" si=\"0\"/><v>8</v></c></row></sheetData>";

/**
 * A member of a container, as text.
 *
 * @param raw {bytes} the container
 * @param name {string} the member
 * @return {string} its text
 */
func memberText(raw as bytes, name as string) {
    return encoding.decode("utf-8", unzip($raw)[$name]);
}

func testPatchingLeavesEveryOtherPartAsItWas() {
    def before as bytes init patchFixture(PATCH_ROWS);
    def after as bytes init patchXlsx($before, "S", {"B2": number(5.0)});
    def old as map of string to bytes init unzip($before);
    def new as map of string to bytes init unzip($after);
    testing.assertEqual(maps.keys($new), maps.keys($old));
    for (def name in $old) {
        if ($name != "xl/worksheets/sheet1.xml") {
            testing.assertEqual($new[$name], $old[$name]);
        }
    }
    def sheet as string init memberText($after, "xl/worksheets/sheet1.xml");
    # The untouched rows and cells are copied as they were written.
    testing.assertTrue(strings.contains(
        $sheet,
        "<row r=\"1\" spans=\"1:3\"><c r=\"A1\" t=\"s\"><v>0</v></c>"));
    testing.assertTrue(strings.contains(
        $sheet,
        "<c r=\"C2\"><f t=\"shared\" ref=\"C2:C3\" si=\"0\">B2*2</f><v>6</v></c>"));
    testing.assertTrue(strings.contains($sheet, "<pageMargins left=\"0.7\"/>"));
}

func testAReplacedCellKeepsItsStyle() {
    def after as bytes init patchXlsx(patchFixture(PATCH_ROWS), "S", {"B2": number(5.0)});
    testing.assertTrue(strings.contains(
        memberText($after, "xl/worksheets/sheet1.xml"),
        "<c r=\"B2\" s=\"2\"><v>5</v></c>"));
    testing.assertEqual(cell(sheetByName(readXlsx($after), "S"), "B2"), number(5.0));
}

func testPatchedTextIsInlineAndTheSharedTableUntouched() {
    def after as bytes init patchXlsx(patchFixture(PATCH_ROWS), "S", {"D1": text("Note & more")});
    def s as Sheet init sheetByName(readXlsx($after), "S");
    testing.assertEqual(cell($s, "D1"), text("Note & more"));
    testing.assertEqual(cell($s, "A1"), text("Name"));
    testing.assertTrue(strings.contains(
        memberText($after, "xl/worksheets/sheet1.xml"),
        "t=\"inlineStr\""));
}

func testNewCellsAndRowsGoInOrderAndGrowTheDimension() {
    def after as bytes init patchXlsx(
        patchFixture(PATCH_ROWS),
        "S",
        {"D2": text("x"), "A5": number(1.0), "B4": boolean(true)});
    def sheet as string init memberText($after, "xl/worksheets/sheet1.xml");
    testing.assertTrue(strings.contains($sheet, "<dimension ref=\"A1:D5\"/>"));
    testing.assertTrue(strings.indexOf($sheet, "<row r=\"4\">") <
        strings.indexOf($sheet, "<row r=\"5\">"));
    # Row 2 gained a cell past its spans, so the hint is dropped there only.
    testing.assertTrue(strings.contains($sheet, "<row r=\"2\"><c r=\"A2\""));
    testing.assertTrue(strings.contains($sheet, "<row r=\"3\" spans=\"1:3\">"));
    def s as Sheet init sheetByName(readXlsx($after), "S");
    testing.assertEqual(
        rows($s),
        [
            [text("Name"), text("Qty"), empty(), empty()],
            [
                date(fromSerial(45000.0, false)),
                number(3.0),
                Value.Formula{source: "B2*2", cached: "6"},
                text("x")
            ],
            [
                date(fromSerial(45001.0, false)),
                number(4.0),
                Value.Formula{source: "", cached: "8"},
                empty()
            ],
            [empty(), boolean(true), empty(), empty()],
            [number(1.0), empty(), empty(), empty()]
        ]);
}

func testEmptyClearsTheValueAndKeepsTheStyle() {
    def after as bytes init patchXlsx(
        patchFixture(PATCH_ROWS),
        "S",
        {"B3": empty(), "A1": empty()});
    def sheet as string init memberText($after, "xl/worksheets/sheet1.xml");
    testing.assertTrue(strings.contains($sheet, "<c r=\"B3\" s=\"2\"/>"));
    testing.assertFalse(strings.contains($sheet, "r=\"A1\""));
}

func testTheAnchorOfASharedFormulaIsRefused() {
    testing.assertThrows("patchTheSharedAnchor", ERROR_KIND);
}

func patchTheSharedAnchor() {
    patchXlsx(patchFixture(PATCH_ROWS), "S", {"C2": number(1.0)});
}

func testACellInsideAnArrayFormulaIsRefused() {
    testing.assertThrows("patchInsideAnArray", ERROR_KIND);
}

func patchInsideAnArray() {
    patchXlsx(
        patchFixture("<sheetData><row r=\"1\">" +
            "<c r=\"A1\"><f t=\"array\" ref=\"A1:A2\">B1:B2*2</f><v>2</v></c></row>" +
            "<row r=\"2\"><c r=\"A2\"><v>4</v></c></row></sheetData>"),
        "S",
        {"A2": number(1.0)});
}

func testOverwritingAFormulaDropsTheCalculationChain() {
    def after as bytes init patchXlsx(patchFixture(PATCH_ROWS), "S", {"C3": number(9.0)});
    testing.assertFalse(maps.has(unzip($after), "xl/calcChain.xml"));
    testing.assertFalse(strings.contains(memberText($after, "[Content_Types].xml"), "calcChain"));
    testing.assertFalse(strings.contains(
        memberText($after, "xl/_rels/workbook.xml.rels"),
        "calcChain"));
    testing.assertTrue(strings.contains(
        memberText($after, "xl/_rels/workbook.xml.rels"),
        "styles.xml"));
}

func testAFormulaReplacedByAFormulaKeepsTheChain() {
    def after as bytes init patchXlsx(
        patchFixture(PATCH_ROWS),
        "S",
        {"C3": Value.Formula{source: "B3*3", cached: "12"}});
    testing.assertTrue(maps.has(unzip($after), "xl/calcChain.xml"));
    testing.assertEqual(
        cell(sheetByName(readXlsx($after), "S"), "C3"),
        Value.Formula{source: "B3*3", cached: "12"});
}

func testADateGoesOnlyIntoADateFormattedCell() {
    def at as time.Time init time.fromIso("2026-11-23T00:00:00Z");
    def after as bytes init patchXlsx(patchFixture(PATCH_ROWS), "S", {"A3": date($at)});
    testing.assertEqual(cell(sheetByName(readXlsx($after), "S"), "A3"), date($at));
    testing.assertThrows("patchADateIntoAPlainCell", ERROR_KIND);
}

func patchADateIntoAPlainCell() {
    patchXlsx(patchFixture(PATCH_ROWS), "S", {"B3": date(time.fromIso("2026-11-23T00:00:00Z"))});
}

func testTwoSpellingsOfOneCellAreRefused() {
    testing.assertThrows("patchOneCellTwice", ERROR_KIND);
}

func patchOneCellTwice() {
    patchXlsx(patchFixture(PATCH_ROWS), "S", {"b2": number(1.0), "B2": number(2.0)});
}

func testAnEmptySheetCanBePatched() {
    def after as bytes init patchXlsx(patchFixture("<sheetData/>"), "S", {"B2": number(1.0)});
    def s as Sheet init sheetByName(readXlsx($after), "S");
    testing.assertEqual(cell($s, "B2"), number(1.0));
    testing.assertEqual(cellCount($s), 1);
}

func testPatchingWhatThisDeckWroteReadsBackTheSame() {
    def s as Sheet init sheetOf("S", [[text("a"), number(1.0)], [text("b"), number(2.0)]]);
    $s = freezePanes(setColumnWidth($s, "A", 20.0), 1, 0);
    def after as bytes init patchXlsx(
        writeXlsx(addSheet(newWorkbook(), $s)),
        "",
        {"B2": number(3.0)});
    def back as Sheet init sheetByName(readXlsx($after), "S");
    testing.assertEqual(cell($back, "B2"), number(3.0));
    testing.assertEqual(cell($back, "A2"), text("b"));
    testing.assertEqual($back.layout, $s.layout);
}
