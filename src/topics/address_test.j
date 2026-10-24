# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for address.j.
# Spliced into sheets_test.j via include - not a standalone module.

func testRefBuildsAReference() {
    def at as Ref init ref(6, 1);
    testing.assertEqual($at.row, 6);
    testing.assertEqual($at.col, 1);
}

func failOnNegativeRow() {
    ref(-1, 0);
}

func failOnNegativeColumn() {
    ref(0, -1);
}

func failOnHugeRow() {
    ref(MAX_ROW + 1, 0);
}

func failOnHugeColumn() {
    ref(0, MAX_COLUMN + 1);
}

func testRefRefusesWhatIsOffTheGrid() {
    testing.assertThrows("failOnNegativeRow", ERROR_KIND);
    testing.assertThrows("failOnNegativeColumn", ERROR_KIND);
    testing.assertThrows("failOnHugeRow", ERROR_KIND);
    testing.assertThrows("failOnHugeColumn", ERROR_KIND);
}

func testColumnNameCountsInBijectiveBase26() {
    # The interesting cases are the carries: there is no zero digit, so Z is
    # followed by AA rather than BA.
    testing.assertEqual(columnName(0), "A");
    testing.assertEqual(columnName(25), "Z");
    testing.assertEqual(columnName(26), "AA");
    testing.assertEqual(columnName(27), "AB");
    testing.assertEqual(columnName(51), "AZ");
    testing.assertEqual(columnName(52), "BA");
    testing.assertEqual(columnName(701), "ZZ");
    testing.assertEqual(columnName(702), "AAA");
}

func testColumnNameReachesTheLastColumn() {
    testing.assertEqual(columnName(MAX_COLUMN), "XFD");
}

func testColumnIndexIsTheInverse() {
    testing.assertEqual(columnIndex("A"), 0);
    testing.assertEqual(columnIndex("Z"), 25);
    testing.assertEqual(columnIndex("AA"), 26);
    testing.assertEqual(columnIndex("ZZ"), 701);
    testing.assertEqual(columnIndex("AAA"), 702);
    testing.assertEqual(columnIndex("XFD"), MAX_COLUMN);
}

func testColumnIndexIsCaseInsensitive() {
    testing.assertEqual(columnIndex("aa"), 26);
    testing.assertEqual(columnIndex("aA"), 26);
}

func testColumnNameAndIndexRoundTrip() {
    for (def i in 0..200) {
        testing.assertEqual(columnIndex(columnName($i)), $i);
    }
    testing.assertEqual(columnIndex(columnName(5000)), 5000);
}

func failOnEmptyColumnName() {
    columnIndex("");
}

func failOnNonLetterColumnName() {
    columnIndex("A1");
}

func failOnColumnNamePastTheGrid() {
    columnIndex("XFE");
}

func testColumnIndexRefusesWhatIsNotAColumn() {
    testing.assertThrows("failOnEmptyColumnName", ERROR_KIND);
    testing.assertThrows("failOnNonLetterColumnName", ERROR_KIND);
    testing.assertThrows("failOnColumnNamePastTheGrid", ERROR_KIND);
}

func testCellRefWritesA1() {
    testing.assertEqual(cellRef(ref(0, 0)), "A1");
    testing.assertEqual(cellRef(ref(6, 1)), "B7");
    testing.assertEqual(cellRef(ref(99, 26)), "AA100");
}

func testParseRefReadsA1() {
    def at as Ref init parseRef("B7");
    testing.assertEqual($at.row, 6);
    testing.assertEqual($at.col, 1);
}

func testParseRefDiscardsDollars() {
    testing.assertEqual(cellRef(parseRef("$B$7")), "B7");
    testing.assertEqual(cellRef(parseRef("B$7")), "B7");
    testing.assertEqual(cellRef(parseRef("$B7")), "B7");
}

func testParseRefIsCaseInsensitive() {
    testing.assertEqual(cellRef(parseRef("b7")), "B7");
}

func testCellRefAndParseRefRoundTrip() {
    for (def spelling in ["A1", "B7", "Z1", "AA100", "XFD1048576"]) {
        testing.assertEqual(cellRef(parseRef($spelling)), $spelling);
    }
}

func failOnEmptyRef() {
    parseRef("");
}

func failOnRefWithNoRow() {
    parseRef("B");
}

func failOnRefWithNoColumn() {
    parseRef("7");
}

func failOnRefWithRowZero() {
    parseRef("B0");
}

func failOnMalformedRef() {
    parseRef("B7B");
}

func failOnRefWithPunctuation() {
    parseRef("B-7");
}

func testParseRefRefusesWhatIsNotAReference() {
    testing.assertThrows("failOnEmptyRef", ERROR_KIND);
    testing.assertThrows("failOnRefWithNoRow", ERROR_KIND);
    testing.assertThrows("failOnRefWithNoColumn", ERROR_KIND);
    testing.assertThrows("failOnRefWithRowZero", ERROR_KIND);
    testing.assertThrows("failOnMalformedRef", ERROR_KIND);
    testing.assertThrows("failOnRefWithPunctuation", ERROR_KIND);
}

