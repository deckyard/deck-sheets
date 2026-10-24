# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for ffntext.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# As in ffn_test.j, the expected values come from tools/formula-oracle.sh,
# which diffs this engine against LibreOffice and Gnumeric.

func testTextLength() {
    assertFn("LEN(D1)", "4");
    assertFn("LEN(\"\")", "0");
    # A number is measured by its rendering.
    assertFn("LEN(A1)", "1");
}

func testTextCase() {
    assertFn("UPPER(D1)", "BETA");
    assertFn("LOWER(\"ABC\")", "abc");
    assertFn("PROPER(\"hello world\")", "Hello World");
}

func testTextTrim() {
    # TRIM collapses runs of inner spaces as well as stripping the ends,
    # which a plain trim does not.
    assertFn("TRIM(\"  a  b  \")", "a b");
    assertFn("TRIM(D1)", "beta");
}

func testTextSlicing() {
    assertFn("LEFT(D1,2)", "be");
    # The count defaults to 1, not to the whole string.
    assertFn("LEFT(D1)", "b");
    assertFn("RIGHT(D1,2)", "ta");
    assertFn("MID(D1,2,2)", "et");
    # Starting past the end is empty text, not an error.
    assertFn("MID(D1,10,2)", "");
    assertFn("LEFT(D1,99)", "beta");
}

func testTextSearch() {
    # FIND is case-sensitive, SEARCH is not. That is the only difference
    # between them and the reason both exist.
    assertFn("FIND(\"t\",D1)", "3");
    assertFn("FIND(\"T\",D1)", "#VALUE!");
    assertFn("SEARCH(\"T\",D1)", "3");
    # A miss is #VALUE!, so IFERROR is how a sheet tests for a substring.
    assertFn("FIND(\"x\",D1)", "#VALUE!");
    assertFn("IFERROR(FIND(\"x\",D1),0)", "0");
}

func testTextSubstitution() {
    assertFn("SUBSTITUTE(D1,\"e\",\"E\")", "bEta");
    # The fourth argument picks one occurrence, counting from 1. Ignoring it
    # replaced every occurrence, which the oracle caught.
    assertFn("SUBSTITUTE(\"aaa\",\"a\",\"b\",2)", "aba");
    assertFn("SUBSTITUTE(\"aaa\",\"a\",\"b\")", "bbb");
    # An occurrence past the end leaves the text alone.
    assertFn("SUBSTITUTE(\"aaa\",\"a\",\"b\",9)", "aaa");
    # An empty needle would match everywhere; the text comes back untouched.
    assertFn("SUBSTITUTE(D1,\"\",\"X\")", "beta");
    assertFn("SUBSTITUTE(\"aaa\",\"a\",\"b\",0)", "#VALUE!");
}

func testTextReplacement() {
    # REPLACE works by position where SUBSTITUTE works by content.
    assertFn("REPLACE(D1,1,1,\"X\")", "Xeta");
    assertFn("REPLACE(D1,2,0,\"-\")", "b-eta");
}

func testTextRepetition() {
    assertFn("REPT(\"ab\",3)", "ababab");
    assertFn("REPT(\"ab\",0)", "");
    # The cap is what stops a formula from asking for a gigabyte of text.
    assertFn("REPT(\"ab\",999999)", "#VALUE!");
}

func testTextComparison() {
    # EXACT is the case-sensitive comparison; `=` is not.
    assertFn("EXACT(D1,\"beta\")", "TRUE");
    assertFn("EXACT(D1,D2)", "FALSE");
    assertFn("D1=D2", "TRUE");
}

func testTextJoining() {
    assertFn("CONCATENATE(D1,\"!\")", "beta!");
    assertFn("CONCAT(D1,\"-\",D2)", "beta-Beta");
    assertFn("CONCATENATE(A1,B1)", "42");
}

func testTextCharacterCodes() {
    assertFn("CODE(\"A\")", "65");
    assertFn("CHAR(65)", "A");
    assertFn("CODE(\"\")", "#VALUE!");
    assertFn("CHAR(0)", "#VALUE!");
}

func testTextCoercionFunctions() {
    # T yields text only for text, N numbers only for numbers. Both are empty
    # or zero otherwise rather than an error.
    assertFn("T(D1)", "beta");
    assertFn("T(A1)", "");
    assertFn("N(A1)", "4");
    assertFn("N(D1)", "0");
    assertFn("VALUE(\"12.5\")", "12.5");
    assertFn("VALUE(D1)", "#VALUE!");
}

