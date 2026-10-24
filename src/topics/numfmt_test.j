# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for numfmt.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# Every expected rendering here came from LibreOffice and Gnumeric, through
# tools/formula-oracle.sh for the codes and tools/format-oracle.sh for the
# cells. Where the two applications disagree the exclusion list at the top of
# tools/formula-oracle.txt says which one this follows and why.

/**
 * Assert what a number renders as through a format code.
 *
 * @param amount {float} the number
 * @param code {string} the format code
 * @param want {string} the expected rendering
 */
func assertFormat(amount as float, code as string, want as string) {
    testing.assertEqual(applyFormat(number($amount), $code), $want);
}

func testFormatFixedPlaces() {
    assertFormat(1234.567, "0", "1235");
    assertFormat(1234.567, "0.00", "1234.57");
    assertFormat(1234.567, "0.000", "1234.567");
    assertFormat(1234.567, "0.0000", "1234.5670");
    assertFormat(0.0, "0.00", "0.00");
}

func testFormatOptionalPlaces() {
    # `#` drops a digit it does not need; `0` keeps the place.
    assertFormat(0.5, "0.##", "0.5");
    assertFormat(1.05, "0.##", "1.05");
    assertFormat(1.5, "0.##", "1.5");
    assertFormat(1.0, "0.##", "1.");
    assertFormat(0.5, "#.##", ".5");
}

func testFormatMinimumDigits() {
    assertFormat(5.0, "000", "005");
    assertFormat(5.0, "00000", "00005");
    assertFormat(1234.567, "000.0", "1234.6");
    assertFormat(0.0, "000", "000");
}

func testFormatGrouping() {
    assertFormat(1234.567, "#,##0", "1,235");
    assertFormat(1234.567, "#,##0.00", "1,234.57");
    assertFormat(1234567.0, "#,##0", "1,234,567");
    assertFormat(5.0, "#,##0", "5");
    assertFormat(0.0, "#,##0", "0");
}

func testFormatScaling() {
    # A comma after the digits divides by a thousand for each one.
    assertFormat(1234567.0, "0,", "1235");
    assertFormat(1234567.0, "#,##0,", "1,235");
    assertFormat(1234567.0, "0.0,,", "1.2");
    # And a per-cent sign multiplies by a hundred.
    assertFormat(0.075, "0%", "8%");
    assertFormat(0.075, "0.0%", "7.5%");
    assertFormat(0.075, "0.00%", "7.50%");
}

func testFormatScientific() {
    assertFormat(1234.567, "0.00E+00", "1.23E+03");
    assertFormat(1234.567, "0.0E+0", "1.2E+3");
    assertFormat(0.000123, "0.00E+00", "1.23E-04");
    assertFormat(0.0, "0.00E+00", "0.00E+00");
}

func testFormatLiterals() {
    assertFormat(1234.567, "$#,##0.00", "$1,234.57");
    assertFormat(42.0, "\"n=\"0", "n=42");
    assertFormat(42.0, "0\" items\"", "42 items");
    # A backslash escapes one character, which is how a file written by
    # LibreOffice spells a literal space.
    assertFormat(42.0, "0\\ \"kg\"", "42 kg");
}

func testFormatSections() {
    # One section is every number; two split on sign, with the negative one
    # spelling out its own sign; three add zero.
    assertFormat(-12.5, "0.00", "-12.50");
    assertFormat(-12.5, "0.00;(0.00)", "(12.50)");
    assertFormat(12.5, "0.00;(0.00)", "12.50");
    assertFormat(-12.5, "#,##0;(#,##0)", "(13)");
    assertFormat(0.0, "0.00;-0.00;\"nil\"", "nil");
    assertFormat(1.0, "0.00;-0.00;\"nil\"", "1.00");
    # An empty section shows nothing at all.
    assertFormat(-12.5, "0.0;;\"zero\"", "");
}

func testFormatColourModifierIsNotText() {
    # `[Red]` says how to paint the cell, so it must not reach the text.
    assertFormat(-12.5, "0.00;[Red]-0.00", "-12.50");
    assertFormat(1234.0, "[Blue]#,##0", "1,234");
    # A locale modifier is dropped the same way.
    assertFormat(1234.0, "[$-409]#,##0", "1,234");
}

