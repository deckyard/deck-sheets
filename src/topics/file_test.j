# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

# sheets - tests for file.j.
# Spliced into sheets_test.j via include - not a standalone module.
#
# Format detection by extension and by signature, and the generic dispatch.

func testAFormulaCrossesFormatsWithItsMeaningIntact() {
    # Written as "of:=[.A1]+SUM([.B1:.B3])" in ODS and "A1+SUM(B1:B3)" in XLSX,
    # and the model sees the same thing from either.
    def s as Sheet init newSheet("S");
    $s = setCell($s, "A1", formula("A1+SUM(B1:B3)", "6"));
    $s = setCell($s, "A2", formula("IF(A1>0,\"yes\",\"no\")", "yes"));
    $s = setCell($s, "A3", formula("'Second Sheet'!B2*2", "8"));
    def wb as Workbook init addSheet(newWorkbook(), $s);

    def viaOds as Workbook init readOds(writeOds($wb));
    def viaXlsx as Workbook init readXlsx(writeXlsx($wb));
    assertFormulaSource(sheetByName($viaOds, "S"), "A1", "A1+SUM(B1:B3)");
    assertFormulaSource(sheetByName($viaXlsx, "S"), "A1", "A1+SUM(B1:B3)");
    assertFormulaSource(sheetByName($viaOds, "S"), "A2", "IF(A1>0,\"yes\",\"no\")");
    assertFormulaSource(sheetByName($viaXlsx, "S"), "A2", "IF(A1>0,\"yes\",\"no\")");
    assertFormulaSource(sheetByName($viaOds, "S"), "A3", "'Second Sheet'!B2*2");
    assertFormulaSource(sheetByName($viaXlsx, "S"), "A3", "'Second Sheet'!B2*2");
}

func testFormatOfReadsTheExtension() {
    testing.assertEqual(formatName(formatOf("a.ods")), "ods");
    testing.assertEqual(formatName(formatOf("a.xlsx")), "xlsx");
    testing.assertEqual(formatName(formatOf("a.xlsm")), "xlsx");
    testing.assertEqual(formatName(formatOf("a.gnumeric")), "gnumeric");
    testing.assertEqual(formatName(formatOf("a.gnm")), "gnumeric");
    testing.assertEqual(formatName(formatOf("a.csv")), "csv");
    testing.assertEqual(formatName(formatOf("a.tsv")), "tsv");
    testing.assertEqual(formatName(formatOf("/path/to/Book.ODS")), "ods");
}

func testFormatOfRefusesWhatItDoesNotKnow() {
    testing.assertThrows("failOnAnUnknownExtension", ERROR_KIND);
    testing.assertThrows("failOnNoExtension", ERROR_KIND);
}

func testFormatOfBytesIdentifiesEachContainer() {
    def wb as Workbook init fixtureWorkbook();
    testing.assertEqual(formatName(formatOfBytes(writeOds($wb))), "ods");
    testing.assertEqual(formatName(formatOfBytes(writeXlsx($wb))), "xlsx");
    testing.assertEqual(formatName(formatOfBytes(writeGnumeric($wb))), "gnumeric");
    testing.assertEqual(formatName(formatOfBytes(writeGnumericXml($wb))), "gnumeric");
}

func failOnBytesThatAreNoFormat() {
    formatOfBytes(convert.bytesFromString("just some text", "utf-8"));
}

func testFormatOfBytesRefusesWhatItCannotIdentify() {
    testing.assertThrows("failOnBytesThatAreNoFormat", ERROR_KIND);
    testing.assertThrows("failOnAZipThatIsNoSpreadsheet", ERROR_KIND);
}

func testReadFormatAndWriteFormatCoverEveryFormat() {
    def wb as Workbook init fixtureWorkbook();
    for (def kind in [Format.Ods, Format.Xlsx, Format.Gnumeric, Format.Csv, Format.Tsv]) {
        def raw as bytes init writeFormat($wb, $kind);
        def back as Workbook init readFormat($raw, $kind);
        testing.assertTrue(len($back.sheets) >= 1);
        testing.assertEqual(asString(cell($back.sheets[0], "A1")), "Name");
    }
}

func failOnOpeningAMissingFile() {
    open("no-such-directory/missing.xlsx");
}

func failOnDetectingAMissingFile() {
    openDetected("no-such-directory/missing.bin");
}

func testOpenAndOpenDetectedRefuseAMissingFile() {
    testing.assertThrows("failOnOpeningAMissingFile", ERROR_KIND);
    testing.assertThrows("failOnDetectingAMissingFile", ERROR_KIND);
}

func failOnSavingToAnUnknownExtension() {
    # formatOf refuses the name before anything is written.
    save(fixtureWorkbook(), "no-such-directory/out.xls");
}

func failOnSavingWithNoExtension() {
    save(fixtureWorkbook(), "no-such-directory/out");
}

func testSaveRefusesANameWithNoKnownFormat() {
    testing.assertThrows("failOnSavingToAnUnknownExtension", ERROR_KIND);
    testing.assertThrows("failOnSavingWithNoExtension", ERROR_KIND);
}
