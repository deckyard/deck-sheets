# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for ffnlogic.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# As in ffn_test.j, the expected values come from tools/formula-oracle.sh,
# which diffs this engine against LibreOffice and Gnumeric.

func testIf() {
    assertFn("IF(A1>B1,\"y\",\"n\")", "y");
    assertFn("IF(A1<B1,\"y\",\"n\")", "n");
    # With no third argument a false condition yields FALSE, not blank.
    assertFn("IF(A1>B1,\"y\")", "y");
    assertFn("IF(A1<B1,\"y\")", "FALSE");
    # A number condition is true when it is not zero.
    assertFn("IF(1,\"y\",\"n\")", "y");
    assertFn("IF(0,\"y\",\"n\")", "n");
}

func testIfIsLazy() {
    # The branch not taken must not be evaluated, or every IF guarding a
    # division would still report #DIV/0!. This is the whole reason the
    # dispatch takes expressions rather than values.
    assertFn("IF(B1=0,0,A1/B1)", "2");
    assertFn("IF(E1=0,0,A1/E1)", "0");
    assertFn("IF(TRUE,1,1/0)", "1");
    assertFn("IF(FALSE,1/0,1)", "1");
}

func testIfError() {
    assertFn("IFERROR(1/0,\"safe\")", "safe");
    assertFn("IFERROR(A1,\"safe\")", "4");
    assertFn("IFNA(NA(),\"safe\")", "safe");
    # IFNA catches only #N/A, so a division error passes through it.
    assertFn("IFNA(1/0,\"safe\")", "#DIV/0!");
    assertFn("IFERROR(NA(),\"safe\")", "safe");
}

func testAndOr() {
    assertFn("AND(A1>1,B1>1)", "TRUE");
    assertFn("AND(A1>1,B1>9)", "FALSE");
    assertFn("OR(A1>99,B1>1)", "TRUE");
    assertFn("OR(A1>99,B1>99)", "FALSE");
    # Comparing a whole span is an array expression, which this engine does
    # not evaluate; both applications answer #VALUE! rather than taking one
    # cell, and taking the first cell gave answers that looked right and were
    # not - `OR(A3:E3>4)` came back FALSE over a row ending in 5.
    assertFn("AND(A3:E3>0)", "#VALUE!");
    assertFn("OR(A3:E3>4)", "#VALUE!");
    # A span is fine where a list of values is wanted.
    assertFn("OR(A3>4,E3>4)", "TRUE");
}

func testNotAndXor() {
    assertFn("NOT(A1>1)", "FALSE");
    assertFn("NOT(FALSE)", "TRUE");
    assertFn("XOR(TRUE,FALSE)", "TRUE");
    assertFn("XOR(TRUE,TRUE)", "FALSE");
    assertFn("XOR(TRUE,TRUE,TRUE)", "TRUE");
    assertFn("TRUE()", "TRUE");
    assertFn("FALSE()", "FALSE");
}

func testIsFunctions() {
    assertFn("ISNUMBER(A1)", "TRUE");
    assertFn("ISNUMBER(D1)", "FALSE");
    assertFn("ISTEXT(D1)", "TRUE");
    assertFn("ISTEXT(A1)", "FALSE");
    assertFn("ISBLANK(E1)", "TRUE");
    assertFn("ISBLANK(A1)", "FALSE");
    assertFn("ISLOGICAL(A2)", "TRUE");
    assertFn("ISLOGICAL(A1)", "FALSE");
    assertFn("ISERROR(1/0)", "TRUE");
    assertFn("ISERROR(A1)", "FALSE");
    assertFn("ISNA(NA())", "TRUE");
    # ISNA is only #N/A, where ISERROR is any error.
    assertFn("ISNA(1/0)", "FALSE");
    assertFn("ISERROR(NA())", "TRUE");
}

func testNa() {
    assertFn("NA()", "#N/A");
}

func testCountFamily() {
    assertFn("COUNT(A1:E1)", "3");
    assertFn("COUNTA(A1:E1)", "4");
    assertFn("COUNTBLANK(A1:E1)", "1");
    assertFn("COUNTA(A2:E2)", "5");
}

func testCountSkipsBooleansInASpan() {
    # Row 2 is TRUE, FALSE, -7, "Beta", 1. COUNT answers 2: where a boolean
    # came from decides whether it counts, and one read out of a cell does
    # not. Gnumeric and Excel agree; this LibreOffice counts them, so the
    # oracle excludes the case.
    assertFn("COUNT(A2:E2)", "2");
    # A boolean written into the call does count.
    assertFn("COUNT(1,TRUE)", "2");
    assertFn("COUNT(A2)", "1");
}

func testCriterionOrderingIsClassScoped() {
    # A numeric criterion compares only against numbers: text and blanks are
    # skipped rather than coerced. Comparing type-blind over-counted by
    # including every text cell, which the oracle caught.
    assertFn("COUNTIF(A1:E1,\">1\")", "3");
    assertFn("COUNTIF(A1:E1,\"<5\")", "2");
    assertFn("COUNTIF(A1:E1,\">=2\")", "3");
    # A text criterion with an ordering operator compares against text.
    assertFn("COUNTIF(A1:E1,\">a\")", "1");
}

