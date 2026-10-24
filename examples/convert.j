#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * convert example - one workbook, every format.
 *
 * Builds a workbook, saves it in every format and reads each file back.
 * Works in a temporary directory that it removes afterwards:
 *   jennifer run examples/convert.j
 */

use io;
use fs;
use path;
use os;

import "../src/sheets.j" as sheet;

def dir as string init fs.makeTempDir(os.tempDir(), "sheets-convert");
defer fs.removeAll($dir);

# Build a small workbook by hand.
def s as sheet.Sheet init sheet.newSheet("Sales");
$s = sheet.setRow(
    $s,
    0,
    [sheet.text("Item"), sheet.text("Qty"), sheet.text("Price"), sheet.text("Total")]);
$s = sheet.setRow(
    $s,
    1,
    [
        sheet.text("Widget & Co"),
        sheet.integer(4),
        sheet.number(9.99),
        sheet.formula("B2*C2", "39.96")
    ]);
$s = sheet.setRow(
    $s,
    2,
    [sheet.text("Gadget"), sheet.integer(2), sheet.number(24.5), sheet.formula("B3*C3", "49")]);

def wb as sheet.Workbook init sheet.newWorkbook();
$wb = sheet.addSheet($wb, $s);

# Write it as every format the deck knows, then read each one back.
for (def ext in [".ods", ".xlsx", ".gnumeric", ".csv", ".tsv"]) {
    def target as string init path.join($dir, "sales" + $ext);
    sheet.save($wb, $target);

    def back as sheet.Workbook init sheet.open($target);
    def first as sheet.Sheet init $back.sheets[0];
    def size as int init len(fs.readBytes($target));

    io.printf(
        "%s|pad=10|align=left %d|pad=6 bytes   A2=%s   D2=%s\n",
        "sales" + $ext,
        $size,
        sheet.asString(sheet.cell($first, "A2")),
        sheet.asString(sheet.cell($first, "D2")));
}