func testFormatConditions() {
    def code as string init "[>100]\"big\";[<0]\"neg\";\"mid\"";
    assertFormat(150.0, $code, "big");
    assertFormat(-5.0, $code, "neg");
    assertFormat(50.0, $code, "mid");
    # Conditions are tried in order and the first match wins.
    assertFormat(1000.0, "[>=1000]0.0,\"k\";0.0", "1.0k");
    assertFormat(999.0, "[>=1000]0.0,\"k\";0.0", "999.0");
}

func testFormatNegativeZeroIsNotShown() {
    # A negative that rounds away must not come out as `-0.00`, which is
    # what both applications avoid.
    assertFormat(-0.001, "0.00", "0.00");
    assertFormat(-0.4, "0", "0");
}

func testFormatFractions() {
    assertFormat(2.25, "# ?/?", "2 1/4");
    assertFormat(0.5, "# ?/?", "1/2");
    assertFormat(-12.5, "# ?/?", "-12 1/2");
    assertFormat(2.1, "# ?/??", "2 1/10");
    # A denominator written into the code is used as it stands, so the whole
    # value becomes eighths.
    assertFormat(2.25, "?/8", "18/8");
}

func testFormatGeneralIsPlain() {
    assertFormat(1234.567, "", "1234.567");
    assertFormat(1234.567, "General", "1234.567");
    assertFormat(1234.567, "general", "1234.567");
}

func testFormatTextPlaceholder() {
    # `@` is the value as text, for a number as well as for text.
    assertFormat(1234.567, "@", "1234.567");
    testing.assertEqual(applyFormat(text("hi"), "@"), "hi");
    testing.assertEqual(applyFormat(text("hi"), "\"[\"@\"]\""), "[hi]");
    # Text falls through a numeric code untouched: there is nothing to round.
    testing.assertEqual(applyFormat(text("hi"), "0.00"), "hi");
    # Unless the code has a fourth section, which is the text one.
    testing.assertEqual(applyFormat(text("hi"), "0.00;-0.00;\"nil\";\"<\"@\">\""), "<hi>");
}

func testFormatOtherKinds() {
    testing.assertEqual(applyFormat(empty(), "0.00"), "");
    testing.assertEqual(applyFormat(boolean(true), "0.00"), "TRUE");
    testing.assertEqual(applyFormat(errorValue("#DIV/0!"), "0.00"), "#DIV/0!");
}

func testFormatRefusesACodeTooLongToBeReal() {
    # A format code comes from a file, so it is untrusted input, and two of
    # the scans over it are quadratic in its length: 10 000 unclosed brackets
    # measured 49 s and 100 000 commas did not finish. Past the cap the value
    # renders plainly, as every other unreadable code does.
    def wide as string init strings.repeat("0", MAX_FORMAT_CODE + 1);
    testing.assertEqual(applyFormat(number(1234.567), $wide), "1234.567");
    testing.assertEqual(MAX_FORMAT_CODE, 255);
    # And just inside the cap still works.
    def ok as string init strings.repeat("0", MAX_FORMAT_CODE);
    testing.assertEqual(len(applyFormat(number(1.0), $ok)), MAX_FORMAT_CODE);
}

func testFormatSurvivesMalformedCodes() {
    # None of these is a real code. Each has to come back with something
    # rather than failing, because a format is a presentation detail and a
    # file full of odd codes should still be readable.
    for (def code in ['0.00"abc', "[Red0.00", '0.00\\', "_", "*", "/", "0.00E", "[>]0.00", "# ?/"]) {
        applyFormat(number(1234.567), $code);
    }
    testing.assertEqual(applyFormat(number(1234.567), "[>]0.00"), "1234.57");
}

func testFormatOfAValueTooWideForTheArithmetic() {
    # Rounding lifts the value by 10^places into an int, so a wide value with
    # a long format would overflow an int64 and raise `kind: "runtime"`,
    # which this deck's errors may never be. Every one of these renders.
    for (def code in ["0.00", "0.00E+00", "# ?/?", "#,##0.00", "0.0%"]) {
        applyFormat(number(1.0e300), $code);
        applyFormat(number(-1.0e300), $code);
        applyFormat(number(1.0e-300), $code);
    }
    testing.assertEqual(applyFormat(number(1.0e300), "0.00"), "1e+300");
    # Fifteen places of a number near the cap is the overflow boundary.
    applyFormat(number(999999999999.0), "0.000000000000000");
}

func testFormatHugeNumbersFallBackToPlain() {
    # Past the cap the digit arithmetic would overflow an int64, so the
    # value is rendered plainly rather than wrongly.
    testing.assertEqual(
        applyFormat(number(MAX_FORMATTED * 10.0), "#,##0"),
        asString(number(MAX_FORMATTED * 10.0)));
    testing.assertEqual(MAX_FORMATTED, 1000000000000000.0);
}

