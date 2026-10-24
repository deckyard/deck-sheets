#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * edit example - open a workbook, change it, write it back.
 *
 * Takes a sheet out, changes it, puts it back and saves:
 *   jennifer run examples/edit.j
 */

use io;
use fs;
use path;
use os;
use convert;

import "../src/sheets.j" as sheet;

def dir as string init fs.makeTempDir(os.tempDir(), "sheets-edit");
defer fs.removeAll($dir);
def target as string init path.join($dir, "book.ods");

# Start from something on disk.
def initial as sheet.Sheet init sheet.newSheet("Q3");
$initial = sheet.setRow($initial, 0, [sheet.text("Region"), sheet.text("Revenue")]);
$initial = sheet.setRow($initial, 1, [sheet.text("North"), sheet.number(1200.0)]);
$initial = sheet.setRow($initial, 2, [sheet.text("South"), sheet.number(980.5)]);
sheet.save(sheet.addSheet(sheet.newWorkbook(), $initial), $target);

# Open it, edit it, write it back.
def wb as sheet.Workbook init sheet.open($target);
def s as sheet.Sheet init sheet.sheetByName($wb, "Q3");

# Every mutator returns a fresh value, so the shape is always $x = f($x, ...).
$s = sheet.addRow($s, [sheet.text("East"), sheet.number(1510.25)]);
def lastRow as int init $s.rowCount;
$s = sheet.setCell($s, "A" + convert.toString($lastRow + 1), sheet.text("Total"));
$s = sheet.setCell(
    $s,
    "B" + convert.toString($lastRow + 1),
    sheet.formula("SUM(B2:B" + convert.toString($lastRow) + ")", ""));

$wb = sheet.putSheet($wb, $s);
$wb = sheet.renameSheet($wb, "Q3", "Q3 2026");
sheet.save($wb, $target);

# Read it back and print what is there.
def check as sheet.Workbook init sheet.open($target);
def out as sheet.Sheet init sheet.sheetByName($check, "Q3 2026");
io.printf("sheets: %v\n", sheet.sheetNames($check));
for (def line in sheet.rows($out)) {
    io.printf("  %s|pad=8|align=left %s\n", sheet.asString($line[0]), sheet.asString($line[1]));
}
def totalCell as sheet.Value init sheet.cell($out, "B" + convert.toString($lastRow + 1));
match ($totalCell) {
    when Formula(f) {
        # The cached result is empty because nothing has evaluated it: this
        # deck stores formulas, it does not compute them.
        io.printf("B%d is =%s, not yet computed\n", $lastRow + 1, $f.source);
    }
    else { io.printf("B%d is a %s\n", $lastRow + 1, sheet.kindOf($totalCell)); }
}