func testTextFormatting() {
    # TEXT renders a number through a format code. Only the codes the deck's
    # own style layer understands are supported.
    assertFn("TEXT(A1,\"0.00\")", "4.00");
    assertFn("TEXT(C1,\"0\")", "10");
}

func testDateConstruction() {
    assertFn("DATE(2026,10,2)", "2026-10-02");
    # A month or day past the end of its range rolls over, which is how a
    # sheet does date arithmetic without a dedicated function.
    assertFn("DATE(2026,13,1)", "2027-01-01");
    assertFn("DATE(2026,1,32)", "2026-02-01");
    assertFn("DATE(2026,0,1)", "2025-12-01");
}

func testDateParts() {
    assertFn("YEAR(DATE(2026,10,2))", "2026");
    assertFn("MONTH(DATE(2026,10,2))", "10");
    assertFn("DAY(DATE(2026,10,2))", "2");
    assertFn("HOUR(DATE(2026,10,2))", "0");
    assertFn("MINUTE(DATE(2026,10,2))", "0");
    assertFn("SECOND(DATE(2026,10,2))", "0");
}

func testWeekdayHonoursItsSecondArgument() {
    # 2 October 2026 is a Friday. Type 1 counts from Sunday as 1, type 2 from
    # Monday as 1, type 3 from Monday as 0. Ignoring the argument made every
    # type answer as type 1, which the oracle caught.
    assertFn("WEEKDAY(DATE(2026,10,2))", "6");
    assertFn("WEEKDAY(DATE(2026,10,2),1)", "6");
    assertFn("WEEKDAY(DATE(2026,10,2),2)", "5");
    assertFn("WEEKDAY(DATE(2026,10,2),3)", "4");
    # Types 11 to 17 start the week on Monday through Sunday.
    assertFn("WEEKDAY(DATE(2026,10,2),11)", "5");
    assertFn("WEEKDAY(DATE(2026,10,2),15)", "1");
    assertFn("WEEKDAY(DATE(2026,10,2),17)", "6");
    assertFn("WEEKDAY(DATE(2026,10,2),4)", "#NUM!");
}

func testDateArithmetic() {
    assertFn("DAYS(DATE(2026,10,2),DATE(2026,10,1))", "1");
    assertFn("DAYS(DATE(2026,10,1),DATE(2026,10,2))", "-1");
    assertFn("YEAR(DATEVALUE(\"2026-10-02\"))", "2026");
    assertFn("DATEVALUE(\"not a date\")", "#VALUE!");
}

func testEdateClampsToTheEndOfTheMonth() {
    # One month after 31 January is 28 February, not 3 March: the day is
    # clamped, not rolled. Both applications agree, and rolling it over was
    # the bug the oracle caught.
    assertFn("EDATE(DATE(2026,1,31),1)", "2026-02-28");
    assertFn("EDATE(DATE(2026,1,31),13)", "2027-02-28");
    assertFn("EDATE(DATE(2024,1,31),1)", "2024-02-29");
    assertFn("EDATE(DATE(2026,3,15),-1)", "2026-02-15");
    assertFn("EDATE(DATE(2026,1,15),0)", "2026-01-15");
    # Crossing a year boundary in either direction.
    assertFn("EDATE(DATE(2026,12,15),1)", "2027-01-15");
    assertFn("EDATE(DATE(2026,1,15),-1)", "2025-12-15");
}

func testTodayAndNowAreDates() {
    # The value moves, so only its shape can be asserted. TODAY has no time
    # of day; NOW does.
    def wb as Workbook init fnFixture();
    def today as Value init evaluate($wb, "S", "YEAR(TODAY())>2000");
    testing.assertEqual(asString($today), "TRUE");
    def now as Value init evaluate($wb, "S", "NOW()>=TODAY()");
    testing.assertEqual(asString($now), "TRUE");
}

func testMaxTextResultIsExcelsCellLimit() {
    testing.assertEqual(MAX_TEXT_RESULT, 32767);
}

func testTextFunctionsRefuseMissingArguments() {
    assertFn("LEFT()", "#VALUE!");
    assertFn("MID(D1,1)", "#VALUE!");
    assertFn("SUBSTITUTE(D1,\"a\")", "#VALUE!");
    assertFn("DATE(2026,1)", "#VALUE!");
}
