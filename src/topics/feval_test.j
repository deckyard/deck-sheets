# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for feval.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# Every expected value in this overlay was checked against LibreOffice 26.8
# and Gnumeric before being written down: `tools/formula-oracle.sh` writes the
# formulas into an .ods, has both applications compute them, and diffs their
# answers against this engine's. Where a spreadsheet disagrees with ordinary
# programming-language intuition, the spreadsheet wins.

/**
 * A workbook with one sheet of fixed inputs, used by most tests here.
 *
 * A1=4, B1=2, C1=9.99, D1="beta", E1 blank, A2=TRUE, B2=FALSE.
 *
 * @return {Workbook} the fixture
 */
func evalFixture() {
    return addSheet(
        newWorkbook(),
        sheetOf(
            "S",
            [
                [integer(4), integer(2), number(9.99), text("beta"), empty()],
                [boolean(true), boolean(false)]
            ]));
}

/**
 * Evaluate one formula against the fixture and render the result.
 *
 * @param source {string} the formula
 * @return {string} the result as text
 */
func evalText(source as string) {
    def wb as Workbook init evalFixture();
    return asString(evaluate($wb, "S", $source));
}

/**
 * Assert what a formula evaluates to against the fixture.
 *
 * @param source {string} the formula
 * @param want {string} the expected rendering
 */
func assertEval(source as string, want as string) {
    testing.assertEqual(evalText($source), $want);
}

func testEvaluateLiterals() {
    assertEval("1", "1");
    assertEval("12.5", "12.5");
    assertEval("\"abc\"", "abc");
    assertEval("TRUE", "TRUE");
    assertEval("#N/A", "#N/A");
}

func testEvaluateArithmetic() {
    assertEval("A1+B1", "6");
    assertEval("A1-B1", "2");
    assertEval("A1*B1", "8");
    assertEval("A1/B1", "2");
    assertEval("A1^B1", "16");
    assertEval("2+3*4^2", "50");
}

func testEvaluatePowerAndUnaryFollowTheSpreadsheets() {
    # Both checked against LibreOffice and Gnumeric: `^` leans left and unary
    # minus binds tighter than it. Most languages do neither.
    assertEval("2^3^2", "64");
    assertEval("-2^2", "4");
    assertEval("-2^2*3", "12");
    assertEval("-(2^2)", "-4");
}

func testEvaluatePercent() {
    assertEval("50%", "0.5");
    assertEval("100%*2", "2");
}

func testEvaluateConcatenation() {
    assertEval("A1&D1", "4beta");
    assertEval("\"a\"&\"b\"&\"c\"", "abc");
    # A number keeps its own rendering when it joins text.
    assertEval("C1&\"\"", "9.99");
}

func testEvaluateComparisons() {
    assertEval("A1=4", "TRUE");
    assertEval("A1<>4", "FALSE");
    assertEval("A1<B1", "FALSE");
    assertEval("A1>=B1", "TRUE");
    # Text compares case-insensitively, as both applications do.
    assertEval("D1=\"BETA\"", "TRUE");
    # Across classes the order is number < text < boolean, so any text is
    # greater than any number.
    assertEval("D1>A1", "TRUE");
}

func testEvaluateBlankCoercion() {
    # A blank cell takes the class of the other side, so it is both 0 and "".
    assertEval("E1+1", "1");
    assertEval("E1=0", "TRUE");
    assertEval("E1=\"\"", "TRUE");
    assertEval("A1&E1", "4");
}

func testEvaluateErrors() {
    assertEval("1/0", "#DIV/0!");
    assertEval("SQRT(-1)", "#NUM!");
    # 0 to a negative power is `#NUM!` in both applications, not `#DIV/0!`.
    assertEval("0^-1", "#NUM!");
    assertEval("\"a\"+1", "#VALUE!");
    assertEval("NoSuchName", "#NAME?");
    assertEval("NOSUCHFUNC(1)", "#NAME?");
}

func testEvaluateErrorsPropagate() {
    # An error in an operand is the result of the whole expression, and the
    # first one wins.
    assertEval("1/0+1", "#DIV/0!");
    assertEval("SUM(1/0,1)", "#DIV/0!");
    assertEval("#N/A+1", "#N/A");
}

func testEvaluateCellReferences() {
    assertEval("A1", "4");
    assertEval("$A$1", "4");
    assertEval("S!A1", "4");
    # A reference off the used range is blank, not an error.
    assertEval("Z99", "");
}

func testEvaluateFollowsAFormulaCell() {
    def wb as Workbook init addSheet(
        newWorkbook(),
        sheetOf("S", [[integer(4)], [formula("A1*2", "")]]));
    # The cached result is ignored: the chain is evaluated afresh.
    testing.assertEqual(asString(evaluate($wb, "S", "A2+1")), "9");
}

