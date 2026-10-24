# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for value.j.
# Spliced into sheets_test.j via include - not a standalone module.

func testAsStringOfAHugeNumber() {
    # `math.floor` returns an int and throws when the result will not fit in
    # one, so checking it before the magnitude made this raise
    # `kind: "runtime"` - and a file is free to hold 1e300.
    testing.assertEqual(asString(number(1.0e300)), "1e+300");
    testing.assertEqual(asString(number(-1.0e300)), "-1e+300");
    testing.assertEqual(asString(number(1.0e-300)), "1e-300");
    # The whole-number shortcut still applies below the bound.
    testing.assertEqual(asString(number(42.0)), "42");
    testing.assertEqual(asString(number(42.5)), "42.5");
}

func testKindOfNamesEveryVariant() {
    testing.assertEqual(kindOf(empty()), "empty");
    testing.assertEqual(kindOf(text("a")), "text");
    testing.assertEqual(kindOf(number(1.0)), "number");
    testing.assertEqual(kindOf(integer(1)), "number");
    testing.assertEqual(kindOf(boolean(true)), "bool");
    testing.assertEqual(kindOf(date(time.fromIso("2026-10-02T00:00:00Z"))), "stamp");
    testing.assertEqual(kindOf(stamp(time.fromIso("2026-10-02T12:00:00Z"))), "stamp");
    testing.assertEqual(kindOf(formula("A1", "1")), "formula");
    testing.assertEqual(kindOf(errorValue("#DIV/0!")), "error");
}

func testTheZeroValueIsEmpty() {
    def v as Value;
    testing.assertTrue(isEmpty($v));
    testing.assertEqual(kindOf($v), "empty");
}

func testIsEmptyOnlyForEmpty() {
    testing.assertTrue(isEmpty(empty()));
    testing.assertFalse(isEmpty(text("")));
    testing.assertFalse(isEmpty(number(0.0)));
}

func testAsStringRendersEachVariant() {
    testing.assertEqual(asString(empty()), "");
    testing.assertEqual(asString(text("total")), "total");
    testing.assertEqual(asString(number(9.99)), "9.99");
    testing.assertEqual(asString(boolean(true)), "TRUE");
    testing.assertEqual(asString(boolean(false)), "FALSE");
    testing.assertEqual(asString(errorValue("#DIV/0!")), "#DIV/0!");
}

func testAsStringDropsATrailingPointZero() {
    # Both formats write 4, not 4.0; a round trip should not grow a point.
    testing.assertEqual(asString(number(4.0)), "4");
    testing.assertEqual(asString(integer(4)), "4");
    testing.assertEqual(asString(number(-7.0)), "-7");
    testing.assertEqual(asString(number(0.0)), "0");
}

func testAsStringGivesAFormulaItsCachedResult() {
    testing.assertEqual(asString(formula("B3*C2", "19.98")), "19.98");
    testing.assertEqual(asString(formula("B3*C2", "")), "");
}

func testAsStringRendersADateAsIso() {
    def day as time.Time init time.fromIso("2026-10-02T00:00:00Z");
    testing.assertEqual(asString(date($day)), "2026-10-02");
    testing.assertEqual(
        asString(stamp(time.fromIso("2026-10-02T14:30:00Z"))),
        "2026-10-02T14:30:00");
}

func testAsNumberReadsEachVariant() {
    testing.assertEqual(asNumber(empty()), 0.0);
    testing.assertEqual(asNumber(number(9.99)), 9.99);
    testing.assertEqual(asNumber(boolean(true)), 1.0);
    testing.assertEqual(asNumber(boolean(false)), 0.0);
}

func testAsNumberReadsNumericText() {
    # A CSV import and a text-typed export both produce numbers stored as text.
    testing.assertEqual(asNumber(text("42")), 42.0);
    testing.assertEqual(asNumber(text(" 9.99 ")), 9.99);
    testing.assertEqual(asNumber(text("")), 0.0);
    testing.assertEqual(asNumber(formula("A1", "42")), 42.0);
}

func failOnWordAsNumber() {
    asNumber(text("north"));
}

func failOnErrorAsNumber() {
    asNumber(errorValue("#DIV/0!"));
}

func testAsNumberRefusesWhatIsNotANumber() {
    testing.assertThrows("failOnWordAsNumber", ERROR_KIND);
    testing.assertThrows("failOnErrorAsNumber", ERROR_KIND);
}

func testAsBoolReadsEachVariant() {
    testing.assertTrue(asBool(boolean(true)));
    testing.assertFalse(asBool(boolean(false)));
    testing.assertFalse(asBool(empty()));
    testing.assertTrue(asBool(number(1.0)));
    testing.assertTrue(asBool(number(-1.0)));
    testing.assertFalse(asBool(number(0.0)));
}

func testAsBoolReadsTheSpellingsFilesUse() {
    testing.assertTrue(asBool(text("TRUE")));
    testing.assertTrue(asBool(text("true")));
    testing.assertTrue(asBool(text("1")));
    testing.assertFalse(asBool(text("FALSE")));
    testing.assertFalse(asBool(text("false")));
    testing.assertFalse(asBool(text("0")));
    testing.assertFalse(asBool(text("")));
}

func failOnWordAsBool() {
    asBool(text("maybe"));
}

func failOnErrorAsBool() {
    asBool(errorValue("#VALUE!"));
}