func testAreaNormalisesItsCorners() {
    def box as Area init area(ref(6, 2), ref(0, 0));
    testing.assertEqual(areaRef($box), "A1:C7");
}

func testAreaRefWritesASingleCellBare() {
    testing.assertEqual(areaRef(area(ref(1, 1), ref(1, 1))), "B2");
}

func testParseAreaReadsBothForms() {
    testing.assertEqual(areaRef(parseArea("A1:C7")), "A1:C7");
    testing.assertEqual(areaRef(parseArea("B2")), "B2");
    testing.assertEqual(areaRef(parseArea("$A$1:$C$7")), "A1:C7");
}

func testParseAreaNormalisesAReversedRange() {
    testing.assertEqual(areaRef(parseArea("C7:A1")), "A1:C7");
}

func testAreaSizeCountsCells() {
    testing.assertEqual(areaSize(parseArea("A1:C7")), 21);
    testing.assertEqual(areaSize(parseArea("B2")), 1);
}

func testAreaContainsItsEdges() {
    def box as Area init parseArea("B2:D5");
    testing.assertTrue(areaContains($box, parseRef("B2")));
    testing.assertTrue(areaContains($box, parseRef("D5")));
    testing.assertTrue(areaContains($box, parseRef("C3")));
    testing.assertFalse(areaContains($box, parseRef("A1")));
    testing.assertFalse(areaContains($box, parseRef("E5")));
    testing.assertFalse(areaContains($box, parseRef("D6")));
}

func testSplitSheetRefReadsAPlainName() {
    def parts as list of string init splitSheetRef("Sheet1!A1");
    testing.assertEqual($parts[0], "Sheet1");
    testing.assertEqual($parts[1], "A1");
}

func testSplitSheetRefReadsAQuotedName() {
    def parts as list of string init splitSheetRef("'Second Sheet'!A1");
    testing.assertEqual($parts[0], "Second Sheet");
    testing.assertEqual($parts[1], "A1");
}

func testSplitSheetRefUndoublesAnInteriorQuote() {
    def parts as list of string init splitSheetRef("'Bob''s Sheet'!B2");
    testing.assertEqual($parts[0], "Bob's Sheet");
    testing.assertEqual($parts[1], "B2");
}

func testSplitSheetRefLeavesAnUnqualifiedReference() {
    def parts as list of string init splitSheetRef("A1");
    testing.assertEqual($parts[0], "");
    testing.assertEqual($parts[1], "A1");
}

func failOnUnclosedSheetQuote() {
    splitSheetRef("'Second Sheet!A1");
}

func testSplitSheetRefRefusesAnUnclosedQuote() {
    testing.assertThrows("failOnUnclosedSheetQuote", ERROR_KIND);
}

func testSheetRefQuotesOnlyWhenItHasTo() {
    testing.assertEqual(sheetRef("Sheet1", "A1"), "Sheet1!A1");
    testing.assertEqual(sheetRef("with_underscore", "A1"), "with_underscore!A1");
    testing.assertEqual(sheetRef("Second Sheet", "A1"), "'Second Sheet'!A1");
    testing.assertEqual(sheetRef("Bob's", "A1"), "'Bob''s'!A1");
    testing.assertEqual(sheetRef("", "A1"), "A1");
}

func testSheetRefQuotesALeadingDigit() {
    # "2024!A1" would read as a reference to a cell, not a sheet.
    testing.assertEqual(sheetRef("2024", "A1"), "'2024'!A1");
}

func testSheetRefAndSplitRoundTrip() {
    for (def name in ["Sheet1", "Second Sheet", "Bob's Sheet", "2024", "a-b"]) {
        def parts as list of string init splitSheetRef(sheetRef($name, "A1"));
        testing.assertEqual($parts[0], $name);
        testing.assertEqual($parts[1], "A1");
    }
}

func failOnAnOverlongColumnName() {
    columnIndex(strings.repeat("Z", 20));
}

func failOnARefWithAnOverlongColumn() {
    parseRef(strings.repeat("A", 20) + "1");
}

func failOnARefWithAnOverlongRow() {
    parseRef("A" + strings.repeat("9", 40));
}

func testAnOverlongReferenceStaysInTheDecksErrorContract() {
    # These used to overflow int64 during the base-26 accumulation, which
    # Jennifer raises as kind "runtime" - escaping this deck's contract, so a
    # caller matching on kind == "sheets" would mis-handle a merely malformed
    # reference. Bounded before the arithmetic now.
    testing.assertThrows("failOnAnOverlongColumnName", ERROR_KIND);
    testing.assertThrows("failOnARefWithAnOverlongColumn", ERROR_KIND);
    testing.assertThrows("failOnARefWithAnOverlongRow", ERROR_KIND);
}

func testTheLongestLegalReferenceStillParses() {
    testing.assertEqual(cellRef(parseRef("XFD1048576")), "XFD1048576");
    testing.assertEqual(columnIndex("XFD"), MAX_COLUMN);
}
