#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * styles example - a report that looks like one.
 *
 * A bold boxed header, a money format and a date format, written as ODS and
 * XLSX:
 *   jennifer run examples/styles.j
 */

use io;
use fs;
use path;
use os;
use time;

import "../src/sheets.j" as sheet;

def dir as string init fs.makeTempDir(os.tempDir(), "sheets-styles");
defer fs.removeAll($dir);

def s as sheet.Sheet init sheet.sheetOf(
    "Q3",
    [
        [sheet.text("Region"), sheet.text("Revenue"), sheet.text("Booked")],
        [
            sheet.text("North"),
            sheet.number(12045.5),
            sheet.date(time.fromIso("2026-07-14T00:00:00Z"))
        ],
        [
            sheet.text("South"),
            sheet.number(9980.25),
            sheet.date(time.fromIso("2026-08-02T00:00:00Z"))
        ],
        [
            sheet.text("East"),
            sheet.number(15102.0),
            sheet.date(time.fromIso("2026-09-30T00:00:00Z"))
        ]
    ]);

# The header: bold, centred, filled, boxed.
def header as sheet.Style init sheet.withBorder(
    sheet.withBackground(
        sheet.withAlign(sheet.withBold(sheet.style(), true), sheet.Align.Centre),
        "FFF2CC"),
    sheet.BorderStyle.Thin);
$s = sheet.setAreaStyle($s, "A1:C1", $header);

# The figures: a thousands separator and two decimals, right aligned.
$s = sheet.setAreaStyle(
    $s,
    "B2:B4",
    sheet.withAlign(sheet.withFormat(sheet.style(), "#,##0.00"), sheet.Align.Right));

# The dates: an unambiguous format rather than the locale's guess.
$s = sheet.setAreaStyle($s, "C2:C4", sheet.withFormat(sheet.style(), "yyyy-mm-dd"));

def wb as sheet.Workbook init sheet.addSheet(sheet.newWorkbook(), $s);

io.printf("%d distinct styles for %d styled cells\n", len($s.styles) - 1, len($s.cellStyles));

for (def ext in [".ods", ".xlsx"]) {
    def target as string init path.join($dir, "report" + $ext);
    sheet.save($wb, $target);

    # Read it back and show that the styles came with it.
    def back as sheet.Workbook init sheet.open($target);
    def b as sheet.Sheet init $back.sheets[0];
    def head as sheet.Style init sheet.styleAt($b, "A1");
    def money as sheet.Style init sheet.styleAt($b, "B2");
    io.printf(
        "%s|pad=6|align=left %d|pad=5 bytes  header bold=%t filled=%s  figures format=%s\n",
        "report" + $ext,
        len(fs.readBytes($target)),
        $head.bold,
        $head.background,
        $money.format);
}

io.printf("\nThe deck carries a number format; it does not apply one.\n");
io.printf(
    "B2 reads back as %s here and displays as 12,045.50 in a spreadsheet.\n",
    sheet.asString(sheet.cell($s, "B2")));
