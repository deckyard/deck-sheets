#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * Write the fixtures tools/validate-output.sh hands to a real spreadsheet.
 *
 * The deck's own readers cannot tell us whether a written file is one a
 * spreadsheet application will accept - they share every assumption the
 * writers made. So the output goes out to LibreOffice, and this program is
 * what produces it.
 *
 * Writes into the directory given as the first argument:
 *   fixture.ods, fixture.xlsx, fixture.gnumeric  the files to open
 *   markers.txt                                  strings that must survive
 *
 * Usage: jennifer run tools/write-fixtures.j <directory>
 */

use io;
use os;
use fs;
use path;
use time;

import "../src/sheets.j" as sheet;

if (len(os.ARGS) < 2) {
    io.printf("usage: jennifer run tools/write-fixtures.j <directory>\n");
    exit 2;
}
def dir as string init os.ARGS[1];
if (not fs.isDir($dir)) {
    fs.mkdirAll($dir);
}

# Deliberately awkward content: an ampersand that must be escaped, a float and
# a whole number, a formula, a date, a boolean, a gap, and a second sheet whose
# name needs quoting in a reference.
def s as sheet.Sheet init sheet.newSheet("Sheet1");
$s = sheet.setRow($s, 0, [sheet.text("Name"), sheet.text("Qty"), sheet.text("Price")]);
$s = sheet.setRow($s, 1, [sheet.text("Widget & Co"), sheet.integer(4), sheet.number(9.99)]);
$s = sheet.setCell($s, "A3", sheet.text("Gadget"));
$s = sheet.setCell($s, "B3", sheet.integer(2));
$s = sheet.setCell($s, "C3", sheet.formula("B3*C2", "19.98"));
$s = sheet.setCell($s, "C4", sheet.date(time.fromIso("2026-10-02T00:00:00Z")));
$s = sheet.setCell($s, "A5", sheet.boolean(true));

# Styles, so the applications are asked about those too. The header is bold,
# centred, filled and boxed; the price column carries a number format; the date
# column carries a date format.
def head as sheet.Style init sheet.withBorder(
    sheet.withBackground(
        sheet.withAlign(sheet.withBold(sheet.style(), true), sheet.Align.Centre),
        "FFF2CC"),
    sheet.BorderStyle.Thin);
$s = sheet.setAreaStyle($s, "A1:C1", $head);
$s = sheet.setAreaStyle($s, "C2:C3", sheet.withFormat(sheet.style(), "#,##0.00"));
$s = sheet.setStyle($s, "C4", sheet.withFormat(sheet.style(), "yyyy-mm-dd"));

def other as sheet.Sheet init sheet.newSheet("Second Sheet");
$other = sheet.setCell($other, "A1", sheet.text("hello"));

def wb as sheet.Workbook init sheet.newWorkbook();
$wb = sheet.addSheet($wb, $s);
$wb = sheet.addSheet($wb, $other);

# A date renders differently per application and locale, so the row carrying
# it is matched by a marker rather than compared verbatim.
def expectedDated as string init "Name,Qty,Price\n" +
    "Widget & Co,4,9.99\n" +
    "Gadget,2,19.98\n" +
    ",,<DATE>\n" +
    "TRUE,,\n";

for (def ext in [".ods", ".xlsx", ".gnumeric"]) {
    def target as string init path.join($dir, "fixture" + $ext);
    sheet.save($wb, $target);
    io.printf("wrote %s (%d bytes)\n", path.base($target), len(fs.readBytes($target)));
}

# What a converter has to produce, cell for cell. Written per format, since
# the formats genuinely differ in what they can hold - though all three now
# agree on this fixture: the Gnumeric codec used to carry no styles, so its
# date arrived as the bare serial 46297, and it carries them now.
#
# The date is matched loosely (see tools/validate-output.sh), because how a
# date renders is the application's business and its locale's.
for (def kind in ["ods", "xlsx", "gnumeric"]) {
    fs.writeString(path.join($dir, "expected-" + $kind + ".csv"), $expectedDated);
}
io.printf("wrote the expected values\n");
