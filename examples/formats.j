#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * formats example - the value against what a person sees.
 *
 * Prints each cell's value beside what its number format displays:
 *   jennifer run examples/formats.j
 */

use io;
use time;
use strings;
use convert;

import "../src/sheets.j" as sheet;

# An invoice: a quantity, a unit price, a share and a date.
def invoice as sheet.Sheet init sheet.sheetOf(
    "Invoice",
    [
        [
            sheet.text("Part"),
            sheet.text("Qty"),
            sheet.text("Unit"),
            sheet.text("Share"),
            sheet.text("Due")
        ],
        [
            sheet.text("Bolt"),
            sheet.integer(1240),
            sheet.number(0.47),
            sheet.number(0.075),
            sheet.date(time.fromIso("2026-10-02T00:00:00Z"))
        ],
        [
            sheet.text("Washer"),
            sheet.integer(18),
            sheet.number(1234.5),
            sheet.number(0.5),
            sheet.date(time.fromIso("2026-12-24T00:00:00Z"))
        ],
        [
            sheet.text("Credit"),
            sheet.integer(-4),
            sheet.number(-20.0),
            sheet.number(0.0),
            sheet.date(time.fromIso("2027-01-05T00:00:00Z"))
        ]
    ]);

$invoice = sheet.setAreaStyle($invoice, "B2:B4", sheet.withFormat(sheet.style(), "#,##0"));
# Two sections, so a credit shows in brackets rather than with a minus.
$invoice = sheet.setAreaStyle(
    $invoice,
    "C2:C4",
    sheet.withFormat(sheet.style(), "$#,##0.00;($#,##0.00)"));
$invoice = sheet.setAreaStyle($invoice, "D2:D4", sheet.withFormat(sheet.style(), "0.0%"));
$invoice = sheet.setAreaStyle($invoice, "E2:E4", sheet.withFormat(sheet.style(), "d mmm yyyy"));

io.printf("what a program reads, against what a person sees:\n\n");
for (def r in 1..4) {
    def line as string init convert.toString($r + 1);
    for (def column in ["B", "C", "D", "E"]) {
        def at as string init $column + $line;
        io.printf(
            "  %s  value %s  shown %s\n",
            $at,
            padTo(sheet.asString(sheet.cell($invoice, $at)), 12),
            sheet.displayAt($invoice, $at));
    }
}

# A whole sheet at once, which is the call to prefer: one cell at a time
# across the module boundary costs 155x what taking a row does.
io.printf("\nthe sheet as it looks:\n\n");
for (def shown in sheet.displayRows($invoice)) {
    io.printf("  %s\n", strings.join($shown, "  "));
}

# A code can be applied without a cell, which is what `TEXT` does in a sheet.
io.printf("\none value through several codes:\n\n");
for (def code in ["0", "0.00", "#,##0.00", "0.0%", "0.00E+00", "# ?/?", "[>1000]0.0,\"k\";0.00"]) {
    io.printf("  %s  ->  %s\n", padTo($code, 22), sheet.applyFormat(sheet.number(1234.567), $code));
}

/**
 * Pad text out to a width, so two columns line up.
 *
 * @param body {string} the text
 * @param width {int} the width to reach
 * @return {string} the padded text
 */
func padTo(body as string, width as int) {
    def out as string init $body;
    while (len($out) < $width) {
        $out = $out + " ";
    }
    return $out;
}