/**
 * Assert what an instant renders as through a date format code.
 *
 * @param iso {string} the instant, in ISO 8601
 * @param code {string} the format code
 * @param want {string} the expected rendering
 */
func assertDateFormat(iso as string, code as string, want as string) {
    testing.assertEqual(applyFormat(stamp(time.fromIso($iso)), $code), $want);
}

func testFormatDateParts() {
    assertDateFormat("2026-10-02T15:04:05Z", "yyyy-mm-dd", "2026-10-02");
    assertDateFormat("2026-10-02T15:04:05Z", "yy", "26");
    assertDateFormat("2026-10-02T15:04:05Z", "mm/dd/yyyy", "10/02/2026");
    assertDateFormat("2026-01-05T00:00:00Z", "d/m/yyyy", "5/1/2026");
    assertDateFormat("2026-01-05T00:00:00Z", "dd/mm/yyyy", "05/01/2026");
}

func testFormatDateNames() {
    assertDateFormat("2026-10-02T15:04:05Z", "mmm", "Oct");
    assertDateFormat("2026-10-02T15:04:05Z", "mmmm", "October");
    # Five letters is the initial, which is how a narrow column shows it.
    assertDateFormat("2026-10-02T15:04:05Z", "mmmmm", "O");
    assertDateFormat("2026-10-02T15:04:05Z", "ddd", "Fri");
    assertDateFormat("2026-10-02T15:04:05Z", "dddd", "Friday");
    assertDateFormat("2026-10-02T15:04:05Z", "d mmm yyyy", "2 Oct 2026");
    assertDateFormat("2026-10-02T15:04:05Z", "dddd d mmmm yyyy", "Friday 2 October 2026");
}

func testFormatTimeParts() {
    assertDateFormat("2026-10-02T15:04:05Z", "hh:mm:ss", "15:04:05");
    assertDateFormat("2026-10-02T15:04:05Z", "h:mm", "15:04");
    assertDateFormat("2026-10-02T15:04:05Z", "h:mm AM/PM", "3:04 PM");
    assertDateFormat("2026-10-02T09:04:05Z", "h:mm AM/PM", "9:04 AM");
    assertDateFormat("2026-10-02T09:04:05Z", "h:mm am/pm", "9:04 am");
    assertDateFormat("2026-10-02T09:04:05Z", "h:mm A/P", "9:04 A");
    assertDateFormat("2026-10-02T15:04:05Z", "h:mm A/P", "3:04 P");
    # Midnight on a 12-hour clock is 12, not 0.
    assertDateFormat("2026-10-02T00:30:00Z", "h:mm AM/PM", "12:30 AM");
    assertDateFormat("2026-10-02T12:30:00Z", "h:mm AM/PM", "12:30 PM");
}

func testFormatMinuteVersusMonth() {
    # The rule that makes `mm` ambiguous: it is minutes after an hour token
    # or before a seconds token, and the month otherwise. Without it
    # `hh:mm` would show October.
    assertDateFormat("2026-10-02T15:04:05Z", "mm", "10");
    assertDateFormat("2026-10-02T15:04:05Z", "hh:mm", "15:04");
    assertDateFormat("2026-10-02T15:04:05Z", "mm:ss", "04:05");
    assertDateFormat("2026-10-02T15:04:05Z", "mm/dd/yy hh:mm", "10/02/26 15:04");
    assertDateFormat("2026-10-02T15:04:05Z", "yyyy-mm-dd hh:mm:ss", "2026-10-02 15:04:05");
}

func testFormatElapsedTime() {
    # `[h]` is a span rather than an hour of the day, which is how a
    # timesheet shows more than 24 hours.
    testing.assertEqual(applyFormat(number(1.5), "[h]:mm"), "36:00");
    testing.assertEqual(applyFormat(number(1.5), "[mm]:ss"), "2160:00");
    testing.assertEqual(applyFormat(number(0.5), "[h]"), "12");
    testing.assertEqual(applyFormat(number(0.75), "hh:mm:ss"), "18:00:00");
}

func testFormatNegativeSerialIsNotADate() {
    # A negative serial is not a date. Both applications render one anyway
    # and disagree about which day it is, so the number is shown instead.
    testing.assertEqual(applyFormat(number(-12.5), "yyyy-mm-dd"), "-12.5");
}

