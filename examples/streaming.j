#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * streaming example - reading a sheet too large to hold.
 *
 * Builds a sheet of 2,000 rows, writes it, then reads it back a row at a time
 * and sums a column without ever holding the whole sheet:
 *   jennifer run examples/streaming.j
 */

use io;
use fs;
use path;
use os;
use convert;

import "../src/sheets.j" as sheet;

def dir as string init fs.makeTempDir(os.tempDir(), "sheets-streaming");
defer fs.removeAll($dir);

# A sheet with a header and 2,000 data rows. Collected first and built in one
# pass with sheetOf: calling setRow per row would copy the sheet's cell map
# every time, which is quadratic (see the docs on sheetOf).
def lines as list of list of sheet.Value init [];
$lines[] = [sheet.text("sensor"), sheet.text("celsius")];
for (def i in 0..2000) {
    def name as string init "sensor" + convert.toString($i % 7);
    def reading as float init convert.toFloat($i) / 10.0;
    $lines[] = [sheet.text($name), sheet.number($reading)];
}
def s as sheet.Sheet init sheet.sheetOf("Readings", $lines);
def target as string init path.join($dir, "readings.xlsx");
sheet.save(sheet.addSheet(sheet.newWorkbook(), $s), $target);
io.printf("wrote %s (%d bytes)\n", path.base($target), len(fs.readBytes($target)));

# Read it back a row at a time. Only the current row is ever live.
def total as float init 0.0;
def counted as int init 0;
def r as sheet.RowReader init sheet.openRows($target, "Readings");
while (sheet.hasRow($r)) {
    $r = sheet.nextRow($r);
    if (sheet.rowNumber($r) == 1) {
        continue;
    }
    def values as list of sheet.Value init sheet.rowValues($r);
    $total = $total + sheet.asNumber($values[1]);
    $counted = $counted + 1;
}
io.printf("streamed %d rows, mean %f|prec=2 C\n", $counted, $total / convert.toFloat($counted));
