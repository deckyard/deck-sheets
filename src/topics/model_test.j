# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for model.j, and the fixtures the format overlays share.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * The workbook every format overlay round-trips.
 *
 * Deliberately awkward: an ampersand that must be escaped, a float and a
 * whole number, a formula with a cached result, a date, a boolean, a gap in
 * the middle of a row, and a second sheet whose name needs quoting in a
 * reference. If a codec survives this it survives most real files.
 *
 * @return {Workbook} the fixture
 */
func fixtureWorkbook() {
    def s as Sheet init newSheet("Sheet1");
    $s = setRow($s, 0, [text("Name"), text("Qty"), text("Price")]);
    $s = setRow($s, 1, [text("Widget & Co"), integer(4), number(9.99)]);
    $s = setCell($s, "A3", text("Gadget"));
    $s = setCell($s, "B3", integer(2));
    $s = setCell($s, "C3", formula("B3*C2", "19.98"));
    # Row 4 leaves A and B empty: a gap a reader has to carry through.
    $s = setCell($s, "C4", date(time.fromIso("2026-10-02T00:00:00Z")));
    $s = setCell($s, "A5", boolean(true));
    $s = setCell($s, "B5", errorValue("#DIV/0!"));

    def other as Sheet init newSheet("Second Sheet");
    $other = setCell($other, "A1", text("hello"));

    def wb as Workbook init newWorkbook();
    $wb = addSheet($wb, $s);
    $wb = addSheet($wb, $other);
    return $wb;
}

/**
 * Assert that a workbook still carries everything `fixtureWorkbook` put in.
 *
 * Every format overlay calls this after a round trip, so a codec that drops a
 * value fails in the overlay that lost it rather than somewhere downstream.
 *
 * @param wb {Workbook} the workbook to check
 * @param keepsFormulas {bool} whether the format round-trips a formula's source
 */
func assertFixtureSurvived(wb as Workbook, keepsFormulas as bool) {
    testing.assertEqual(sheetNames($wb), ["Sheet1", "Second Sheet"]);
    def s as Sheet init sheetByName($wb, "Sheet1");

    testing.assertEqual(asString(cell($s, "A1")), "Name");
    testing.assertEqual(asString(cell($s, "C1")), "Price");
    testing.assertEqual(asString(cell($s, "A2")), "Widget & Co");
    testing.assertEqual(asNumber(cell($s, "B2")), 4.0);
    testing.assertEqual(asNumber(cell($s, "C2")), 9.99);
    testing.assertEqual(asString(cell($s, "A3")), "Gadget");

    # The gap has to still be a gap.
    testing.assertTrue(isEmpty(cell($s, "A4")));
    testing.assertTrue(isEmpty(cell($s, "B4")));

    testing.assertEqual(time.format(asTime(cell($s, "C4")), "%Y-%m-%d"), "2026-10-02");
    testing.assertTrue(asBool(cell($s, "A5")));
    testing.assertEqual(asString(cell($s, "B5")), "#DIV/0!");

    def c3 as Value init cell($s, "C3");
    testing.assertEqual(asString($c3), "19.98");
    if ($keepsFormulas) {
        testing.assertEqual(kindOf($c3), "formula");
        match ($c3) {
            when Formula(f) { testing.assertEqual($f.source, "B3*C2"); }
            else {
                throw Error{
                    kind: "test",
                    message: "C3 is not a formula",
                    file: "",
                    line: 0,
                    col: 0
                };
            }
        }
    }

    def other as Sheet init sheetByName($wb, "Second Sheet");
    testing.assertEqual(asString(cell($other, "A1")), "hello");
}

func testNewSheetIsEmpty() {
    def s as Sheet init newSheet("Sheet1");
    testing.assertEqual($s.name, "Sheet1");
    testing.assertEqual(cellCount($s), 0);
    testing.assertEqual($s.rowCount, 0);
    testing.assertEqual($s.colCount, 0);
}

func failOnEmptySheetName() {
    newSheet("");
}

func failOnLongSheetName() {
    newSheet(strings.repeat("x", 32));
}

func failOnSheetNameWithBracket() {
    newSheet("a[b]");
}

func failOnSheetNameWithSlash() {
    newSheet("a/b");
}

func failOnSheetNameWithColon() {
    newSheet("a:b");
}

func failOnSheetNameInQuotes() {
    newSheet("'quoted'");
}

