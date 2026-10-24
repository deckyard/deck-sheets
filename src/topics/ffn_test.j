# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for ffn.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# The expected values here were taken from tools/formula-oracle.sh, which
# evaluates the same formulas in LibreOffice and Gnumeric and diffs all three
# answers. Where a spreadsheet disagrees with programming-language intuition,
# the spreadsheet wins, and the comment says so.

/**
 * The fixture tools/formula-oracle.txt documents, in a workbook.
 *
 *   A1=4  B1=2  C1=9.99  D1="beta"  E1=blank
 *   A2=TRUE  B2=FALSE  C2=-7  D2="Beta"  E2=1
 *   A3=1  B3=2  C3=3  D3=4  E3=5
 *
 * @return {Workbook} the fixture
 */
func fnFixture() {
    return addSheet(
        newWorkbook(),
        sheetOf(
            "S",
            [
                [integer(4), integer(2), number(9.99), text("beta"), empty()],
                [boolean(true), boolean(false), integer(-7), text("Beta"), integer(1)],
                [integer(1), integer(2), integer(3), integer(4), integer(5)]
            ]));
}

/**
 * Assert what a formula evaluates to against the shared fixture.
 *
 * @param source {string} the formula
 * @param want {string} the expected rendering
 */
func assertFn(source as string, want as string) {
    def wb as Workbook init fnFixture();
    testing.assertEqual(asString(evaluate($wb, "S", $source)), $want);
}

func testAggregates() {
    assertFn("SUM(A1:C1)", "15.99");
    assertFn("SUM(A3:E3)", "15");
    assertFn("SUM(1,2,3)", "6");
    # Several spans in one call, which is what a real sheet does.
    # Plain double accumulation, as both applications do: they also store the
    # unrounded value in the file and round only for display.
    assertFn("SUM(A1:C1,A3:C3)", "21.990000000000002");
    assertFn("AVERAGE(A1:B1)", "3");
    assertFn("MIN(A1:C1)", "2");
    assertFn("MAX(A1:C1)", "9.99");
    assertFn("PRODUCT(A1:B1)", "8");
    assertFn("MEDIAN(A3:E3)", "3");
    assertFn("SUMSQ(A3:C3)", "14");
}

func testAggregatesIgnoreTextAndBlanks() {
    # SUM over a span holding text and a gap adds only the numbers; it is not
    # an error and the text is not zero-coerced.
    assertFn("SUM(A1:E1)", "15.99");
    assertFn("COUNT(A1:E1)", "3");
    assertFn("COUNTA(A1:E1)", "4");
    assertFn("COUNTBLANK(A1:E1)", "1");
}

func testStatistics() {
    # Sample against population: STDEV divides by n-1, STDEVP by n.
    assertFn("STDEV(A3:E3)", "1.5811388300841898");
    assertFn("STDEVP(A3:E3)", "1.4142135623730951");
    assertFn("VAR(A3:E3)", "2.5");
    assertFn("VARP(A3:E3)", "2");
}

func testRounding() {
    assertFn("ROUND(C1,1)", "10");
    assertFn("ROUND(C1,0)", "10");
    assertFn("ROUND(C1,-1)", "10");
    assertFn("ROUNDUP(C1,0)", "10");
    assertFn("ROUNDDOWN(C1,0)", "9");
    # INT floors towards minus infinity; TRUNC cuts towards zero. They differ
    # on negatives, which is the whole reason both exist.
    assertFn("INT(C1)", "9");
    assertFn("INT(C2)", "-7");
    assertFn("TRUNC(C1)", "9");
    assertFn("TRUNC(C2)", "-7");
    assertFn("CEILING(C1,1)", "10");
    assertFn("FLOOR(C1,1)", "9");
    assertFn("EVEN(3)", "4");
    assertFn("ODD(4)", "5");
}

func testNumberTheory() {
    assertFn("ABS(C2)", "7");
    assertFn("SIGN(C2)", "-1");
    assertFn("SIGN(0)", "0");
    assertFn("SQRT(A1)", "2");
    # MOD takes the sign of the divisor, which is the mathematical convention
    # and not what most languages' `%` does.
    assertFn("MOD(7,3)", "1");
    assertFn("MOD(-7,3)", "2");
    assertFn("MOD(7,-3)", "-2");
    assertFn("POWER(A1,B1)", "16");
    assertFn("QUOTIENT(7,2)", "3");
    assertFn("GCD(12,18)", "6");
    assertFn("LCM(4,6)", "12");
    assertFn("FACT(4)", "24");
}

func testTranscendental() {
    assertFn("EXP(0)", "1");
    assertFn("LN(1)", "0");
    assertFn("LOG10(100)", "2");
    assertFn("LOG(8,2)", "3");
    assertFn("SIN(0)", "0");
    assertFn("COS(0)", "1");
    assertFn("TAN(0)", "0");
    assertFn("ASIN(0)", "0");
    assertFn("ACOS(1)", "0");
    assertFn("ATAN(0)", "0");
    # ATAN2 in a spreadsheet takes x first, the opposite of C's argument
    # order, so this is pi/2 rather than 0.
    assertFn("ATAN2(1,0)", "0");
    assertFn("SQRTPI(1)", "1.7724538509055159");
}

func testPiTakesNoArgument() {
    # PI is dispatched with the one-argument numeric family but has no
    # argument, so the arity check has to let it through.
    assertFn("PI()", "3.141592653589793");
    assertFn("DEGREES(PI())", "180");
    assertFn("RADIANS(180)=PI()", "TRUE");
}

func testNumericFunctionsReportTheirDomain() {
    assertFn("SQRT(-1)", "#NUM!");
    assertFn("LOG(0)", "#NUM!");
    assertFn("ACOS(2)", "#NUM!");
    assertFn("FACT(-1)", "#NUM!");
    # A zero divisor is #DIV/0! where every other domain error is #NUM!.
    assertFn("MOD(1,0)", "#DIV/0!");
    assertFn("QUOTIENT(1,0)", "#DIV/0!");
    assertFn("LOG(1,0)", "#NUM!");
}

func testTextArgumentsToNumericFunctionsAreValueErrors() {
    assertFn("SQRT(D1)", "#VALUE!");
    assertFn("ABS(D1)", "#VALUE!");
}

func testUnknownFunctionIsANameError() {
    assertFn("NOSUCHFUNC(1)", "#NAME?");
    assertFn("SUMMM(A1:A3)", "#NAME?");
}

func testArgumentsAreFlattenedAcrossSpans() {
    # An aggregate takes spans, single cells and literals in any mixture.
    assertFn("SUM(A3,B3:C3,4)", "10");
    assertFn("COUNT(A3:E3,\"x\",7)", "6");
}