func testDisplayAtUsesTheCellsOwnFormat() {
    def s as Sheet init sheetOf("S", [[number(0.075), number(1234.5), number(-20.0)]]);
    $s = setStyle($s, "A1", withFormat(style(), "0.0%"));
    $s = setStyle($s, "B1", withFormat(style(), "#,##0.00"));
    $s = setStyle($s, "C1", withFormat(style(), "$#,##0.00;($#,##0.00)"));
    testing.assertEqual(displayAt($s, "A1"), "7.5%");
    testing.assertEqual(displayAt($s, "B1"), "1,234.50");
    testing.assertEqual(displayAt($s, "C1"), "($20.00)");
    # The value itself is untouched: the format is a presentation detail.
    testing.assertEqual(asString(cell($s, "A1")), "0.075");
}

func testDisplayAtOnACellWithNoFormat() {
    def s as Sheet init sheetOf("S", [[number(0.075), empty()]]);
    testing.assertEqual(displayAt($s, "A1"), "0.075");
    testing.assertEqual(displayAt($s, "B1"), "");
    # Off the used range is blank, as everywhere else in the deck.
    testing.assertEqual(displayAt($s, "Z99"), "");
}

func testDisplayAtRef() {
    def s as Sheet init setStyle(sheetOf("S", [[number(0.5)]]), "A1", withFormat(style(), "0%"));
    testing.assertEqual(displayAtRef($s, Ref{row: 0, col: 0}), "50%");
}

func testDisplayRowAndRows() {
    def s as Sheet init sheetOf(
        "S",
        [[text("Share"), text("Cost")], [number(0.075), number(1234.5)]]);
    $s = setStyle($s, "A2", withFormat(style(), "0.0%"));
    $s = setStyle($s, "B2", withFormat(style(), "#,##0.00"));
    testing.assertEqual(displayRow($s, 0), ["Share", "Cost"]);
    testing.assertEqual(displayRow($s, 1), ["7.5%", "1,234.50"]);
    def all as list of list of string init displayRows($s);
    testing.assertEqual(len($all), 2);
    testing.assertEqual($all[1], ["7.5%", "1,234.50"]);
}

func testBuiltinFormat() {
    # XLSX leaves the first fifty codes implicit, so a file can say
    # `numFmtId="14"` and nothing else. Reading only the date ids, and
    # writing `yyyy-mm-dd` for all of them, made a time format into a date
    # and dropped every non-date built-in.
    testing.assertEqual(builtinFormat(0), "");
    testing.assertEqual(builtinFormat(1), "0");
    testing.assertEqual(builtinFormat(2), "0.00");
    testing.assertEqual(builtinFormat(4), "#,##0.00");
    testing.assertEqual(builtinFormat(9), "0%");
    testing.assertEqual(builtinFormat(10), "0.00%");
    testing.assertEqual(builtinFormat(14), "mm/dd/yyyy");
    testing.assertEqual(builtinFormat(18), "h:mm AM/PM");
    testing.assertEqual(builtinFormat(21), "h:mm:ss");
    testing.assertEqual(builtinFormat(46), "[h]:mm:ss");
    testing.assertEqual(builtinFormat(49), "@");
    # The ids with no fixed meaning read as the general format.
    testing.assertEqual(builtinFormat(5), "");
    testing.assertEqual(builtinFormat(23), "");
    testing.assertEqual(builtinFormat(999), "");
    testing.assertEqual(builtinFormat(-1), "");
}

func testBuiltinTimeFormatIsATimeNotADate() {
    # The point of the table: id 18 is a time, and it has to render as one.
    def shown as string init applyFormat(
        stamp(time.fromIso("2026-10-02T15:04:05Z")),
        builtinFormat(18));
    testing.assertEqual($shown, "3:04 PM");
}

/**
 * A German locale, built the way a caller would.
 *
 * The spellings were read off a German-locale LibreOffice rendering the same
 * codes, which is what `docs/guide/formats-applied.md` records.
 *
 * @return {Locale} the locale
 */
func germanLocale() {
    return withDayNames(
        withMonthNames(
            withSeparators(defaultLocale(), ",", "."),
            [
                "Januar",
                "Februar",
                "Marz",
                "April",
                "Mai",
                "Juni",
                "Juli",
                "August",
                "September",
                "Oktober",
                "November",
                "Dezember"
            ],
            ["Jan", "Feb", "Mar", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]),
        ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"],
        []);
}

