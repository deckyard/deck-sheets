# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for fdialect.j.
# Spliced into sheets_test.j via include - not a standalone module.

/**
 * Assert that a formula survives a trip to OpenFormula and back.
 *
 * The property that matters: a conversion must not change what a formula
 * means. Both directions are checked, because a translator that is wrong in
 * one direction only is still a translator that corrupts files.
 *
 * @param a1 {string} the A1 spelling
 * @param openFormula {string} the OpenFormula spelling
 */
func assertDialectPair(a1 as string, openFormula as string) {
    testing.assertEqual(toOpenFormula($a1), $openFormula);
    testing.assertEqual(toA1Formula($openFormula), $a1);
    testing.assertEqual(toA1Formula(toOpenFormula($a1)), $a1);
}

func testASingleReference() {
    assertDialectPair("B3", "[.B3]");
    assertDialectPair("A1", "[.A1]");
    assertDialectPair("XFD1048576", "[.XFD1048576]");
}

func testArithmeticBetweenReferences() {
    assertDialectPair("B3*C2", "[.B3]*[.C2]");
    assertDialectPair("A1+A2-A3", "[.A1]+[.A2]-[.A3]");
    assertDialectPair("(A1+A2)/2", "([.A1]+[.A2])/2");
}

func testARange() {
    assertDialectPair("SUM(A1:A5)", "SUM([.A1:.A5])");
    assertDialectPair("SUM(A1:B10)", "SUM([.A1:.B10])");
}

func testArgumentSeparatorsSwap() {
    # The separator is the other half of the dialect: A1 uses a comma, and
    # OpenFormula a semicolon.
    assertDialectPair("SUM(A1,A2)", "SUM([.A1];[.A2])");
    assertDialectPair("IF(A1>0,A2,A3)", "IF([.A1]>0;[.A2];[.A3])");
}

func testAbsoluteReferencesKeepTheirDollars() {
    assertDialectPair("$B$3", "[.$B$3]");
    assertDialectPair("B$3*$C2", "[.B$3]*[.$C2]");
}

func testCrossSheetReferences() {
    assertDialectPair("Sheet2!B3", "[Sheet2.B3]");
    assertDialectPair("Sheet2!A1+B1", "[Sheet2.A1]+[.B1]");
}

func testAQuotedSheetName() {
    assertDialectPair("'Second Sheet'!B3", "['Second Sheet'.B3]");
}

func testASheetQualifiedRangeRepeatsTheSheetInOpenFormula() {
    # A1 names the sheet once; OpenFormula puts it on both halves.
    testing.assertEqual(toOpenFormula("Sheet2!A1:A5"), "[Sheet2.A1:.A5]");
    testing.assertEqual(toA1Formula("[Sheet2.A1:Sheet2.A5]"), "Sheet2!A1:A5");
}

func testStringLiteralsArePreserved() {
    assertDialectPair("CONCATENATE(A1,\" and \",B1)", "CONCATENATE([.A1];\" and \";[.B1])");
}

func testASeparatorInsideAStringIsNotASeparator() {
    # The whole reason this is a tokeniser: a search and replace over the
    # separator would corrupt the literal.
    testing.assertEqual(toOpenFormula("CONCATENATE(A1,\"a,b\")"), "CONCATENATE([.A1];\"a,b\")");
    testing.assertEqual(toA1Formula("CONCATENATE([.A1];\"a;b\")"), "CONCATENATE(A1,\"a;b\")");
}

func testABracketInsideAStringIsNotAReference() {
    testing.assertEqual(toA1Formula("CONCATENATE(\"[.A1]\";[.B1])"), "CONCATENATE(\"[.A1]\",B1)");
}

func testSomethingThatLooksLikeAReferenceInsideAStringIsLeftAlone() {
    testing.assertEqual(toOpenFormula("\"B3\""), "\"B3\"");
    testing.assertEqual(toOpenFormula("CONCATENATE(\"B3\",B3)"), "CONCATENATE(\"B3\";[.B3])");
}

func testADoubledQuoteInsideAStringDoesNotCloseIt() {
    testing.assertEqual(
        toOpenFormula("CONCATENATE(\"a\"\"b\",A1)"),
        "CONCATENATE(\"a\"\"b\";[.A1])");
}