func testNewSheetRefusesANameNoApplicationAccepts() {
    testing.assertThrows("failOnEmptySheetName", ERROR_KIND);
    testing.assertThrows("failOnLongSheetName", ERROR_KIND);
    testing.assertThrows("failOnSheetNameWithBracket", ERROR_KIND);
    testing.assertThrows("failOnSheetNameWithSlash", ERROR_KIND);
    testing.assertThrows("failOnSheetNameWithColon", ERROR_KIND);
    testing.assertThrows("failOnSheetNameInQuotes", ERROR_KIND);
}

func testASheetNameOf31CharactersIsAllowed() {
    def s as Sheet init newSheet(strings.repeat("x", 31));
    testing.assertEqual(len($s.name), 31);
}

func testAnAbsentCellReadsAsEmpty() {
    def s as Sheet init newSheet("Sheet1");
    testing.assertTrue(isEmpty(cell($s, "Z100")));
    testing.assertEqual(asString(cell($s, "A1")), "");
}

func testSetCellStoresAndReadsBack() {
    def s as Sheet init newSheet("Sheet1");
    $s = setCell($s, "B7", number(42.5));
    testing.assertEqual(asNumber(cell($s, "B7")), 42.5);
    testing.assertEqual(cellCount($s), 1);
}

func testSetCellIsKeyedCanonically() {
    # A lowercase or dollar-laden spelling must reach the same cell.
    def s as Sheet init newSheet("Sheet1");
    $s = setCell($s, "b7", number(1.0));
    testing.assertEqual(asNumber(cell($s, "B7")), 1.0);
    testing.assertEqual(asNumber(cell($s, "$B$7")), 1.0);
    testing.assertEqual(cellCount($s), 1);
}

func testSetCellGrowsTheExtent() {
    def s as Sheet init newSheet("Sheet1");
    $s = setCell($s, "C4", number(1.0));
    testing.assertEqual($s.rowCount, 4);
    testing.assertEqual($s.colCount, 3);
    testing.assertEqual(areaRef(extent($s)), "A1:C4");
}

func testSettingEmptyRemovesTheCell() {
    def s as Sheet init newSheet("Sheet1");
    $s = setCell($s, "B7", number(1.0));
    $s = setCell($s, "B7", empty());
    testing.assertEqual(cellCount($s), 0);
    testing.assertTrue(isEmpty(cell($s, "B7")));
}

func testClearCellRemovesTheCellButKeepsTheExtent() {
    # Both formats keep a sheet's shape after its cells are cleared.
    def s as Sheet init newSheet("Sheet1");
    $s = setCell($s, "C4", number(1.0));
    $s = clearCell($s, "C4");
    testing.assertEqual(cellCount($s), 0);
    testing.assertEqual($s.rowCount, 4);
    testing.assertEqual($s.colCount, 3);
}

func testClearingAnAbsentCellIsHarmless() {
    def s as Sheet init newSheet("Sheet1");
    $s = clearCell($s, "B7");
    testing.assertEqual(cellCount($s), 0);
}

func testValueSemanticsHoldForASheet() {
    def a as Sheet init newSheet("Sheet1");
    def b as Sheet init setCell($a, "A1", number(1.0));
    testing.assertEqual(cellCount($a), 0);
    testing.assertEqual(cellCount($b), 1);
}

func testExtentOfAnEmptySheet() {
    testing.assertEqual(areaRef(extent(newSheet("Sheet1"))), "A1");
}

func testRowIsPaddedToTheSheetWidth() {
    def s as Sheet init newSheet("Sheet1");
    $s = setCell($s, "C1", number(1.0));
    def r as list of Value init row($s, 0);
    testing.assertEqual(len($r), 3);
    testing.assertTrue(isEmpty($r[0]));
    testing.assertTrue(isEmpty($r[1]));
    testing.assertEqual(asNumber($r[2]), 1.0);
}

func testRowsCoversEveryRow() {
    def s as Sheet init newSheet("Sheet1");
    $s = setRow($s, 0, [text("a"), text("b")]);
    $s = setRow($s, 2, [text("c")]);
    def rs as list of list of Value init rows($s);
    testing.assertEqual(len($rs), 3);
    testing.assertEqual(asString($rs[0][0]), "a");
    testing.assertTrue(isEmpty($rs[1][0]));
    testing.assertEqual(asString($rs[2][0]), "c");
}

func testAddRowAppendsBelowEverything() {
    def s as Sheet init newSheet("Sheet1");
    $s = addRow($s, [text("a")]);
    $s = addRow($s, [text("b")]);
    testing.assertEqual($s.rowCount, 2);
    testing.assertEqual(asString(cell($s, "A1")), "a");
    testing.assertEqual(asString(cell($s, "A2")), "b");
}

func testSheetByNameFindsIt() {
    def wb as Workbook init fixtureWorkbook();
    testing.assertEqual(sheetByName($wb, "Second Sheet").name, "Second Sheet");
}