func testAsBoolRefusesWhatIsNotABoolean() {
    testing.assertThrows("failOnWordAsBool", ERROR_KIND);
    testing.assertThrows("failOnErrorAsBool", ERROR_KIND);
}

func testAsTimeReadsEachVariant() {
    def day as time.Time init time.fromIso("2026-10-02T00:00:00Z");
    testing.assertEqual(time.iso(asTime(date($day))), time.iso($day));
    testing.assertEqual(time.iso(asTime(number(46297.0))), time.iso($day));
    testing.assertEqual(time.iso(asTime(text("2026-10-02"))), time.iso($day));
}

func failOnTextAsTime() {
    asTime(text("not a date"));
}

func failOnBoolAsTime() {
    asTime(boolean(true));
}

func testAsTimeRefusesWhatIsNotADate() {
    testing.assertThrows("failOnTextAsTime", ERROR_KIND);
    testing.assertThrows("failOnBoolAsTime", ERROR_KIND);
}

func testToSerialMatchesTheKnownValue() {
    # 46297 is 2026-10-02 in the 1900 system; checked against a real file.
    def day as time.Time init time.fromIso("2026-10-02T00:00:00Z");
    testing.assertEqual(toSerial($day, false), 46297.0);
}

func testSerialOneIsTheFirstOfJanuary1900() {
    testing.assertEqual(time.format(fromSerial(1.0, false), "%Y-%m-%d"), "1900-01-01");
}

func testSerialSurvivesTheFake1900LeapDay() {
    # The format treats 1900 as a leap year, so serial 60 is 1900-02-29, a day
    # that never existed. Either side of it must still land on the right day.
    testing.assertEqual(time.format(fromSerial(59.0, false), "%Y-%m-%d"), "1900-02-28");
    testing.assertEqual(time.format(fromSerial(61.0, false), "%Y-%m-%d"), "1900-03-01");
}

func testThePhantomLeapDayReadsAsTheDayBefore() {
    # Serial 60 describes no real date; reading it as 1900-02-28 beats
    # refusing a file over a value no one meant to write.
    testing.assertEqual(time.format(fromSerial(60.0, false), "%Y-%m-%d"), "1900-02-28");
}

func testSerialsEitherSideOfThePhantomDayAreContiguousDates() {
    # The gap in the serials is the point: 59 and 61 are consecutive days.
    def before as time.Time init fromSerial(59.0, false);
    def after as time.Time init fromSerial(61.0, false);
    testing.assertEqual(time.seconds(time.sub($after, $before)), 86400);
}

func testFromSerialCarriesTheTimeOfDay() {
    testing.assertEqual(
        time.format(fromSerial(46297.5, false), "%Y-%m-%d %H:%M:%S"),
        "2026-10-02 12:00:00");
}

func testSerialRoundTrips() {
    # Serial 60 is excluded: it names no date, so it cannot round-trip.
    for (def s in [1.0, 2.0, 59.0, 61.0, 25569.0, 46297.0]) {
        testing.assertEqual(toSerial(fromSerial($s, false), false), $s);
    }
}

func testSerialRoundTripsIn1904Too() {
    for (def s in [0.0, 1.0, 60.0, 44835.0]) {
        testing.assertEqual(toSerial(fromSerial($s, true), true), $s);
    }
}

func testTheUnixEpochHasItsKnownSerial() {
    # 25569 is 1970-01-01 in the 1900 system, the constant every
    # spreadsheet-to-epoch conversion is built on.
    testing.assertEqual(time.format(fromSerial(25569.0, false), "%Y-%m-%d"), "1970-01-01");
}

func testThe1904SystemIsOffsetByFourYears() {
    # The same day is 1462 lower in the 1904 system.
    def day as time.Time init time.fromIso("2026-10-02T00:00:00Z");
    testing.assertEqual(toSerial($day, false) - toSerial($day, true), 1462.0);
    testing.assertEqual(time.format(fromSerial(0.0, true), "%Y-%m-%d"), "1904-01-01");
}

func failOnNegativeSerial() {
    fromSerial(-1.0, false);
}

func failOnDateBeforeTheEpoch() {
    toSerial(time.fromIso("1800-01-01T00:00:00Z"), false);
}

func testTheSerialCodecRefusesWhatItCannotRepresent() {
    testing.assertThrows("failOnNegativeSerial", ERROR_KIND);
    testing.assertThrows("failOnDateBeforeTheEpoch", ERROR_KIND);
}

func testParseIsoDateReadsBothForms() {
    testing.assertEqual(time.format(parseIsoDate("2026-10-02"), "%Y-%m-%d"), "2026-10-02");
    testing.assertEqual(
        time.format(parseIsoDate("2026-10-02T14:30:00"), "%Y-%m-%d %H:%M:%S"),
        "2026-10-02 14:30:00");
    testing.assertEqual(
        time.format(parseIsoDate("2026-10-02T14:30:00Z"), "%Y-%m-%d %H:%M:%S"),
        "2026-10-02 14:30:00");
}

func failOnEmptyIsoDate() {
    parseIsoDate("   ");
}

func failOnGarbageIsoDate() {
    parseIsoDate("the second of October");
}

func testParseIsoDateRefusesWhatIsNotADate() {
    testing.assertThrows("failOnEmptyIsoDate", ERROR_KIND);
    testing.assertThrows("failOnGarbageIsoDate", ERROR_KIND);
}
