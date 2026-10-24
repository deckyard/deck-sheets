#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.25.0

/**
 * formulas example - compute a sheet rather than waiting for Excel to.
 *
 * Builds an order book with formula cells and recalculates it, then shows
 * that errors are values, that IF is lazy, and that a cycle yields #REF!:
 *   jennifer run examples/formulas.j
 */

use io;
use convert;

import "../src/sheets.j" as sheet;

# Quantity, unit price, line total, then a VAT line and a total.
def orders as sheet.Sheet init sheet.sheetOf(
    "Orders",
    [
        [sheet.text("Item"), sheet.text("Qty"), sheet.text("Unit"), sheet.text("Total")],
        [sheet.text("Bolt"), sheet.integer(120), sheet.number(0.35), sheet.formula("B2*C2", "")],
        [sheet.text("Nut"), sheet.integer(120), sheet.number(0.12), sheet.formula("B3*C3", "")],
        [sheet.text("Washer"), sheet.integer(240), sheet.number(0.04), sheet.formula("B4*C4", "")],
        [sheet.text("Net"), sheet.empty(), sheet.empty(), sheet.formula("SUM(D2:D4)", "")],
        [sheet.text("VAT"), sheet.empty(), sheet.empty(), sheet.formula("ROUND(D5*0.2,2)", "")],
        [sheet.text("Gross"), sheet.empty(), sheet.empty(), sheet.formula("D5+D6", "")],
        [sheet.text("Avg line"), sheet.empty(), sheet.empty(), sheet.formula("AVERAGE(D2:D4)", "")],
        [sheet.text("Biggest"), sheet.empty(), sheet.empty(), sheet.formula("MAX(D2:D4)", "")],
        [
            sheet.text("Over 20?"),
            sheet.empty(),
            sheet.empty(),
            sheet.formula("IF(D7>20,\"yes\",\"no\")", "")
        ]
    ]);

def book as sheet.Workbook init sheet.addSheet(sheet.newWorkbook(), $orders);

# One expression, without touching the sheet.
io.printf(
    "net of the three lines: %s\n",
    sheet.asString(sheet.evaluate($book, "Orders", "=SUM(D2:D4)")));

# Or recalculate the whole sheet and write the results into the cells.
def done as sheet.Recalculated init sheet.recalculate($book, "Orders");
io.printf("recalculated %d formulas, %d of them errors\n\n", $done.evaluated, $done.failed);

for (def r in 1..10) {
    def line as string init convert.toString($r + 1);
    def label as string init sheet.asString(sheet.cell($done.sheet, "A" + $line));
    def value as string init sheet.asString(sheet.cell($done.sheet, "D" + $line));
    io.printf("  %s = %s\n", $label, $value);
}

# An error is a value, not a throw, exactly as in a spreadsheet.
io.printf(
    "\n1/0 is %s, and IFERROR catches it: %s\n",
    sheet.asString(sheet.evaluate($book, "Orders", "1/0")),
    sheet.asString(sheet.evaluate($book, "Orders", "IFERROR(1/0,\"n/a\")")));

# IF is lazy, so the guard actually guards.
io.printf(
    "IF(C9=0,0,D5/C9) is %s rather than #DIV/0!\n",
    sheet.asString(sheet.evaluate($book, "Orders", "IF(C9=0,0,D5/C9)")));

# A cycle is reported, not hung on.
def loop as sheet.Workbook init sheet.addSheet(
    sheet.newWorkbook(),
    sheet.sheetOf("Loop", [[sheet.formula("A2", "")], [sheet.formula("A1", "")]]));
io.printf("a mutual reference is %s\n", sheet.asString(sheet.evaluate($loop, "Loop", "A1")));

# And where a spreadsheet is not a programming language.
for (def odd in ["2^3^2", "-2^2", "MOD(-7,3)", "\"beta\"=\"BETA\"", "0^-1"]) {
    io.printf("  %s is %s\n", $odd, sheet.asString(sheet.evaluate($book, "Orders", $odd)));
}