func failOnMissingSheet() {
    sheetByName(workbookWith("Sheet1"), "Nope");
}

func testSheetByNameRefusesAMissingSheet() {
    testing.assertThrows("failOnMissingSheet", ERROR_KIND);
}

func testTheMissingSheetErrorNamesWhatIsThere() {
    def message as string init "";
    try {
        sheetByName(workbookWith("Sheet1"), "Nope");
    } catch (e) {
        $message = $e.message;
    }
    testing.assertTrue(strings.contains($message, "\"Sheet1\""));
}

func testHasSheetAndSheetNames() {
    def wb as Workbook init fixtureWorkbook();
    testing.assertTrue(hasSheet($wb, "Sheet1"));
    testing.assertFalse(hasSheet($wb, "sheet1"));
    testing.assertEqual(sheetNames($wb), ["Sheet1", "Second Sheet"]);
}

func testWorkbookWithStartsWithOneSheet() {
    def wb as Workbook init workbookWith("Sheet1");
    testing.assertEqual(sheetNames($wb), ["Sheet1"]);
    testing.assertFalse($wb.date1904);
}

func testPutSheetReplacesInPlace() {
    def wb as Workbook init fixtureWorkbook();
    def s as Sheet init sheetByName($wb, "Sheet1");
    $s = setCell($s, "Z1", text("new"));
    $wb = putSheet($wb, $s);
    testing.assertEqual(sheetNames($wb), ["Sheet1", "Second Sheet"]);
    testing.assertEqual(asString(cell(sheetByName($wb, "Sheet1"), "Z1")), "new");
}

func testPutSheetAppendsAnUnknownSheet() {
    def wb as Workbook init workbookWith("Sheet1");
    $wb = putSheet($wb, newSheet("Extra"));
    testing.assertEqual(sheetNames($wb), ["Sheet1", "Extra"]);
}

func failOnDuplicateSheet() {
    addSheet(workbookWith("Sheet1"), newSheet("Sheet1"));
}

func testAddSheetRefusesADuplicateName() {
    testing.assertThrows("failOnDuplicateSheet", ERROR_KIND);
}

func testRemoveSheetDropsIt() {
    def wb as Workbook init fixtureWorkbook();
    $wb = removeSheet($wb, "Second Sheet");
    testing.assertEqual(sheetNames($wb), ["Sheet1"]);
}

func testRemoveSheetKeepsTheDateSystem() {
    def wb as Workbook init fixtureWorkbook();
    $wb.date1904 = true;
    $wb = removeSheet($wb, "Second Sheet");
    testing.assertTrue($wb.date1904);
}

func failOnRemovingTheLastSheet() {
    removeSheet(workbookWith("Sheet1"), "Sheet1");
}

func failOnRemovingAMissingSheet() {
    removeSheet(fixtureWorkbook(), "Nope");
}

func testRemoveSheetRefusesWhatWouldBreakTheFile() {
    testing.assertThrows("failOnRemovingTheLastSheet", ERROR_KIND);
    testing.assertThrows("failOnRemovingAMissingSheet", ERROR_KIND);
}

func testRenameSheetKeepsItsPosition() {
    def wb as Workbook init fixtureWorkbook();
    $wb = renameSheet($wb, "Sheet1", "Q3");
    testing.assertEqual(sheetNames($wb), ["Q3", "Second Sheet"]);
    testing.assertEqual(asString(cell(sheetByName($wb, "Q3"), "A1")), "Name");
}

func testRenameSheetToItsOwnNameIsHarmless() {
    def wb as Workbook init fixtureWorkbook();
    $wb = renameSheet($wb, "Sheet1", "Sheet1");
    testing.assertEqual(sheetNames($wb), ["Sheet1", "Second Sheet"]);
}

func failOnRenamingToATakenName() {
    renameSheet(fixtureWorkbook(), "Sheet1", "Second Sheet");
}

func failOnRenamingAMissingSheet() {
    renameSheet(fixtureWorkbook(), "Nope", "Q3");
}

func failOnRenamingToABadName() {
    renameSheet(fixtureWorkbook(), "Sheet1", "a/b");
}

func testRenameSheetRefusesWhatItCannotDo() {
    testing.assertThrows("failOnRenamingToATakenName", ERROR_KIND);
    testing.assertThrows("failOnRenamingAMissingSheet", ERROR_KIND);
    testing.assertThrows("failOnRenamingToABadName", ERROR_KIND);
}

func testTheFixtureIsSelfConsistent() {
    # The fixture is the contract every codec is held to, so it is worth
    # checking that it says what the assertions expect before a codec runs.
    assertFixtureSurvived(fixtureWorkbook(), true);
}