func testLocaleSeparators() {
    # The whole of what most regions differ by, and the reason the rendering
    # takes a locale while the code does not. Every expected value here was
    # read off a German-locale LibreOffice showing the same code.
    def german as Locale init germanLocale();
    testing.assertEqual(applyFormatIn(number(1234.5), "0.00", $german), "1234,50");
    testing.assertEqual(applyFormatIn(number(1234.5), "#,##0.00", $german), "1.234,50");
    testing.assertEqual(applyFormatIn(number(1234.5), "$#,##0.00", $german), "$1.234,50");
    testing.assertEqual(applyFormatIn(number(1234.5), "0.0%", $german), "123450,0%");
    testing.assertEqual(applyFormatIn(number(1234567.0), "#,##0", $german), "1.234.567");
}

func testLocaleMonthAndDayNames() {
    def german as Locale init germanLocale();
    def moment as Value init stamp(time.fromIso("1903-05-18T00:00:00Z"));
    testing.assertEqual(applyFormatIn($moment, "d mmm yyyy", $german), "18 Mai 1903");
    testing.assertEqual(applyFormatIn($moment, "mmmm", $german), "Mai");
    testing.assertEqual(applyFormatIn($moment, "dddd", $german), "Montag");
    # Short weekday names were not supplied, so the full ones are cut.
    # Monday cuts to the same three letters in both languages, so a
    # Wednesday is what shows the cut is really from the German name.
    testing.assertEqual(applyFormatIn($moment, "ddd", $german), "Mon");
    def wednesday as Value init stamp(time.fromIso("1903-05-20T00:00:00Z"));
    testing.assertEqual(applyFormatIn($wednesday, "dddd", $german), "Mittwoch");
    testing.assertEqual(applyFormatIn($wednesday, "ddd", $german), "Mit");
    # A numeric month or day is not a name and does not change.
    testing.assertEqual(applyFormatIn($moment, "dd.mm.yyyy", $german), "18.05.1903");
}

func testLocaleLeavesTheDefaultAlone() {
    # `applyFormat` is `applyFormatIn` with `defaultLocale()`, so nothing
    # that used it before behaves differently.
    testing.assertEqual(applyFormat(number(1234.5), "#,##0.00"), "1,234.50");
    testing.assertEqual(applyFormatIn(number(1234.5), "#,##0.00", defaultLocale()), "1,234.50");
    testing.assertEqual(defaultLocale().decimal, ".");
    testing.assertEqual(defaultLocale().grouping, ",");
    # No names of its own: the `time` module's are English whatever the
    # process locale says, and they are what the oracle assumes.
    testing.assertEqual(len(defaultLocale().months), 0);
    testing.assertEqual(len(defaultLocale().days), 0);
}

func testLocaleWithOnlySeparators() {
    # The common case: a caller who wants German numbers and does not care
    # about month names should not have to supply thirty-eight strings.
    def swiss as Locale init withSeparators(defaultLocale(), ".", "'");
    testing.assertEqual(applyFormatIn(number(1234567.5), "#,##0.00", $swiss), "1'234'567.50");
    def moment as Value init stamp(time.fromIso("1903-05-18T00:00:00Z"));
    testing.assertEqual(applyFormatIn($moment, "mmmm", $swiss), "May");
}

func failOnTooFewMonthNames() {
    withMonthNames(defaultLocale(), ["Jan", "Feb"], []);
}

func failOnTooFewDayNames() {
    withDayNames(defaultLocale(), ["Sun"], []);
}

func testLocaleRefusesAPartialNameList() {
    # A short list would render some months and not others, which is worse
    # than refusing it.
    testing.assertThrows("failOnTooFewMonthNames", ERROR_KIND);
    testing.assertThrows("failOnTooFewDayNames", ERROR_KIND);
}

func testDisplayInALocale() {
    def s as Sheet init sheetOf("S", [[number(1234.5)], [number(0.075)]]);
    $s = setStyle($s, "A1", withFormat(style(), "#,##0.00"));
    $s = setStyle($s, "A2", withFormat(style(), "0.0%"));
    def german as Locale init germanLocale();
    testing.assertEqual(displayAtIn($s, "A1", $german), "1.234,50");
    testing.assertEqual(displayAtIn($s, "A2", $german), "7,5%");
    testing.assertEqual(displayRowsIn($s, $german), [["1.234,50"], ["7,5%"]]);
    # And the plain forms are unchanged.
    testing.assertEqual(displayAt($s, "A1"), "1,234.50");
    testing.assertEqual(displayRows($s), [["1,234.50"], ["7.5%"]]);
}