func testCriterionEquality() {
    assertFn("COUNTIF(A1:E1,2)", "1");
    assertFn("COUNTIF(A1:E1,\"beta\")", "1");
    assertFn("COUNTIF(A1:E1,\"=2\")", "1");
    # Inequality crosses classes, so the text and the blank both satisfy it.
    assertFn("COUNTIF(A1:E1,\"<>2\")", "4");
    assertFn("COUNTIF(A1:E1,\"<>beta\")", "4");
    # An empty criterion matches the blank cell and nothing else.
    assertFn("COUNTIF(A1:E1,\"\")", "1");
}

func testSumIf() {
    assertFn("SUMIF(A1:C1,\">3\")", "13.99");
    assertFn("SUMIF(A3:E3,\">2\")", "12");
    # A text criterion sums nothing, because text has no numeric value.
    assertFn("SUMIF(A1:E1,\"beta\")", "0");
    # A third argument sums a parallel span instead of the tested one.
    assertFn("SUMIF(A3:E3,\">2\",A3:E3)", "12");
}

func testVlookup() {
    # VLOOKUP searches the first *column* of the range. Over a single row
    # that column holds one cell, so looking for anything else misses - the
    # answer both applications give, and a trap worth pinning.
    assertFn("VLOOKUP(2,A3:E3,1,FALSE)", "#N/A");
    assertFn("VLOOKUP(1,A3:E3,1,FALSE)", "1");
    assertFn("VLOOKUP(1,A3:E3,3,FALSE)", "3");
    # An exact lookup that misses is #N/A, which is what IFNA is for.
    assertFn("VLOOKUP(99,A3:E3,1,FALSE)", "#N/A");
    assertFn("IFNA(VLOOKUP(99,A3:E3,1,FALSE),0)", "0");
    # A column index past the range is #REF! in Gnumeric and Excel; this
    # LibreOffice says #NUM!, so the oracle excludes it.
    assertFn("VLOOKUP(1,A3:E3,9,FALSE)", "#REF!");
}

func testHlookup() {
    assertFn("HLOOKUP(2,A3:E3,1,FALSE)", "2");
    assertFn("HLOOKUP(99,A3:E3,1,FALSE)", "#N/A");
}

func testIndex() {
    assertFn("INDEX(A3:E3,1,3)", "3");
    assertFn("INDEX(A3:E3,1,1)", "1");
    # Out of the block is a reference error, not a blank.
    assertFn("INDEX(A3:E3,1,9)", "#REF!");
    assertFn("INDEX(A3:E3,9,1)", "#REF!");
}

func testMatch() {
    # Type 0 is an exact match; type 1 finds the largest value not greater
    # than the target, over data assumed ascending.
    assertFn("MATCH(3,A3:E3,0)", "3");
    assertFn("MATCH(3,A3:E3,1)", "3");
    assertFn("MATCH(99,A3:E3,0)", "#N/A");
    # A target past the end of ascending data answers with the end of the
    # data, not #N/A. Searching for an exact match only gave #N/A, which the
    # oracle caught.
    assertFn("MATCH(99,A3:E3,1)", "5");
    assertFn("MATCH(0,A3:E3,1)", "#N/A");
    # The type defaults to 1, not to 0.
    assertFn("MATCH(99,A3:E3)", "5");
}

func testMatchDescending() {
    # Type -1 assumes descending data and answers the last position holding a
    # value no less than the target. The applications disagree over what an
    # ill-ordered search should give, so this uses properly ordered data.
    def wb as Workbook init addSheet(
        newWorkbook(),
        sheetOf("D", [[integer(5), integer(4), integer(3), integer(2), integer(1)]]));
    testing.assertEqual(asString(evaluate($wb, "D", "MATCH(3,A1:E1,-1)")), "3");
    testing.assertEqual(asString(evaluate($wb, "D", "MATCH(0,A1:E1,-1)")), "5");
    testing.assertEqual(asString(evaluate($wb, "D", "MATCH(9,A1:E1,-1)")), "#N/A");
}

func testRowAndColumn() {
    assertFn("ROW(B2)", "2");
    assertFn("COLUMN(C1)", "3");
    assertFn("ROWS(A1:C3)", "3");
    assertFn("COLUMNS(A1:C3)", "3");
    assertFn("ROWS(A1)", "1");
    assertFn("COLUMNS(A1:A9)", "1");
}

func testLookupsRefuseAMissingArgument() {
    assertFn("VLOOKUP(1)", "#VALUE!");
    assertFn("INDEX(A3:E3)", "#VALUE!");
    assertFn("MATCH(1)", "#VALUE!");
    assertFn("COUNTIF(A1:E1)", "#VALUE!");
}