func testValuesInReadsARectangle() {
    def s as Sheet init sheetByName(fixtureWorkbook(), "Sheet1");
    def block as list of list of Value init valuesIn($s, "A1:C2");
    testing.assertEqual(len($block), 2);
    testing.assertEqual(len($block[0]), 3);
    testing.assertEqual(asString($block[0][0]), "Name");
    testing.assertEqual(asString($block[0][2]), "Price");
    testing.assertEqual(asString($block[1][0]), "Widget & Co");
    testing.assertEqual(asNumber($block[1][1]), 4.0);
}

func testValuesInPadsOutsideTheSheet() {
    def s as Sheet init newSheet("S");
    $s = setCell($s, "A1", text("only"));
    def block as list of list of Value init valuesIn($s, "A1:C3");
    testing.assertEqual(len($block), 3);
    testing.assertEqual(len($block[2]), 3);
    testing.assertEqual(asString($block[0][0]), "only");
    testing.assertTrue(isEmpty($block[2][2]));
}

func testValuesInTakesASingleReference() {
    def s as Sheet init sheetByName(fixtureWorkbook(), "Sheet1");
    def block as list of list of Value init valuesIn($s, "B2");
    testing.assertEqual(len($block), 1);
    testing.assertEqual(len($block[0]), 1);
    testing.assertEqual(asNumber($block[0][0]), 4.0);
}

func failOnValuesInWithABadArea() {
    valuesIn(newSheet("S"), "not an area");
}

func testValuesInRefusesABadArea() {
    testing.assertThrows("failOnValuesInWithABadArea", ERROR_KIND);
}

func testSheetOfBuildsFromRows() {
    def s as Sheet init sheetOf(
        "Sales",
        [[text("Item"), text("Qty")], [text("Widget & Co"), integer(4)]]);
    testing.assertEqual($s.name, "Sales");
    testing.assertEqual($s.rowCount, 2);
    testing.assertEqual($s.colCount, 2);
    testing.assertEqual(cellCount($s), 4);
    testing.assertEqual(asString(cell($s, "A1")), "Item");
    testing.assertEqual(asNumber(cell($s, "B2")), 4.0);
}

func testSheetOfAgreesWithSetRow() {
    # The fast path and the incremental path must build the same sheet.
    def lines as list of list of Value init [
        [text("a"), integer(1), number(2.5)],
        [empty(), text("b")],
        [text("c")]
    ];
    def bulk as Sheet init sheetOf("S", $lines);
    def stepwise as Sheet init newSheet("S");
    for (def r in 0..len($lines)) {
        $stepwise = setRow($stepwise, $r, $lines[$r]);
    }
    testing.assertEqual(cellCount($bulk), cellCount($stepwise));
    testing.assertEqual($bulk.rowCount, $stepwise.rowCount);
    testing.assertEqual($bulk.colCount, $stepwise.colCount);
    for (def r in 0..$bulk.rowCount) {
        for (def c in 0..$bulk.colCount) {
            def at as Ref init Ref{row: $r, col: $c};
            testing.assertEqual(asString(cellAt($bulk, $at)), asString(cellAt($stepwise, $at)));
        }
    }
}

func testSheetOfSkipsEmptyCells() {
    def s as Sheet init sheetOf("S", [[empty(), text("b"), empty()]]);
    testing.assertEqual(cellCount($s), 1);
    testing.assertEqual($s.colCount, 2);
    testing.assertTrue(isEmpty(cell($s, "A1")));
    testing.assertEqual(asString(cell($s, "B1")), "b");
}

func testSheetOfTakesRaggedRows() {
    def s as Sheet init sheetOf("S", [[text("a")], [text("b"), text("c")]]);
    testing.assertEqual($s.colCount, 2);
    testing.assertEqual(asString(cell($s, "B2")), "c");
}

func testSheetOfWithNoRowsIsEmpty() {
    def s as Sheet init sheetOf("S", []);
    testing.assertEqual(cellCount($s), 0);
    testing.assertEqual($s.rowCount, 0);
}

func failOnSheetOfWithABadName() {
    sheetOf("a/b", [[text("a")]]);
}

func testSheetOfRefusesABadName() {
    testing.assertThrows("failOnSheetOfWithABadName", ERROR_KIND);
}

func failOnSetRowPastTheGrid() {
    setRow(newSheet("S"), MAX_ROW + 1, [text("a")]);
}

func testSetRowRefusesARowOffTheGrid() {
    # Before, an off-grid row reached the map through setCellAt's own check;
    # setRow now checks up front so it cannot write a key it would refuse.
    testing.assertThrows("failOnSetRowPastTheGrid", ERROR_KIND);
}