func testEvaluateCrossSheetReferences() {
    def wb as Workbook init addSheet(
        addSheet(newWorkbook(), sheetOf("Main", [[integer(3)]])),
        sheetOf("Other Sheet", [[integer(10)]]));
    testing.assertEqual(asString(evaluate($wb, "Main", "'Other Sheet'!A1*A1")), "30");
    testing.assertEqual(asString(evaluate($wb, "Main", "Main!A1")), "3");
    # A sheet that is not there is a reference error, not a throw.
    testing.assertEqual(asString(evaluate($wb, "Main", "Nope!A1")), "#REF!");
}

func testEvaluateDetectsCycles() {
    def wb as Workbook init addSheet(
        newWorkbook(),
        sheetOf("C", [[formula("A1+1", "")], [formula("A3", "")], [formula("A2", "")]]));
    # A self-reference and a mutual pair are both cycles, and neither may
    # recurse until the stack goes.
    testing.assertEqual(asString(evaluate($wb, "C", "A1")), ERR_CIRCULAR);
    testing.assertEqual(asString(evaluate($wb, "C", "A2")), ERR_CIRCULAR);
    testing.assertEqual(asString(evaluate($wb, "C", "A3")), ERR_CIRCULAR);
}

func testEvaluateFollowsALongChain() {
    # 200 cells each pointing at the one below. Bounding the *recursion* to
    # keep the interpreter alive used to make this `#REF!`, which is a wrong
    # answer for an ordinary running-total column; resolution is iterative
    # now, so chain length is bounded by MAX_RESOLVED_CELLS instead.
    def lines as list of list of Value init [];
    for (def i in 0..200) {
        $lines[] = [formula("A" + convert.toString($i + 2), "")];
    }
    $lines[] = [integer(1)];
    def wb as Workbook init addSheet(newWorkbook(), sheetOf("D", $lines));
    testing.assertEqual(asString(evaluate($wb, "D", "A1")), "1");
}

func testEvaluateComputesAFanOutOnce() {
    # Each cell references the one above it twice. Re-evaluating per
    # reference costs 2^n, so depth 16 measured 15.9 s and depth 20 did not
    # finish; each cell is computed once now.
    def lines as list of list of Value init [[integer(2)]];
    for (def i in 1..21) {
        def above as string init "A" + convert.toString($i);
        $lines[] = [formula($above + "+" + $above, "")];
    }
    def wb as Workbook init addSheet(newWorkbook(), sheetOf("F", $lines));
    # 2 doubled twenty times.
    testing.assertEqual(asString(evaluate($wb, "F", "A21")), "2097152");
}

func testEvaluateFindsACycleBuriedInALongChain() {
    # The last cell of a 200-long chain points back at the first.
    def lines as list of list of Value init [[formula("A200", "")]];
    for (def i in 1..200) {
        $lines[] = [formula("A" + convert.toString($i) + "+1", "")];
    }
    def wb as Workbook init addSheet(newWorkbook(), sheetOf("C", $lines));
    testing.assertEqual(asString(evaluate($wb, "C", "A1")), ERR_CIRCULAR);
}

func testMaxResolvedCellsIsTheWorkBudget() {
    # Resolution is memoised, so this counts distinct cells rather than
    # evaluations, and bounds the work one evaluation can ask for.
    testing.assertEqual(MAX_RESOLVED_CELLS, 500000);
}

func failOnEvaluateMissingSheet() {
    def wb as Workbook init evalFixture();
    evaluate($wb, "Nope", "1");
}

func testEvaluateRefusesAnAbsentStartingSheet() {
    # A bad reference inside a formula is a cell error, but being asked to
    # evaluate against a sheet that does not exist is a caller mistake.
    testing.assertThrows("failOnEvaluateMissingSheet", ERROR_KIND);
}

func testRecalculateWritesCachedResults() {
    def wb as Workbook init addSheet(
        newWorkbook(),
        sheetOf(
            "S",
            [
                [integer(4), integer(2)],
                [formula("A1*B1", ""), formula("A2+1", "")],
                [formula("SUM(A1:B2)", ""), text("plain")]
            ]));
    def done as Recalculated init recalculate($wb, "S");
    testing.assertEqual($done.evaluated, 3);
    testing.assertEqual($done.failed, 0);
    testing.assertEqual(asString(cell($done.sheet, "A2")), "8");
    testing.assertEqual(asString(cell($done.sheet, "B2")), "9");
    testing.assertEqual(asString(cell($done.sheet, "A3")), "23");
    # Non-formula cells are untouched.
    testing.assertEqual(asString(cell($done.sheet, "B3")), "plain");
}

func testRecalculateKeepsTheFormulaSource() {
    def wb as Workbook init addSheet(
        newWorkbook(),
        sheetOf("S", [[integer(2), formula("A1*3", "")]]));
    def done as Recalculated init recalculate($wb, "S");
    def again as Value init cell($done.sheet, "B1");
    match ($again) {
        when Formula(f) {
            # The source has to survive, or a recalculation would turn every
            # formula in the file into a literal.
            testing.assertEqual($f.source, "A1*3");
            testing.assertEqual($f.cached, "6");
        }
        else {
            throw Error{
                kind: "test",
                message: "recalculate dropped the formula",
                file: "",
                line: 0,
                col: 0
            };
        }
    }
}

