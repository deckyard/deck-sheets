#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * exporting example - the same sheet as a page, as records and as paper.
 *
 * Writes a styled sheet as HTML, JSON, JSON Lines and PDF:
 *   jennifer run examples/exporting.j
 */

use io;
use strings;
use fs;
use path;
use os;

import "../src/sheets.j" as sheet;

def dir as string init fs.makeTempDir(os.tempDir(), "sheets-export");
defer fs.removeAll($dir);

def report as sheet.Sheet init sheet.sheetOf(
    "Stock",
    [
        [sheet.text("Part"), sheet.text("On hand"), sheet.text("Unit")],
        [sheet.text("Bolt & nut"), sheet.integer(1240), sheet.number(0.47)],
        [sheet.text("Washer"), sheet.integer(18), sheet.number(0.04)],
        [sheet.text("Bracket"), sheet.empty(), sheet.number(2.15)]
    ]);

# A bold header on a fill, so the exports have something to carry over.
def heading as sheet.Style init sheet.withBackground(
    sheet.withBold(sheet.style(), true),
    "#eeeeee");
$report = sheet.setAreaStyle($report, "A1:C1", $heading);

# One page, standalone: doctype, charset, title, inline styles.
def page as string init path.join($dir, "stock.html");
fs.writeString($page, sheet.toHtmlDocument($report, "Stock on hand"));
io.printf("wrote %s (%d bytes)\n", path.base($page), len(fs.readString($page)));

# Records, keyed by the header row. Every value is the cell's rendering.
def records as list of map of string to string init sheet.toRecords($report);
io.printf(
    "%d records, first part is %s with %s on hand\n",
    len($records),
    $records[0]["Part"],
    $records[0]["On hand"]);

# A blank cell is an empty field rather than a missing key.
io.printf("the bracket's count is %s (empty, not absent)\n", quotedField($records[2]["On hand"]));

def jsonl as string init path.join($dir, "stock.jsonl");
fs.writeString($jsonl, sheet.toJsonLines($report));
for (def line in strings.split(strings.trim(fs.readString($jsonl)), "\n")) {
    io.printf("  %s\n", $line);
}

# Paper. The header repeats on every page and a long cell is truncated
# rather than overflowing into the next column.
def paper as string init path.join($dir, "stock.pdf");
fs.writeBytes($paper, sheet.toPdf($report, sheet.a4()));
io.printf("wrote %s (%d bytes, A4 portrait)\n", path.base($paper), len(fs.readBytes($paper)));

/**
 * Show a field with its quotes, so an empty one is visible.
 *
 * @param body {string} the field
 * @return {string} the field in quotes
 */
func quotedField(body as string) {
    return "\"" + $body + "\"";
}
