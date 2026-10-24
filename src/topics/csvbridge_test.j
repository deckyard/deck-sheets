# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for csvbridge.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# Typing on the way in, and formula-injection safety on the way out.

func testCsvKeepsWhatTextCanHold() {
    def text as string init writeCsv(fixtureWorkbook(), "Sheet1");
    def wb as Workbook init readCsv($text, true);
    def s as Sheet init sheetByName($wb, CSV_SHEET_NAME);
    testing.assertEqual(asString(cell($s, "A1")), "Name");
    testing.assertEqual(asString(cell($s, "A2")), "Widget & Co");
    testing.assertEqual(asNumber(cell($s, "B2")), 4.0);
    testing.assertEqual(asNumber(cell($s, "C2")), 9.99);
    # A formula arrives as its cached result, which is all text can carry.
    testing.assertEqual(asNumber(cell($s, "C3")), 19.98);
    testing.assertEqual(kindOf(cell($s, "C3")), "number");
}

func testCsvQuotesWhatNeedsIt() {
    def s as Sheet init newSheet("S");
    $s = setRow($s, 0, [text("has,comma"), text("has\"quote"), text("plain")]);
    def out as string init writeCsv(addSheet(newWorkbook(), $s), "");
    def back as Workbook init readCsv($out, true);
    def b as Sheet init sheetByName($back, CSV_SHEET_NAME);
    testing.assertEqual(asString(cell($b, "A1")), "has,comma");
    testing.assertEqual(asString(cell($b, "B1")), "has\"quote");
    testing.assertEqual(asString(cell($b, "C1")), "plain");
}

func testTsvUsesTabs() {
    def s as Sheet init newSheet("S");
    $s = setRow($s, 0, [text("a"), text("b")]);
    def out as string init writeDelimited(addSheet(newWorkbook(), $s), "", "\t");
    testing.assertTrue(strings.contains($out, "a\tb"));
    def back as Workbook init readDelimited($out, "\t", true);
    testing.assertEqual(asString(cell(sheetByName($back, CSV_SHEET_NAME), "B1")), "b");
}

func testCsvTypingCanBeTurnedOff() {
    # The identifier case: 007 must not become 7.
    def typed as Workbook init readCsv("007,TRUE,2026-10-02\n", true);
    def raw as Workbook init readCsv("007,TRUE,2026-10-02\n", false);
    def t as Sheet init sheetByName($typed, CSV_SHEET_NAME);
    def r as Sheet init sheetByName($raw, CSV_SHEET_NAME);
    # A leading zero is protected even with typing on.
    testing.assertEqual(kindOf(cell($t, "A1")), "text");
    testing.assertEqual(asString(cell($t, "A1")), "007");
    testing.assertEqual(kindOf(cell($t, "B1")), "bool");
    testing.assertEqual(kindOf(cell($t, "C1")), "stamp");
    # With typing off, everything is text.
    testing.assertEqual(kindOf(cell($r, "B1")), "text");
    testing.assertEqual(kindOf(cell($r, "C1")), "text");
}

func testCsvTypesNumbersAndLeavesWordsAlone() {
    def wb as Workbook init readCsv("1,2.5,-3,1e3,0,hello,#N/A\n", true);
    def s as Sheet init sheetByName($wb, CSV_SHEET_NAME);
    testing.assertEqual(asNumber(cell($s, "A1")), 1.0);
    testing.assertEqual(asNumber(cell($s, "B1")), 2.5);
    testing.assertEqual(asNumber(cell($s, "C1")), -3.0);
    testing.assertEqual(asNumber(cell($s, "D1")), 1000.0);
    testing.assertEqual(asNumber(cell($s, "E1")), 0.0);
    testing.assertEqual(kindOf(cell($s, "E1")), "number");
    testing.assertEqual(kindOf(cell($s, "F1")), "text");
    testing.assertEqual(kindOf(cell($s, "G1")), "error");
}

func testAnEmptyCsvFieldIsAnEmptyCell() {
    def wb as Workbook init readCsv("a,,c\n", true);
    def s as Sheet init sheetByName($wb, CSV_SHEET_NAME);
    testing.assertTrue(isEmpty(cell($s, "B1")));
    testing.assertEqual(asString(cell($s, "C1")), "c");
}

func testWriteCsvSafeNeutralisesAFormulaInjection() {
    # CWE-1236: a field a spreadsheet would execute on open.
    def s as Sheet init newSheet("S");
    $s = setRow($s, 0, [text("=1+1"), text("+A1"), text("plain")]);
    def wb as Workbook init addSheet(newWorkbook(), $s);
    def safe as string init writeCsvSafe($wb, "");
    testing.assertFalse(strings.startsWith($safe, "=1+1"));
    testing.assertTrue(strings.contains($safe, "plain"));
}

func failOnABadDelimiter() {
    writeDelimited(fixtureWorkbook(), "", ";;");
}

func failOnReadingWithABadDelimiter() {
    readDelimited("a;b", "", true);
}

func testTheDelimitedBridgeRefusesABadSeparator() {
    testing.assertThrows("failOnABadDelimiter", ERROR_KIND);
    testing.assertThrows("failOnReadingWithABadDelimiter", ERROR_KIND);
}

func failOnWritingCsvForAMissingSheet() {
    writeCsv(fixtureWorkbook(), "Nope");
}

func testWriteCsvRefusesAMissingSheet() {
    testing.assertThrows("failOnWritingCsvForAMissingSheet", ERROR_KIND);
}