func testRecalculateCountsFailures() {
    def wb as Workbook init addSheet(
        newWorkbook(),
        sheetOf("S", [[formula("1/0", ""), formula("1+1", "")]]));
    def done as Recalculated init recalculate($wb, "S");
    testing.assertEqual($done.evaluated, 2);
    testing.assertEqual($done.failed, 1);
    testing.assertEqual(asString(cell($done.sheet, "A1")), "#DIV/0!");
}

func testRecalculateOnASheetWithNoFormulas() {
    def wb as Workbook init addSheet(newWorkbook(), sheetOf("S", [[integer(1), text("x")]]));
    def done as Recalculated init recalculate($wb, "S");
    testing.assertEqual($done.evaluated, 0);
    testing.assertEqual($done.failed, 0);
}

func testIsErrorValue() {
    testing.assertTrue(isErrorValue(Value.Err{code: ERR_DIV0}));
    testing.assertFalse(isErrorValue(integer(1)));
    testing.assertFalse(isErrorValue(empty()));
    testing.assertFalse(isErrorValue(text("#DIV/0!")));
    # A formula cell whose cached result is an error code is not itself an
    # error value: the cache is text until it is evaluated.
    testing.assertFalse(isErrorValue(formula("1/0", "#DIV/0!")));
}

func testMaxRangeCellsBoundsASpan() {
    # A span the size of the whole grid must be refused by the cap rather
    # than materialised.
    testing.assertTrue(MAX_RANGE_CELLS > 0);
    testing.assertEqual(evalText("SUM(A1:XFD1048576)"), "#NUM!");
}

func testMaxFormulaDepthIsExcelsLimit() {
    testing.assertEqual(MAX_FORMULA_DEPTH, 64);
}

func testTextGrowthIsCappedWellAboveTheCellLimit() {
    # Both applications let an intermediate value run past what a cell can
    # hold, so the cap is not the cell limit: `LEN(a&b)` over two maximal
    # strings is 65 534 in LibreOffice and Gnumeric, and must be here too.
    def wb as Workbook init evalFixture();
    def joined as Value init evaluate($wb, "S", "LEN(REPT(\"x\",32767)&REPT(\"x\",32767))");
    testing.assertEqual(asString($joined), "65534");
    testing.assertTrue(MAX_TEXT_GROWTH > MAX_TEXT_RESULT * 2);
}

func testTextGrowthIsCappedAcrossAChainOfCells() {
    # The shape the cap exists for. Each cell doubles the one above it, so
    # the formulas stay tiny - well inside MAX_FORMULA_TOKENS - while the
    # text they build grows exponentially. Without the cap a chain of 64,
    # which MAX_FORMULA_DEPTH permits, reaches 2^64 characters.
    def lines as list of list of Value init [[text("abcd")]];
    for (def i in 1..40) {
        def above as string init "A" + convert.toString($i);
        $lines[] = [formula($above + "&" + $above, "")];
    }
    def wb as Workbook init addSheet(newWorkbook(), sheetOf("Grow", $lines));
    # 4 characters doubled 18 times is 1 048 576, still under the cap.
    testing.assertEqual(asString(evaluate($wb, "Grow", "LEN(A19)")), "1048576");
    # Two more doublings pass it, and the error propagates up the chain.
    testing.assertEqual(asString(evaluate($wb, "Grow", "A21")), ERR_VALUE);
    testing.assertEqual(asString(evaluate($wb, "Grow", "A40")), ERR_VALUE);
}

func failOnRecalculateMissingSheet() {
    def wb as Workbook init evalFixture();
    recalculate($wb, "Nope");
}

func testRecalculateRefusesAnAbsentSheet() {
    testing.assertThrows("failOnRecalculateMissingSheet", ERROR_KIND);
}

func testRecalculateKeepsStylesAndExtent() {
    # The sheet is rebuilt rather than updated cell by cell, so everything
    # that is not a cell value has to survive the rebuild.
    def s as Sheet init sheetOf(
        "S",
        [[integer(2), formula("A1*3", "")], [integer(5), text("tail")]]);
    $s = setStyle($s, "A1", withBold(style(), true));
    def wb as Workbook init addSheet(newWorkbook(), $s);
    def done as Recalculated init recalculate($wb, "S");
    testing.assertEqual($done.sheet.name, "S");
    testing.assertEqual($done.sheet.rowCount, 2);
    testing.assertEqual($done.sheet.colCount, 2);
    testing.assertTrue(styleAt($done.sheet, "A1").bold);
    testing.assertEqual(asString(cell($done.sheet, "B2")), "tail");
    testing.assertEqual(asString(cell($done.sheet, "B1")), "6");
}