func testAFunctionNameEndingInDigitsIsNotAReference() {
    # LOG10 is the case a naive letters-then-digits scan gets wrong.
    testing.assertEqual(toOpenFormula("LOG10(A1)"), "LOG10([.A1])");
    testing.assertEqual(toOpenFormula("ATAN2(A1,B1)"), "ATAN2([.A1];[.B1])");
    testing.assertEqual(toOpenFormula("SUMX2MY2(A1,B1)"), "SUMX2MY2([.A1];[.B1])");
}

func testANamedRangeIsNotAReference() {
    # A bare name with no digits is not a cell, so it passes through.
    testing.assertEqual(toOpenFormula("SUM(Revenue)"), "SUM(Revenue)");
    testing.assertEqual(toOpenFormula("TotalCost*2"), "TotalCost*2");
}

func testANumberIsNotAReference() {
    testing.assertEqual(toOpenFormula("1+2"), "1+2");
    testing.assertEqual(toOpenFormula("A1*1.5"), "[.A1]*1.5");
    testing.assertEqual(toOpenFormula("1E5"), "1E5");
}

func testAColumnNameLongerThanThreeLettersIsNotAReference() {
    # No column reaches four letters, so this is a name.
    testing.assertEqual(toOpenFormula("ABCD1"), "ABCD1");
}

func testComparisonsAndTextOperators() {
    assertDialectPair("A1<>B1", "[.A1]<>[.B1]");
    assertDialectPair("A1&B1", "[.A1]&[.B1]");
    assertDialectPair("A1>=B1", "[.A1]>=[.B1]");
}

func testAnEmptyFormulaIsLeftAlone() {
    testing.assertEqual(toOpenFormula(""), "");
    testing.assertEqual(toA1Formula(""), "");
}

func testNestedFunctions() {
    assertDialectPair("IF(SUM(A1:A5)>10,MAX(B1:B5),0)", "IF(SUM([.A1:.A5])>10;MAX([.B1:.B5]);0)");
}

func testAnUnterminatedStringDoesNotLoseTheRest() {
    # Damage, not bad data: keep what can be read rather than refusing. The
    # literal is closed on the way out (the input had no closing paren either,
    # and inventing one would be a guess).
    testing.assertEqual(toOpenFormula("CONCATENATE(A1,\"tail"), "CONCATENATE([.A1];\"tail\"");
}

func testAnUnclosedBracketDoesNotHang() {
    testing.assertEqual(toA1Formula("SUM([.A1"), "SUM(A1");
}

func testALongFormulaIsTranslatedInLinearTime() {
    # The regression this guards. Two separate quadratics lived here: the
    # tokeniser threaded its growing piece list through a helper, and it read
    # the source with `strings.substring($s, $i, $i + 1)`, which is
    # rune-indexed and so walks i runes per character. A 6 KB formula took
    # 3 802 ms; it now takes about 100 ms, and a 24 KB one scales linearly
    # rather than to 77 s.
    def terms as list of string init [];
    for (def i in 0..4000) {
        $terms[] = "A1";
    }
    def source as string init strings.join($terms, "+");
    def started as time.Time init time.now();
    def out as string init toOpenFormula($source);
    def elapsed as int init time.milliseconds(time.sub(time.now(), $started));
    testing.assertTrue(strings.startsWith($out, "[.A1]+[.A1]"));
    testing.assertEqual(len($out), len($source) + 4000 * 3);
    testing.assertTrue($elapsed < 10000);
}

func testALongFormulaRoundTripsBothWays() {
    def terms as list of string init [];
    for (def i in 0..500) {
        $terms[] = "B" + convert.toString($i + 1);
    }
    def source as string init strings.join($terms, "+");
    testing.assertEqual(toA1Formula(toOpenFormula($source)), $source);
}

func testAQualifierScanDoesNotRunToTheEndOfTheFormula() {
    # `sheetQualifierEnd` used to search the whole remainder for a `!`, which
    # made every character position cost the document's length. A formula with
    # no `!` in it at all is the case that exposed it.
    def terms as list of string init [];
    for (def i in 0..2000) {
        $terms[] = "C1";
    }
    def source as string init strings.join($terms, "*");
    def started as time.Time init time.now();
    testing.assertTrue(len(toOpenFormula($source)) > len($source));
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 10000);
}