func testSetRowClearsWithAnEmptyValue() {
    def s as Sheet init sheetOf("S", [[text("a"), text("b")]]);
    $s = setRow($s, 0, [text("a"), empty()]);
    testing.assertEqual(cellCount($s), 1);
    testing.assertTrue(isEmpty(cell($s, "B1")));
}

func testACellStartsWithTheDefaultStyle() {
    def s as Sheet init newSheet("S");
    testing.assertTrue(isPlain(styleAt($s, "A1")));
}

func testSetStyleStoresAndReadsBack() {
    def s as Sheet init newSheet("S");
    $s = setStyle($s, "B7", fixtureStyle());
    assertStyleSurvived(styleAt($s, "B7"), fixtureStyle(), true);
    testing.assertTrue(isPlain(styleAt($s, "B8")));
}

func testStylesAreInterned() {
    # The point of the table: one entry however many cells point at it.
    def s as Sheet init newSheet("S");
    def st as Style init withBold(style(), true);
    $s = setAreaStyle($s, "A1:A100", $st);
    # The default plus the one style.
    testing.assertEqual(len($s.styles), 2);
    testing.assertEqual(len($s.cellStyles), 100);
    testing.assertTrue(styleAt($s, "A50").bold);
}

func testTwoDistinctStylesTakeTwoEntries() {
    def s as Sheet init newSheet("S");
    $s = setStyle($s, "A1", withBold(style(), true));
    $s = setStyle($s, "A2", withItalic(style(), true));
    $s = setStyle($s, "A3", withBold(style(), true));
    testing.assertEqual(len($s.styles), 3);
    testing.assertTrue(styleAt($s, "A3").bold);
}

func testSettingTheDefaultStyleRemovesIt() {
    def s as Sheet init newSheet("S");
    $s = setStyle($s, "A1", withBold(style(), true));
    $s = setStyle($s, "A1", style());
    testing.assertEqual(len($s.cellStyles), 0);
    testing.assertTrue(isPlain(styleAt($s, "A1")));
}

func testSetAreaStyleCanClearAnArea() {
    def s as Sheet init newSheet("S");
    $s = setAreaStyle($s, "A1:C3", withBold(style(), true));
    testing.assertEqual(len($s.cellStyles), 9);
    $s = setAreaStyle($s, "A1:B2", style());
    testing.assertEqual(len($s.cellStyles), 5);
    testing.assertTrue(isPlain(styleAt($s, "A1")));
    testing.assertTrue(styleAt($s, "C3").bold);
}

func testAStyleOnAnEmptyCellGrowsTheExtent() {
    # A blank cell with a background or a border has to be written, so the
    # extent follows styles as well as values.
    def s as Sheet init newSheet("S");
    $s = setStyle($s, "C4", withBackground(style(), "FFF2CC"));
    testing.assertEqual($s.rowCount, 4);
    testing.assertEqual($s.colCount, 3);
    testing.assertEqual(cellCount($s), 0);
}

func testAStyleIsIndependentOfItsValue() {
    def s as Sheet init newSheet("S");
    $s = setStyle($s, "A1", withBold(style(), true));
    $s = setCell($s, "A1", text("after"));
    testing.assertTrue(styleAt($s, "A1").bold);
    testing.assertEqual(asString(cell($s, "A1")), "after");
    $s = clearCell($s, "A1");
    testing.assertTrue(styleAt($s, "A1").bold);
}

func failOnStylingOffTheGrid() {
    setStyleAt(newSheet("S"), Ref{row: MAX_ROW + 1, col: 0}, withBold(style(), true));
}

func testSetStyleRefusesWhatIsOffTheGrid() {
    testing.assertThrows("failOnStylingOffTheGrid", ERROR_KIND);
}

func testStyleAtRefReadsByZeroBasedRowAndColumn() {
    # B7 is row 6, column 1: the same cell styleAt reaches by name.
    def s as Sheet init newSheet("S");
    $s = setStyle($s, "B7", withBold(style(), true));
    testing.assertTrue(styleAtRef($s, ref(6, 1)).bold);
    testing.assertTrue(isPlain(styleAtRef($s, ref(6, 2))));
    testing.assertTrue(isPlain(styleAtRef($s, ref(5, 1))));
}

func testStyleAtRefReadsADanglingIndexAsTheDefault() {
    def s as Sheet init newSheet("S");
    $s.cellStyles["A1"] = 99;
    testing.assertTrue(isPlain(styleAtRef($s, ref(0, 0))));
}
